package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"

	"walkietalkie/backend/internal/auth"
	"walkietalkie/backend/internal/config"
	"walkietalkie/backend/internal/models"
	"walkietalkie/backend/internal/push"
	"walkietalkie/backend/internal/repository"
)

type stubUserRepo struct{}

func (stubUserRepo) Create(context.Context, string, string, string) (models.User, error) {
	return models.User{ID: "user-1", Email: "demo@example.com"}, nil
}

func (stubUserRepo) GetByEmail(context.Context, string) (models.User, error) {
	return models.User{ID: "user-1", Email: "demo@example.com"}, nil
}

func (stubUserRepo) GetByID(context.Context, string) (models.User, error) {
	return models.User{ID: "user-1", Email: "demo@example.com"}, nil
}

type stubChannelRepo struct {
	roleByChannel map[string]string
	channelByID   map[string]models.Channel
	membersByID   map[string][]models.ChannelMembership
	memberRoles   map[string]string
	roleCounts    map[string]int
	createErr     error
	getByIDErr    error
	listMembersErr error
	upsertErr     error
	transferErr   error
	deleteErr     error
	updateErr     error
	countErr      error
}

func (s stubChannelRepo) ListByUser(context.Context, string) ([]models.Channel, error) {
	if s.channelByID != nil {
		channels := make([]models.Channel, 0, len(s.channelByID))
		for _, item := range s.channelByID {
			channels = append(channels, item)
		}
		return channels, nil
	}
	return []models.Channel{}, nil
}

func (s stubChannelRepo) GetByID(_ context.Context, channelID string) (models.Channel, error) {
	if s.getByIDErr != nil {
		return models.Channel{}, s.getByIDErr
	}
	if s.channelByID != nil {
		if item, ok := s.channelByID[channelID]; ok {
			return item, nil
		}
	}
	return models.Channel{ID: channelID, OwnerUserID: "owner-1"}, nil
}

func (s stubChannelRepo) UserHasMembership(_ context.Context, _ string, _ string) (bool, error) {
	return true, nil
}

func (s stubChannelRepo) GetMembershipRole(_ context.Context, channelID string, userID string) (string, error) {
	if s.memberRoles != nil {
		if role, ok := s.memberRoles[channelID+":"+userID]; ok {
			return role, nil
		}
	}
	if role, ok := s.roleByChannel[channelID]; ok {
		return role, nil
	}
	return "", context.Canceled
}

func (s stubChannelRepo) ListMemberships(_ context.Context, channelID string) ([]models.ChannelMembership, error) {
	if s.listMembersErr != nil {
		return nil, s.listMembersErr
	}
	if items, ok := s.membersByID[channelID]; ok {
		return items, nil
	}
	return []models.ChannelMembership{}, nil
}

func (s stubChannelRepo) UpsertMembershipRole(_ context.Context, channelID, userID, role string) (models.ChannelMembership, error) {
	if s.upsertErr != nil {
		return models.ChannelMembership{}, s.upsertErr
	}
	return models.ChannelMembership{
		ChannelID: channelID,
		UserID:    userID,
		Role:      role,
		JoinedAt:  time.Now(),
	}, nil
}

func (s stubChannelRepo) TransferOwnership(_ context.Context, channelID, userID string) (models.ChannelMembership, error) {
	if s.transferErr != nil {
		return models.ChannelMembership{}, s.transferErr
	}
	return models.ChannelMembership{
		ChannelID: channelID,
		UserID:    userID,
		Role:      "owner",
		JoinedAt:  time.Now(),
	}, nil
}

func (s stubChannelRepo) DeleteMembership(_ context.Context, _, _ string) error {
	if s.deleteErr != nil {
		return s.deleteErr
	}
	return nil
}

func (s stubChannelRepo) CountMembersByRole(_ context.Context, channelID, role string) (int, error) {
	if s.countErr != nil {
		return 0, s.countErr
	}
	if s.roleCounts != nil {
		if count, ok := s.roleCounts[channelID+":"+role]; ok {
			return count, nil
		}
	}
	return 0, nil
}

func (s stubChannelRepo) Create(context.Context, string, string, string) (models.Channel, error) {
	if s.createErr != nil {
		return models.Channel{}, s.createErr
	}
	return models.Channel{}, nil
}

func (s stubChannelRepo) AddMember(context.Context, string, string, string) error {
	return nil
}

func (s stubChannelRepo) Update(_ context.Context, channelID, name, channelType string) (models.Channel, error) {
	if s.updateErr != nil {
		return models.Channel{}, s.updateErr
	}
	return models.Channel{ID: channelID, Name: name, Type: channelType, OwnerUserID: "owner-1"}, nil
}

type stubInviteRepo struct {
	invites           []models.Invite
	invite            models.Invite
	getValidByHashErr error
	createErr         error
	getByIDErr        error
	incrementErr      error
	revokeErr         error
	listErr           error
}

func (s stubInviteRepo) Create(context.Context, string, string, string, time.Time, int) (models.Invite, error) {
	if s.createErr != nil {
		return models.Invite{}, s.createErr
	}
	return s.invite, nil
}

func (s stubInviteRepo) GetValidByHash(context.Context, string) (models.Invite, error) {
	if s.getValidByHashErr != nil {
		return models.Invite{}, s.getValidByHashErr
	}
	return s.invite, nil
}

func (s stubInviteRepo) GetByID(_ context.Context, _ string) (models.Invite, error) {
	if s.getByIDErr != nil {
		return models.Invite{}, s.getByIDErr
	}
	return s.invite, nil
}

func (s stubInviteRepo) IncrementUsage(context.Context, string) error {
	if s.incrementErr != nil {
		return s.incrementErr
	}
	return nil
}

func (s stubInviteRepo) Revoke(context.Context, string, string) error {
	if s.revokeErr != nil {
		return s.revokeErr
	}
	return nil
}

func (s stubInviteRepo) ListByChannel(context.Context, string, int) ([]models.Invite, error) {
	if s.listErr != nil {
		return nil, s.listErr
	}
	return s.invites, nil
}

type stubAuditRepo struct {
	events []models.AuditEvent
}

func (s stubAuditRepo) Create(context.Context, string, string, string, string, map[string]any) error {
	return nil
}

func (s stubAuditRepo) ListByChannel(context.Context, string, int) ([]models.AuditEvent, error) {
	return s.events, nil
}

type stubDeviceRepo struct {
	devices  []models.Device
	listErr  error
	upsertErr error
}

func (s stubDeviceRepo) ListByUserID(context.Context, string) ([]models.Device, error) {
	if s.listErr != nil {
		return nil, s.listErr
	}
	return s.devices, nil
}

func (s stubDeviceRepo) Upsert(context.Context, string, string, string, string) (models.Device, error) {
	if s.upsertErr != nil {
		return models.Device{}, s.upsertErr
	}
	return models.Device{}, nil
}

type recordingPushService struct {
	err          error
	notifications []push.InviteNotification
}

func (s *recordingPushService) SendInvite(_ context.Context, notification push.InviteNotification) error {
	s.notifications = append(s.notifications, notification)
	return s.err
}

type stubTokenRepo struct{}

func (stubTokenRepo) GetByHash(context.Context, string) (repository.RefreshTokenRecord, error) {
	return repository.RefreshTokenRecord{}, nil
}

func (stubTokenRepo) Create(context.Context, string, string, time.Time) error {
	return nil
}

func (stubTokenRepo) DeleteByHash(context.Context, string) error {
	return nil
}

func (stubTokenRepo) DeleteByUserID(context.Context, string) error {
	return nil
}

func newAuthorizedRequest(t *testing.T, method, path string, body string, authService *auth.Service) *http.Request {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	token, err := authService.IssueAccessToken("user-1", "demo@example.com")
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	return req
}

func TestCreateInviteRequiresAdminRole(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{roleByChannel: map[string]string{"channel-1": "member"}},
		InviteRepo:  stubInviteRepo{invite: models.Invite{ID: "invite-1", ChannelID: "channel-1"}},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPost, "/v1/channels/channel-1/invites", `{}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", rec.Code)
	}
}

func TestListChannelsReturnsMembershipRole(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			channelByID: map[string]models.Channel{
				"channel-1": {
					ID:          "channel-1",
					Name:        "Alpha",
					Type:        "private",
					OwnerUserID: "owner-1",
					Role:        "admin",
				},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodGet, "/v1/channels", "", authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var body struct {
		Channels []models.Channel `json:"channels"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if len(body.Channels) != 1 || body.Channels[0].Role != "admin" {
		t.Fatalf("unexpected channels payload: %#v", body.Channels)
	}
}

func TestAcceptInviteReturnsNotFoundWhenInviteRevoked(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{},
		InviteRepo:  stubInviteRepo{getValidByHashErr: errors.New("invite revoked")},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPost, "/v1/invites/revoked-token/accept", "", authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", rec.Code)
	}
}

func TestListInvitesAllowsAdminRole(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{roleByChannel: map[string]string{"channel-1": "admin"}},
		InviteRepo: stubInviteRepo{invites: []models.Invite{
			{ID: "invite-1", ChannelID: "channel-1", CreatedBy: "owner-1", MaxUses: 10, UsedCount: 1, CreatedAt: time.Now(), ExpiresAt: time.Now().Add(time.Hour)},
		}},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodGet, "/v1/channels/channel-1/invites?limit=10", "", authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var body struct {
		Invites []models.Invite `json:"invites"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if len(body.Invites) != 1 || body.Invites[0].ID != "invite-1" {
		t.Fatalf("unexpected invites payload: %#v", body.Invites)
	}
}

func TestAuditEventsRequireAdminRole(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{roleByChannel: map[string]string{"channel-1": "member"}},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodGet, "/v1/channels/channel-1/audit-events", "", authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", rec.Code)
	}
}

func TestListAuditEventsReturnsMetadata(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{roleByChannel: map[string]string{"channel-1": "owner"}},
		InviteRepo:  stubInviteRepo{},
		AuditRepo: stubAuditRepo{events: []models.AuditEvent{
			{
				ID:           "evt-1",
				ActorUserID:  "owner-1",
				Action:       "invite.created",
				ResourceType: "channel_invite",
				ResourceID:   "invite-1",
				Metadata:     json.RawMessage(`{"channelId":"channel-1","maxUses":10}`),
				CreatedAt:    time.Now(),
			},
		}},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodGet, "/v1/channels/channel-1/audit-events?limit=5", "", authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var body struct {
		Events []models.AuditEvent `json:"events"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if len(body.Events) != 1 || !strings.Contains(string(body.Events[0].Metadata), `"channel-1"`) {
		t.Fatalf("unexpected events payload: %#v", body.Events)
	}
}

func TestPatchChannelAllowsAdminRename(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "admin"},
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "owner-1"},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPatch, "/v1/channels/channel-1", `{"name":"Bravo"}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var body struct {
		Channel models.Channel `json:"channel"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Channel.Name != "Bravo" || body.Channel.Type != "private" {
		t.Fatalf("unexpected channel payload: %#v", body.Channel)
	}
}

func TestPatchChannelRejectsMemberRename(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "member"},
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "owner-1"},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPatch, "/v1/channels/channel-1", `{"name":"Bravo"}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", rec.Code)
	}
}

func TestPatchChannelRejectsAdminTypeChange(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "admin"},
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "owner-1"},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPatch, "/v1/channels/channel-1", `{"type":"public"}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", rec.Code)
	}
}

func TestListMembersAllowsAdmin(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "admin"},
			membersByID: map[string][]models.ChannelMembership{
				"channel-1": {
					{ChannelID: "channel-1", UserID: "owner-1", Role: "owner", JoinedAt: time.Now()},
					{ChannelID: "channel-1", UserID: "user-2", Role: "member", JoinedAt: time.Now()},
				},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodGet, "/v1/channels/channel-1/members", "", authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestAdminCannotPromoteMemberToAdmin(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "admin"},
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "owner-1"},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPut, "/v1/channels/channel-1/members/user-2", `{"role":"admin"}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", rec.Code)
	}
}

func TestOwnerCanPromoteMemberToAdmin(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "owner"},
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "user-1"},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPut, "/v1/channels/channel-1/members/user-2", `{"role":"admin"}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var body struct {
		Member models.ChannelMembership `json:"member"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Member.Role != "admin" || body.Member.UserID != "user-2" {
		t.Fatalf("unexpected member payload: %#v", body.Member)
	}
}

func TestOwnerCanTransferOwnership(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "owner"},
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "user-1"},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPut, "/v1/channels/channel-1/members/user-2", `{"role":"owner"}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var body struct {
		Member models.ChannelMembership `json:"member"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Member.Role != "owner" || body.Member.UserID != "user-2" {
		t.Fatalf("unexpected member payload: %#v", body.Member)
	}
}

func TestAdminCanRemoveMember(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "admin"},
			memberRoles:   map[string]string{"channel-1:user-2": "member"},
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "owner-1"},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodDelete, "/v1/channels/channel-1/members/user-2", "", authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestAdminCannotRemoveOwner(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "admin"},
			memberRoles:   map[string]string{"channel-1:owner-1": "owner"},
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "owner-1"},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodDelete, "/v1/channels/channel-1/members/owner-1", "", authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", rec.Code)
	}
}

func TestOwnerCannotRemoveLastOwner(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "owner"},
			memberRoles:   map[string]string{"channel-1:user-1": "owner"},
			roleCounts:    map[string]int{"channel-1:owner": 1},
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "user-1"},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodDelete, "/v1/channels/channel-1/members/user-1", "", authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
}

func TestCreateInviteReturnsServerErrorWhenRepositoryFails(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{roleByChannel: map[string]string{"channel-1": "owner"}},
		InviteRepo:  stubInviteRepo{createErr: errors.New("create failed")},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPost, "/v1/channels/channel-1/invites", `{}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
}

func TestCreateInviteQueuesPushForTargetDevices(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	pushService := &recordingPushService{}
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "owner"},
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "user-1"},
			},
		},
		InviteRepo: stubInviteRepo{invite: models.Invite{
			ID: "invite-1", ChannelID: "channel-1", CreatedBy: "user-1", MaxUses: 5, ExpiresAt: time.Now().Add(time.Hour),
		}},
		AuditRepo: stubAuditRepo{},
		DeviceRepo: stubDeviceRepo{devices: []models.Device{
			{UserID: "user-2", Platform: "android", PushToken: "push-token-1"},
		}},
		TokenRepo:   stubTokenRepo{},
		PushService: pushService,
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPost, "/v1/channels/channel-1/invites", `{"targetUserId":"user-2","maxUses":5}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", rec.Code)
	}
	if len(pushService.notifications) != 1 {
		t.Fatalf("expected one push notification, got %d", len(pushService.notifications))
	}

	var body struct {
		InviteToken string `json:"inviteToken"`
		PushQueued  bool   `json:"pushQueued"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.InviteToken == "" || !body.PushQueued {
		t.Fatalf("expected invite token and pushQueued=true, got %#v", body)
	}
	if pushService.notifications[0].ChannelName != "Alpha" || pushService.notifications[0].UserID != "user-2" {
		t.Fatalf("unexpected notification payload: %#v", pushService.notifications[0])
	}
}

func TestCreateInviteReturnsServerErrorWhenTargetDevicesFail(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "owner"},
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "user-1"},
			},
		},
		InviteRepo: stubInviteRepo{invite: models.Invite{
			ID: "invite-1", ChannelID: "channel-1", CreatedBy: "user-1", MaxUses: 5, ExpiresAt: time.Now().Add(time.Hour),
		}},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{listErr: errors.New("devices failed")},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPost, "/v1/channels/channel-1/invites", `{"targetUserId":"user-2"}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
}

func TestListInvitesReturnsServerErrorOnRepositoryFailure(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{roleByChannel: map[string]string{"channel-1": "admin"}},
		InviteRepo:  stubInviteRepo{listErr: errors.New("list failed")},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodGet, "/v1/channels/channel-1/invites?limit=10", "", authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
}

func TestRevokeInviteRejectsNonOwnerNonCreator(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "admin"},
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "owner-1"},
			},
		},
		InviteRepo: stubInviteRepo{invite: models.Invite{
			ID: "invite-1", ChannelID: "channel-1", CreatedBy: "user-9", ExpiresAt: time.Now().Add(time.Hour),
		}},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPost, "/v1/channels/channel-1/invites/invite-1/revoke", "", authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", rec.Code)
	}
}

func TestRevokeInviteReturnsServerErrorWhenRevokeFails(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "owner"},
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "user-1"},
			},
		},
		InviteRepo: stubInviteRepo{
			invite:     models.Invite{ID: "invite-1", ChannelID: "channel-1", CreatedBy: "user-1", ExpiresAt: time.Now().Add(time.Hour)},
			revokeErr:  errors.New("revoke failed"),
		},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPost, "/v1/channels/channel-1/invites/invite-1/revoke", "", authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
}

func TestCreateChannelReturnsServerErrorOnRepositoryFailure(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{createErr: errors.New("create failed")},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPost, "/v1/channels", `{"name":"Alpha","type":"private"}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
}

func TestPatchChannelRejectsEmptyChangeSet(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "owner"},
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "user-1"},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPatch, "/v1/channels/channel-1", `{}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
}

func TestPatchChannelReturnsNotFoundWhenChannelMissing(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "owner"},
			getByIDErr:    errors.New("not found"),
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPatch, "/v1/channels/channel-1", `{"name":"Bravo"}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", rec.Code)
	}
}

func TestPatchChannelReturnsServerErrorOnUpdateFailure(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "owner"},
			updateErr:     errors.New("update failed"),
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "user-1"},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPatch, "/v1/channels/channel-1", `{"name":"Bravo"}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
}

func TestListMembersReturnsServerErrorOnRepositoryFailure(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel:  map[string]string{"channel-1": "admin"},
			listMembersErr: errors.New("list failed"),
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodGet, "/v1/channels/channel-1/members", "", authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
}

func TestOwnerRoleUpdateReturnsServerErrorOnTransferFailure(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "owner"},
			transferErr:   errors.New("transfer failed"),
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "user-1"},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPut, "/v1/channels/channel-1/members/user-2", `{"role":"owner"}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
}

func TestRemoveMemberReturnsServerErrorOnDeleteFailure(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{
			roleByChannel: map[string]string{"channel-1": "admin"},
			memberRoles:   map[string]string{"channel-1:user-2": "member"},
			deleteErr:     errors.New("delete failed"),
			channelByID: map[string]models.Channel{
				"channel-1": {ID: "channel-1", Name: "Alpha", Type: "private", OwnerUserID: "owner-1"},
			},
		},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   stubTokenRepo{},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodDelete, "/v1/channels/channel-1/members/user-2", "", authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
}
