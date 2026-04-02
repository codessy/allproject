package app

import (
	"context"
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"

	"walkietalkie/backend/internal/auth"
	"walkietalkie/backend/internal/channel"
	"walkietalkie/backend/internal/config"
	"walkietalkie/backend/internal/database"
	"walkietalkie/backend/internal/httpapi"
	"walkietalkie/backend/internal/media"
	"walkietalkie/backend/internal/push"
	"walkietalkie/backend/internal/realtime"
	"walkietalkie/backend/internal/repository"
)

type App struct {
	Config         config.Config
	Database       *database.DB
	Redis          *redis.Client
	AuthService    *auth.Service
	ChannelService *channel.Service
	UserRepo       *repository.UserRepository
	ChannelRepo    *repository.ChannelRepository
	InviteRepo     *repository.InviteRepository
	AuditRepo      *repository.AuditRepository
	DeviceRepo     *repository.DeviceRepository
	TokenRepo      *repository.RefreshTokenRepository
	MediaService   *media.LiveKitService
	PushService    push.Service
	RealtimeHub    *realtime.Hub
}

func New(ctx context.Context, cfg config.Config) (*App, error) {
	db, err := database.Connect(ctx, cfg.PostgresDSN)
	if err != nil {
		return nil, err
	}

	if err := database.RunMigrations(ctx, db, "migrations"); err != nil {
		return nil, fmt.Errorf("run migrations: %w", err)
	}

	rdb := redis.NewClient(&redis.Options{
		Addr: cfg.RedisAddr,
	})

	authService := auth.NewService(cfg.JWTIssuer, cfg.JWTSecret)
	userRepo := repository.NewUserRepository(db.Pool)
	channelRepo := repository.NewChannelRepository(db.Pool)
	inviteRepo := repository.NewInviteRepository(db.Pool)
	auditRepo := repository.NewAuditRepository(db.Pool)
	deviceRepo := repository.NewDeviceRepository(db.Pool)
	tokenRepo := repository.NewRefreshTokenRepository(db.Pool)
	mediaService := media.NewLiveKitService(cfg.LiveKitAPIKey, cfg.LiveKitSecret)
	pushService, err := push.NewService(cfg)
	if err != nil {
		return nil, fmt.Errorf("init push service: %w", err)
	}
	pushService = push.NewRedisQueueService(
		ctx,
		pushService,
		rdb,
		push.QueueConfig{
			QueueSize:            cfg.PushQueueSize,
			Workers:              cfg.PushWorkers,
			QueueName:            cfg.PushQueueName,
			MaxAttempts:          cfg.PushMaxAttempts,
			RetryBaseMs:          cfg.PushRetryBaseMs,
			ProcessingTimeoutSec: cfg.PushProcessingTimeoutSec,
			DeadLetterQueueName:  cfg.PushDeadLetterQueueName,
		},
	)
	hub := realtime.NewHub()

	if err := userRepo.SeedDemoUser(ctx); err != nil {
		return nil, fmt.Errorf("seed demo user: %w", err)
	}
	if err := channelRepo.SeedDemoChannel(ctx, "demo@example.com"); err != nil {
		return nil, fmt.Errorf("seed demo channel: %w", err)
	}

	return &App{
		Config:         cfg,
		Database:       db,
		Redis:          rdb,
		AuthService:    authService,
		ChannelService: channel.NewService(rdb),
		UserRepo:       userRepo,
		ChannelRepo:    channelRepo,
		InviteRepo:     inviteRepo,
		AuditRepo:      auditRepo,
		DeviceRepo:     deviceRepo,
		TokenRepo:      tokenRepo,
		MediaService:   mediaService,
		PushService:    pushService,
		RealtimeHub:    hub,
	}, nil
}

func (a *App) Router() *gin.Engine {
	return httpapi.NewRouter(httpapi.RouterDeps{
		Config:         a.Config,
		AuthService:    a.AuthService,
		ChannelService: a.ChannelService,
		Database:       a.Database,
		RedisClient:    a.Redis,
		UserRepo:       a.UserRepo,
		ChannelRepo:    a.ChannelRepo,
		InviteRepo:     a.InviteRepo,
		AuditRepo:      a.AuditRepo,
		DeviceRepo:     a.DeviceRepo,
		TokenRepo:      a.TokenRepo,
		MediaService:   a.MediaService,
		PushService:    a.PushService,
		RealtimeHub:    a.RealtimeHub,
		Upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool { return true },
		},
	})
}
