package httpapi

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"

	"walkietalkie/backend/internal/auth"
	"walkietalkie/backend/internal/channel"
	"walkietalkie/backend/internal/config"
	"walkietalkie/backend/internal/media"
	"walkietalkie/backend/internal/models"
	"walkietalkie/backend/internal/push"
	"walkietalkie/backend/internal/realtime"
	"walkietalkie/backend/internal/repository"
)

type RouterDeps struct {
	Config         config.Config
	AuthService    *auth.Service
	ChannelService *channel.Service
	Database       interface{ Ping(context.Context) error }
	RedisClient    interface {
		Ping(context.Context) *redis.StatusCmd
		Incr(context.Context, string) *redis.IntCmd
		Expire(context.Context, string, time.Duration) *redis.BoolCmd
		TTL(context.Context, string) *redis.DurationCmd
	}
	UserRepo     userRepository
	ChannelRepo  channelRepository
	InviteRepo   inviteRepository
	AuditRepo    auditRepository
	DeviceRepo   deviceRepository
	TokenRepo    tokenRepository
	MediaService *media.LiveKitService
	PushService  push.Service
	RealtimeHub  *realtime.Hub
	Upgrader     websocket.Upgrader
}

type userRepository interface {
	Create(context.Context, string, string, string) (models.User, error)
	GetByEmail(context.Context, string) (models.User, error)
	GetByID(context.Context, string) (models.User, error)
}

type channelRepository interface {
	ListByUser(context.Context, string) ([]models.Channel, error)
	GetByID(context.Context, string) (models.Channel, error)
	UserHasMembership(context.Context, string, string) (bool, error)
	GetMembershipRole(context.Context, string, string) (string, error)
	ListMemberships(context.Context, string) ([]models.ChannelMembership, error)
	UpsertMembershipRole(context.Context, string, string, string) (models.ChannelMembership, error)
	TransferOwnership(context.Context, string, string) (models.ChannelMembership, error)
	DeleteMembership(context.Context, string, string) error
	CountMembersByRole(context.Context, string, string) (int, error)
	Create(context.Context, string, string, string) (models.Channel, error)
	AddMember(context.Context, string, string, string) error
	Update(context.Context, string, string, string) (models.Channel, error)
}

type inviteRepository interface {
	Create(context.Context, string, string, string, time.Time, int) (models.Invite, error)
	GetValidByHash(context.Context, string) (models.Invite, error)
	GetByID(context.Context, string) (models.Invite, error)
	IncrementUsage(context.Context, string) error
	Revoke(context.Context, string, string) error
	ListByChannel(context.Context, string, int) ([]models.Invite, error)
}

type auditRepository interface {
	Create(context.Context, string, string, string, string, map[string]any) error
	ListByChannel(context.Context, string, int) ([]models.AuditEvent, error)
}

type deviceRepository interface {
	ListByUserID(context.Context, string) ([]models.Device, error)
	Upsert(context.Context, string, string, string, string) (models.Device, error)
}

type tokenRepository interface {
	GetByHash(context.Context, string) (repository.RefreshTokenRecord, error)
	Create(context.Context, string, string, time.Time) error
	DeleteByHash(context.Context, string) error
	DeleteByUserID(context.Context, string) error
}

type pushStatsProvider interface {
	Stats(context.Context) push.QueueStats
}

func recordAuditEvent(
	ctx context.Context,
	repo auditRepository,
	actorUserID string,
	action string,
	resourceType string,
	resourceID string,
	metadata map[string]any,
) {
	if repo == nil {
		return
	}
	_ = repo.Create(ctx, actorUserID, action, resourceType, resourceID, metadata)
}

func parseListLimit(raw string, fallback int) (int, error) {
	if raw == "" {
		return fallback, nil
	}
	limit, err := strconv.Atoi(raw)
	if err != nil {
		return 0, fmt.Errorf("invalid limit")
	}
	if limit <= 0 || limit > 200 {
		return 0, fmt.Errorf("limit out of range")
	}
	return limit, nil
}

func channelRoleAllowed(role string, allowed ...string) bool {
	for _, item := range allowed {
		if role == item {
			return true
		}
	}
	return false
}

func requireChannelRole(c *gin.Context, repo channelRepository, channelID string, allowed ...string) (string, bool) {
	role, err := repo.GetMembershipRole(c.Request.Context(), channelID, c.GetString("userID"))
	if err != nil || !channelRoleAllowed(role, allowed...) {
		requiredRole := "channel membership required"
		if len(allowed) > 0 {
			requiredRole = "insufficient channel role"
		}
		c.JSON(http.StatusForbidden, gin.H{"error": requiredRole})
		return "", false
	}
	return role, true
}

type JoinChannelResponse struct {
	ChannelID     string   `json:"channelId"`
	LiveKitURL    string   `json:"livekitUrl"`
	LiveKitToken  string   `json:"livekitToken"`
	IceServers    []string `json:"iceServers"`
	WebSocketURL  string   `json:"webSocketUrl"`
	ActiveSpeaker string   `json:"activeSpeaker,omitempty"`
}

func NewRouter(deps RouterDeps) *gin.Engine {
	router := gin.Default()

	router.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	router.GET("/healthz/push", func(c *gin.Context) {
		statsProvider, ok := deps.PushService.(pushStatsProvider)
		if !ok {
			c.JSON(http.StatusOK, gin.H{
				"status":       "ok",
				"pushObserved": false,
			})
			return
		}

		stats := statsProvider.Stats(c.Request.Context())
		c.JSON(http.StatusOK, gin.H{
			"status":       "ok",
			"pushObserved": true,
			"pushQueue":    stats,
		})
	})

	router.GET("/healthz/diagnostics", func(c *gin.Context) {
		dbStatus := "unknown"
		redisStatus := "unknown"

		if deps.Database != nil {
			if err := deps.Database.Ping(c.Request.Context()); err != nil {
				dbStatus = "error"
			} else {
				dbStatus = "ok"
			}
		}

		if deps.RedisClient != nil {
			if err := deps.RedisClient.Ping(c.Request.Context()).Err(); err != nil {
				redisStatus = "error"
			} else {
				redisStatus = "ok"
			}
		}

		pushObserved := false
		var pushQueue any
		if statsProvider, ok := deps.PushService.(pushStatsProvider); ok {
			pushObserved = true
			pushQueue = statsProvider.Stats(c.Request.Context())
		}

		statusCode := http.StatusOK
		overallStatus := "ok"
		if dbStatus == "error" || redisStatus == "error" {
			statusCode = http.StatusServiceUnavailable
			overallStatus = "degraded"
		}

		c.JSON(statusCode, gin.H{
			"status": overallStatus,
			"dependencies": gin.H{
				"database": dbStatus,
				"redis":    redisStatus,
			},
			"pushObserved": pushObserved,
			"pushQueue":    pushQueue,
		})
	})

	authRegisterLimit := RateLimitMiddleware(deps.RedisClient, "auth_register", 10, time.Minute, EmailOrIPKey)
	authLoginLimit := RateLimitMiddleware(deps.RedisClient, "auth_login", 20, time.Minute, EmailOrIPKey)

	router.POST("/v1/auth/register", authRegisterLimit, func(c *gin.Context) {
		var req struct {
			Email       string `json:"email"`
			DisplayName string `json:"displayName"`
			Password    string `json:"password"`
		}
		if err := c.ShouldBindBodyWithJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
			return
		}

		hash, err := deps.AuthService.HashPassword(req.Password)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
			return
		}

		user, err := deps.UserRepo.Create(c.Request.Context(), req.Email, req.DisplayName, hash)
		if err != nil {
			c.JSON(http.StatusConflict, gin.H{"error": "user could not be created"})
			return
		}

		token, err := deps.AuthService.IssueAccessToken(user.ID, user.Email)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to issue token"})
			return
		}

		refreshRaw, refreshHash, refreshExpiry, err := deps.AuthService.NewRefreshToken()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to issue refresh token"})
			return
		}
		if err := deps.TokenRepo.Create(c.Request.Context(), user.ID, refreshHash, refreshExpiry); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to persist refresh token"})
			return
		}

		c.JSON(http.StatusCreated, gin.H{
			"user":         user,
			"accessToken":  token,
			"refreshToken": refreshRaw,
		})
	})

	router.POST("/v1/auth/login", authLoginLimit, func(c *gin.Context) {
		var req struct {
			Email    string `json:"email"`
			Password string `json:"password"`
		}
		if err := c.ShouldBindBodyWithJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
			return
		}

		user, err := deps.UserRepo.GetByEmail(c.Request.Context(), req.Email)
		if err != nil || !deps.AuthService.VerifyPassword(req.Password, user.PasswordHash) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
			return
		}

		token, err := deps.AuthService.IssueAccessToken(user.ID, user.Email)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to issue token"})
			return
		}

		refreshRaw, refreshHash, refreshExpiry, err := deps.AuthService.NewRefreshToken()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to issue refresh token"})
			return
		}
		if err := deps.TokenRepo.Create(c.Request.Context(), user.ID, refreshHash, refreshExpiry); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to persist refresh token"})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"user":         user,
			"accessToken":  token,
			"refreshToken": refreshRaw,
		})
	})

	router.POST("/v1/auth/refresh", func(c *gin.Context) {
		var req struct {
			RefreshToken string `json:"refreshToken"`
		}
		if err := c.ShouldBindJSON(&req); err != nil || req.RefreshToken == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
			return
		}

		record, err := deps.TokenRepo.GetByHash(c.Request.Context(), deps.AuthService.HashOpaqueToken(req.RefreshToken))
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid refresh token"})
			return
		}
		if record.ExpiresAt.Before(time.Now()) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "refresh token expired"})
			return
		}

		user, err := deps.UserRepo.GetByID(c.Request.Context(), record.UserID)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
			return
		}

		token, err := deps.AuthService.IssueAccessToken(user.ID, user.Email)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to issue token"})
			return
		}

		newRefreshRaw, newRefreshHash, newRefreshExpiry, err := deps.AuthService.NewRefreshToken()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to rotate refresh token"})
			return
		}
		if err := deps.TokenRepo.DeleteByHash(c.Request.Context(), record.TokenHash); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to revoke old refresh token"})
			return
		}
		if err := deps.TokenRepo.Create(c.Request.Context(), user.ID, newRefreshHash, newRefreshExpiry); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to persist rotated refresh token"})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"user":         user,
			"accessToken":  token,
			"refreshToken": newRefreshRaw,
		})
	})

	v1 := router.Group("/v1")
	v1.Use(AuthMiddleware(deps.AuthService))
	{
		v1.POST("/auth/logout", func(c *gin.Context) {
			var req struct {
				RefreshToken string `json:"refreshToken"`
				AllDevices   bool   `json:"allDevices"`
			}
			if err := c.ShouldBindJSON(&req); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
				return
			}

			if req.AllDevices {
				if err := deps.TokenRepo.DeleteByUserID(c.Request.Context(), c.GetString("userID")); err != nil {
					c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to revoke user sessions"})
					return
				}
			} else if req.RefreshToken != "" {
				if err := deps.TokenRepo.DeleteByHash(c.Request.Context(), deps.AuthService.HashOpaqueToken(req.RefreshToken)); err != nil {
					c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to revoke refresh token"})
					return
				}
			}

			c.JSON(http.StatusOK, gin.H{"loggedOut": true})
		})

		v1.GET("/me", func(c *gin.Context) {
			user, err := deps.UserRepo.GetByID(c.Request.Context(), c.GetString("userID"))
			if err != nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
				return
			}
			c.JSON(http.StatusOK, gin.H{"user": user})
		})

		v1.GET("/channels", func(c *gin.Context) {
			channels, err := deps.ChannelRepo.ListByUser(c.Request.Context(), c.GetString("userID"))
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list channels"})
				return
			}
			c.JSON(http.StatusOK, gin.H{"channels": channels})
		})

		v1.POST("/channels", func(c *gin.Context) {
			var req struct {
				Name string `json:"name"`
				Type string `json:"type"`
			}
			if err := c.ShouldBindJSON(&req); err != nil || req.Name == "" {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
				return
			}
			if req.Type == "" {
				req.Type = "private"
			}

			channel, err := deps.ChannelRepo.Create(c.Request.Context(), c.GetString("userID"), req.Name, req.Type)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create channel"})
				return
			}
			c.JSON(http.StatusCreated, gin.H{"channel": channel})
		})

		v1.PATCH("/channels/:id", func(c *gin.Context) {
			channelID := c.Param("id")
			role, ok := requireChannelRole(c, deps.ChannelRepo, channelID, "owner", "admin", "member")
			if !ok {
				return
			}

			channelItem, err := deps.ChannelRepo.GetByID(c.Request.Context(), channelID)
			if err != nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "channel not found"})
				return
			}

			var req struct {
				Name *string `json:"name"`
				Type *string `json:"type"`
			}
			if err := c.ShouldBindJSON(&req); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
				return
			}
			if req.Name == nil && req.Type == nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "no channel changes provided"})
				return
			}

			nextName := channelItem.Name
			nextType := channelItem.Type

			if req.Name != nil {
				if !channelRoleAllowed(role, "owner", "admin") {
					c.JSON(http.StatusForbidden, gin.H{"error": "channel admin role required"})
					return
				}
				if strings.TrimSpace(*req.Name) == "" {
					c.JSON(http.StatusBadRequest, gin.H{"error": "channel name required"})
					return
				}
				nextName = strings.TrimSpace(*req.Name)
			}

			if req.Type != nil {
				if !channelRoleAllowed(role, "owner") {
					c.JSON(http.StatusForbidden, gin.H{"error": "channel owner role required"})
					return
				}
				if *req.Type != "public" && *req.Type != "private" {
					c.JSON(http.StatusBadRequest, gin.H{"error": "invalid channel type"})
					return
				}
				nextType = *req.Type
			}

			channelItem, err = deps.ChannelRepo.Update(c.Request.Context(), channelID, nextName, nextType)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update channel"})
				return
			}

			recordAuditEvent(c.Request.Context(), deps.AuditRepo, c.GetString("userID"), "channel.updated", "channel", channelID, map[string]any{
				"channelId": channelID,
				"name":      channelItem.Name,
				"type":      channelItem.Type,
			})

			c.JSON(http.StatusOK, gin.H{"channel": channelItem})
		})

		v1.GET("/channels/:id/members", func(c *gin.Context) {
			channelID := c.Param("id")
			if _, ok := requireChannelRole(c, deps.ChannelRepo, channelID, "owner", "admin"); !ok {
				return
			}

			memberships, err := deps.ChannelRepo.ListMemberships(c.Request.Context(), channelID)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list channel members"})
				return
			}

			c.JSON(http.StatusOK, gin.H{"members": memberships})
		})

		v1.PUT("/channels/:id/members/:userId", func(c *gin.Context) {
			channelID := c.Param("id")
			targetUserID := c.Param("userId")
			actorUserID := c.GetString("userID")

			actorRole, ok := requireChannelRole(c, deps.ChannelRepo, channelID, "owner", "admin")
			if !ok {
				return
			}

			var req struct {
				Role string `json:"role"`
			}
			if err := c.ShouldBindJSON(&req); err != nil || req.Role == "" {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
				return
			}
			if req.Role != "admin" && req.Role != "member" && req.Role != "owner" {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid membership role"})
				return
			}

			channelItem, err := deps.ChannelRepo.GetByID(c.Request.Context(), channelID)
			if err != nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "channel not found"})
				return
			}

			if actorRole != "owner" {
				if req.Role != "member" {
					c.JSON(http.StatusForbidden, gin.H{"error": "channel owner role required"})
					return
				}
				targetRole, err := deps.ChannelRepo.GetMembershipRole(c.Request.Context(), channelID, targetUserID)
				if err == nil && targetRole != "member" {
					c.JSON(http.StatusForbidden, gin.H{"error": "admin can manage members only"})
					return
				}
			}

			if req.Role == "owner" && actorUserID != channelItem.OwnerUserID {
				c.JSON(http.StatusForbidden, gin.H{"error": "channel owner role required"})
				return
			}

			var membership models.ChannelMembership
			if req.Role == "owner" {
				membership, err = deps.ChannelRepo.TransferOwnership(c.Request.Context(), channelID, targetUserID)
				if err != nil {
					c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to transfer channel ownership"})
					return
				}
			} else {
				membership, err = deps.ChannelRepo.UpsertMembershipRole(c.Request.Context(), channelID, targetUserID, req.Role)
				if err != nil {
					c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update channel member"})
					return
				}
			}

			recordAuditEvent(c.Request.Context(), deps.AuditRepo, actorUserID, "channel.member.upserted", "channel_membership", channelID+":"+targetUserID, map[string]any{
				"channelId": channelID,
				"userId":    targetUserID,
				"role":      membership.Role,
			})

			c.JSON(http.StatusOK, gin.H{"member": membership})
		})

		v1.DELETE("/channels/:id/members/:userId", func(c *gin.Context) {
			channelID := c.Param("id")
			targetUserID := c.Param("userId")
			actorUserID := c.GetString("userID")

			actorRole, ok := requireChannelRole(c, deps.ChannelRepo, channelID, "owner", "admin")
			if !ok {
				return
			}

			targetRole, err := deps.ChannelRepo.GetMembershipRole(c.Request.Context(), channelID, targetUserID)
			if err != nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "channel member not found"})
				return
			}

			channelItem, err := deps.ChannelRepo.GetByID(c.Request.Context(), channelID)
			if err != nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "channel not found"})
				return
			}

			if actorRole != "owner" {
				if targetRole != "member" {
					c.JSON(http.StatusForbidden, gin.H{"error": "admin can remove members only"})
					return
				}
			}

			if targetRole == "owner" {
				if actorUserID != channelItem.OwnerUserID {
					c.JSON(http.StatusForbidden, gin.H{"error": "channel owner role required"})
					return
				}
				ownerCount, err := deps.ChannelRepo.CountMembersByRole(c.Request.Context(), channelID, "owner")
				if err != nil {
					c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to verify owner count"})
					return
				}
				if ownerCount <= 1 {
					c.JSON(http.StatusBadRequest, gin.H{"error": "cannot remove last channel owner"})
					return
				}
			}

			if err := deps.ChannelRepo.DeleteMembership(c.Request.Context(), channelID, targetUserID); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove channel member"})
				return
			}

			recordAuditEvent(c.Request.Context(), deps.AuditRepo, actorUserID, "channel.member.removed", "channel_membership", channelID+":"+targetUserID, map[string]any{
				"channelId": channelID,
				"userId":    targetUserID,
				"role":      targetRole,
			})

			c.JSON(http.StatusOK, gin.H{"removed": true})
		})

		v1.POST(
			"/channels/:id/invites",
			RateLimitMiddleware(deps.RedisClient, "channel_invites", 30, time.Minute, UserOrIPKey),
			func(c *gin.Context) {
				channelID := c.Param("id")
				userID := c.GetString("userID")
				var req struct {
					TargetUserID string `json:"targetUserId"`
					MaxUses      int    `json:"maxUses"`
					ExpiresInHrs int    `json:"expiresInHours"`
				}
				if err := c.ShouldBindJSON(&req); err != nil && err.Error() != "EOF" {
					c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
					return
				}

				if _, ok := requireChannelRole(c, deps.ChannelRepo, channelID, "owner", "admin"); !ok {
					return
				}

				rawToken, tokenHash, err := deps.AuthService.NewOpaqueToken()
				if err != nil {
					c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate invite token"})
					return
				}

				maxUses := req.MaxUses
				if maxUses <= 0 {
					maxUses = 10
				}
				expiresAt := time.Now().Add(24 * time.Hour)
				if req.ExpiresInHrs > 0 {
					expiresAt = time.Now().Add(time.Duration(req.ExpiresInHrs) * time.Hour)
				}

				invite, err := deps.InviteRepo.Create(
					c.Request.Context(),
					channelID,
					userID,
					tokenHash,
					expiresAt,
					maxUses,
				)
				if err != nil {
					c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create invite"})
					return
				}

				recordAuditEvent(c.Request.Context(), deps.AuditRepo, userID, "invite.created", "channel_invite", invite.ID, map[string]any{
					"channelId":    channelID,
					"targetUserId": req.TargetUserID,
					"maxUses":      invite.MaxUses,
				})

				pushQueued := false
				if req.TargetUserID != "" {
					channelItem, err := deps.ChannelRepo.GetByID(c.Request.Context(), channelID)
					if err != nil {
						c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load channel for invite notification"})
						return
					}

					devices, err := deps.DeviceRepo.ListByUserID(c.Request.Context(), req.TargetUserID)
					if err != nil {
						c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load target devices"})
						return
					}

					targets := make([]push.DeviceTarget, 0, len(devices))
					for _, device := range devices {
						targets = append(targets, push.DeviceTarget{
							UserID:    device.UserID,
							Platform:  push.Platform(device.Platform),
							PushToken: device.PushToken,
						})
					}

					if len(targets) > 0 {
						if err := deps.PushService.SendInvite(c.Request.Context(), push.InviteNotification{
							UserID:      req.TargetUserID,
							ChannelID:   channelID,
							ChannelName: channelItem.Name,
							InviteToken: rawToken,
							Targets:     targets,
						}); err == nil {
							pushQueued = true
						}
					}
				}

				c.JSON(http.StatusCreated, gin.H{
					"invite": gin.H{
						"id":        invite.ID,
						"channelId": invite.ChannelID,
						"expiresAt": invite.ExpiresAt,
						"maxUses":   invite.MaxUses,
					},
					"inviteToken": rawToken,
					"pushQueued":  pushQueued,
				})
			})

		v1.GET("/channels/:id/invites", func(c *gin.Context) {
			channelID := c.Param("id")

			if _, ok := requireChannelRole(c, deps.ChannelRepo, channelID, "owner", "admin"); !ok {
				return
			}

			limit, err := parseListLimit(c.Query("limit"), 50)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}

			invites, err := deps.InviteRepo.ListByChannel(c.Request.Context(), channelID, limit)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list invites"})
				return
			}

			c.JSON(http.StatusOK, gin.H{"invites": invites})
		})

		v1.POST("/channels/:id/invites/:inviteId/revoke", func(c *gin.Context) {
			channelID := c.Param("id")
			inviteID := c.Param("inviteId")
			userID := c.GetString("userID")

			if _, ok := requireChannelRole(c, deps.ChannelRepo, channelID, "owner", "admin"); !ok {
				return
			}

			invite, err := deps.InviteRepo.GetByID(c.Request.Context(), inviteID)
			if err != nil || invite.ChannelID != channelID {
				c.JSON(http.StatusNotFound, gin.H{"error": "invite not found"})
				return
			}

			channelItem, err := deps.ChannelRepo.GetByID(c.Request.Context(), channelID)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load channel"})
				return
			}

			if invite.CreatedBy != userID && channelItem.OwnerUserID != userID {
				c.JSON(http.StatusForbidden, gin.H{"error": "invite revoke not allowed"})
				return
			}

			if invite.RevokedAt != nil {
				c.JSON(http.StatusOK, gin.H{"revoked": true, "invite": invite})
				return
			}

			if err := deps.InviteRepo.Revoke(c.Request.Context(), inviteID, userID); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to revoke invite"})
				return
			}

			updatedInvite, err := deps.InviteRepo.GetByID(c.Request.Context(), inviteID)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load revoked invite"})
				return
			}

			recordAuditEvent(c.Request.Context(), deps.AuditRepo, userID, "invite.revoked", "channel_invite", inviteID, map[string]any{
				"channelId": channelID,
			})

			c.JSON(http.StatusOK, gin.H{
				"revoked": true,
				"invite":  updatedInvite,
			})
		})

		v1.GET("/channels/:id/audit-events", func(c *gin.Context) {
			channelID := c.Param("id")

			if _, ok := requireChannelRole(c, deps.ChannelRepo, channelID, "owner", "admin"); !ok {
				return
			}

			limit, err := parseListLimit(c.Query("limit"), 50)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}

			events, err := deps.AuditRepo.ListByChannel(c.Request.Context(), channelID, limit)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list audit events"})
				return
			}

			c.JSON(http.StatusOK, gin.H{"events": events})
		})

		v1.POST("/channels/:id/join", func(c *gin.Context) {
			channelID := c.Param("id")
			userID := c.GetString("userID")

			member, err := deps.ChannelRepo.UserHasMembership(c.Request.Context(), channelID, userID)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to validate membership"})
				return
			}
			if !member {
				c.JSON(http.StatusForbidden, gin.H{"error": "channel membership required"})
				return
			}

			activeSpeaker := deps.ChannelService.ActiveSpeaker(c.Request.Context(), channelID)
			liveKitToken, err := deps.MediaService.IssueRoomToken(userID, channelID, false)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to issue media token"})
				return
			}

			resp := JoinChannelResponse{
				ChannelID:    channelID,
				LiveKitURL:   deps.Config.LiveKitURL,
				LiveKitToken: liveKitToken,
				IceServers: []string{
					"stun:localhost:3478",
					"turn:localhost:3478?transport=udp",
					"turns:localhost:5349?transport=tcp",
				},
				WebSocketURL: deps.Config.WebSocketURL,
			}
			if activeSpeaker != "" {
				resp.ActiveSpeaker = activeSpeaker
			}

			c.JSON(http.StatusOK, resp)
		})

		v1.POST("/invites/:token/accept", func(c *gin.Context) {
			rawToken := c.Param("token")
			tokenHash := deps.AuthService.HashOpaqueToken(rawToken)

			invite, err := deps.InviteRepo.GetValidByHash(c.Request.Context(), tokenHash)
			if err != nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "invite not found or expired"})
				return
			}

			if err := deps.ChannelRepo.AddMember(c.Request.Context(), invite.ChannelID, c.GetString("userID"), "member"); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to add member"})
				return
			}

			if err := deps.InviteRepo.IncrementUsage(c.Request.Context(), invite.ID); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update invite usage"})
				return
			}

			recordAuditEvent(c.Request.Context(), deps.AuditRepo, c.GetString("userID"), "invite.accepted", "channel_invite", invite.ID, map[string]any{
				"channelId": invite.ChannelID,
			})

			c.JSON(http.StatusOK, gin.H{
				"channelId": invite.ChannelID,
				"joined":    true,
			})
		})

		v1.POST("/devices", func(c *gin.Context) {
			var req struct {
				Platform   string `json:"platform"`
				PushToken  string `json:"pushToken"`
				AppVersion string `json:"appVersion"`
			}
			if err := c.ShouldBindJSON(&req); err != nil || req.Platform == "" || req.PushToken == "" {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
				return
			}

			device, err := deps.DeviceRepo.Upsert(
				c.Request.Context(),
				c.GetString("userID"),
				req.Platform,
				req.PushToken,
				req.AppVersion,
			)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to register device"})
				return
			}

			c.JSON(http.StatusOK, gin.H{"device": device})
		})

		v1.GET(
			"/ws",
			RateLimitMiddleware(
				deps.RedisClient,
				"ws_connect",
				int64(deps.Config.WSConnectRateLimit),
				time.Duration(deps.Config.WSConnectWindowSec)*time.Second,
				UserOrIPKey,
			),
			func(c *gin.Context) {
				handleWS(
					c,
					deps.Upgrader,
					deps.ChannelService,
					deps.RealtimeHub,
					deps.Config.WSMessageRateLimit,
					time.Duration(deps.Config.WSMessageWindowSec)*time.Second,
				)
			})
	}

	return router
}
