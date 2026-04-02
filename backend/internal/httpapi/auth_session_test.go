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

type sessionUserRepo struct {
	userByID      map[string]models.User
	userByEmail   map[string]models.User
	createdUser   models.User
	createErr     error
	createdEmail  string
	createdName   string
	createdHash   string
	getByEmailErr error
}

func (s *sessionUserRepo) Create(_ context.Context, email, displayName, passwordHash string) (models.User, error) {
	if s.createErr != nil {
		return models.User{}, s.createErr
	}
	s.createdEmail = email
	s.createdName = displayName
	s.createdHash = passwordHash
	if s.createdUser.ID != "" {
		return s.createdUser, nil
	}
	return models.User{
		ID:          "created-user",
		Email:       email,
		DisplayName: displayName,
	}, nil
}

func (s *sessionUserRepo) GetByEmail(_ context.Context, email string) (models.User, error) {
	if s.getByEmailErr != nil {
		return models.User{}, s.getByEmailErr
	}
	user, ok := s.userByEmail[email]
	if !ok {
		return models.User{}, errors.New("user not found")
	}
	return user, nil
}

func (s *sessionUserRepo) GetByID(_ context.Context, userID string) (models.User, error) {
	user, ok := s.userByID[userID]
	if !ok {
		return models.User{}, errors.New("user not found")
	}
	return user, nil
}

type sessionTokenRepo struct {
	record          repository.RefreshTokenRecord
	getByHashErr    error
	createErr       error
	deleteByHashErr error
	deleteByUserErr error
	createdUserID   string
	createdHash     string
	createdExpiry   time.Time
	deletedHash     string
	deletedByUserID string
}

func (s *sessionTokenRepo) GetByHash(context.Context, string) (repository.RefreshTokenRecord, error) {
	if s.getByHashErr != nil {
		return repository.RefreshTokenRecord{}, s.getByHashErr
	}
	return s.record, nil
}

func (s *sessionTokenRepo) Create(_ context.Context, userID, tokenHash string, expiresAt time.Time) error {
	if s.createErr != nil {
		return s.createErr
	}
	s.createdUserID = userID
	s.createdHash = tokenHash
	s.createdExpiry = expiresAt
	return nil
}

func (s *sessionTokenRepo) DeleteByHash(_ context.Context, tokenHash string) error {
	if s.deleteByHashErr != nil {
		return s.deleteByHashErr
	}
	s.deletedHash = tokenHash
	return nil
}

func (s *sessionTokenRepo) DeleteByUserID(_ context.Context, userID string) error {
	if s.deleteByUserErr != nil {
		return s.deleteByUserErr
	}
	s.deletedByUserID = userID
	return nil
}

func TestRefreshRotatesStoredToken(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	refreshRaw, refreshHash, refreshExpiry, err := authService.NewRefreshToken()
	if err != nil {
		t.Fatalf("new refresh token: %v", err)
	}

	tokenRepo := &sessionTokenRepo{
		record: repository.RefreshTokenRecord{
			UserID:    "user-1",
			TokenHash: refreshHash,
			ExpiresAt: refreshExpiry,
		},
	}

	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo: &sessionUserRepo{userByID: map[string]models.User{
			"user-1": {ID: "user-1", Email: "demo@example.com", DisplayName: "Demo"},
		}},
		ChannelRepo: stubChannelRepo{},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   tokenRepo,
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := httptest.NewRequest(http.MethodPost, "/v1/auth/refresh", strings.NewReader(`{"refreshToken":"`+refreshRaw+`"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if tokenRepo.deletedHash != refreshHash {
		t.Fatalf("expected old token hash to be deleted, got %q", tokenRepo.deletedHash)
	}
	if tokenRepo.createdUserID != "user-1" {
		t.Fatalf("expected rotated token to be stored for user-1, got %q", tokenRepo.createdUserID)
	}
	if tokenRepo.createdHash == "" || tokenRepo.createdHash == refreshHash {
		t.Fatalf("expected rotated refresh hash, got %q", tokenRepo.createdHash)
	}
	if !tokenRepo.createdExpiry.After(time.Now()) {
		t.Fatalf("expected future refresh expiry, got %v", tokenRepo.createdExpiry)
	}

	var body struct {
		User         models.User `json:"user"`
		AccessToken  string      `json:"accessToken"`
		RefreshToken string      `json:"refreshToken"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.User.ID != "user-1" || body.AccessToken == "" {
		t.Fatalf("unexpected refresh response: %#v", body)
	}
	if body.RefreshToken == "" || body.RefreshToken == refreshRaw {
		t.Fatalf("expected rotated refresh token in response, got %q", body.RefreshToken)
	}
}

func TestLogoutRevokesCurrentRefreshToken(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	tokenRepo := &sessionTokenRepo{}
	refreshToken := "refresh-token-value"

	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   tokenRepo,
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPost, "/v1/auth/logout", `{"refreshToken":"`+refreshToken+`"}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	expectedHash := authService.HashOpaqueToken(refreshToken)
	if tokenRepo.deletedHash != expectedHash {
		t.Fatalf("expected deleted hash %q, got %q", expectedHash, tokenRepo.deletedHash)
	}
	if tokenRepo.deletedByUserID != "" {
		t.Fatalf("did not expect all-device revoke, got %q", tokenRepo.deletedByUserID)
	}
}

func TestLogoutAllDevicesRevokesUserSessions(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	tokenRepo := &sessionTokenRepo{}

	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   tokenRepo,
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPost, "/v1/auth/logout", `{"allDevices":true}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if tokenRepo.deletedByUserID != "user-1" {
		t.Fatalf("expected all-device revoke for user-1, got %q", tokenRepo.deletedByUserID)
	}
	if tokenRepo.deletedHash != "" {
		t.Fatalf("did not expect single-token revoke, got %q", tokenRepo.deletedHash)
	}
}

func TestRefreshRejectsExpiredToken(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	tokenRepo := &sessionTokenRepo{
		record: repository.RefreshTokenRecord{
			UserID:    "user-1",
			TokenHash: "expired-hash",
			ExpiresAt: time.Now().Add(-time.Minute),
		},
	}

	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    &sessionUserRepo{userByID: map[string]models.User{"user-1": {ID: "user-1", Email: "demo@example.com"}}},
		ChannelRepo: stubChannelRepo{},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   tokenRepo,
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := httptest.NewRequest(http.MethodPost, "/v1/auth/refresh", strings.NewReader(`{"refreshToken":"expired-token"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
	if tokenRepo.deletedHash != "" || tokenRepo.createdHash != "" {
		t.Fatalf("expected no token mutation for expired refresh token")
	}
}

func TestRefreshRejectsUnknownUser(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	tokenRepo := &sessionTokenRepo{
		record: repository.RefreshTokenRecord{
			UserID:    "missing-user",
			TokenHash: "refresh-hash",
			ExpiresAt: time.Now().Add(time.Hour),
		},
	}

	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    &sessionUserRepo{userByID: map[string]models.User{}},
		ChannelRepo: stubChannelRepo{},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   tokenRepo,
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := httptest.NewRequest(http.MethodPost, "/v1/auth/refresh", strings.NewReader(`{"refreshToken":"valid-but-orphaned"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
	if tokenRepo.deletedHash != "" || tokenRepo.createdHash != "" {
		t.Fatalf("expected no token rotation when user lookup fails")
	}
}

func TestRefreshFailsWhenOldTokenRevokeFails(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	refreshRaw, refreshHash, refreshExpiry, err := authService.NewRefreshToken()
	if err != nil {
		t.Fatalf("new refresh token: %v", err)
	}
	tokenRepo := &sessionTokenRepo{
		record: repository.RefreshTokenRecord{
			UserID:    "user-1",
			TokenHash: refreshHash,
			ExpiresAt: refreshExpiry,
		},
		deleteByHashErr: errors.New("delete failed"),
	}

	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    &sessionUserRepo{userByID: map[string]models.User{"user-1": {ID: "user-1", Email: "demo@example.com"}}},
		ChannelRepo: stubChannelRepo{},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   tokenRepo,
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := httptest.NewRequest(http.MethodPost, "/v1/auth/refresh", strings.NewReader(`{"refreshToken":"`+refreshRaw+`"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
	if tokenRepo.createdHash != "" {
		t.Fatalf("did not expect rotated token persistence after revoke failure")
	}
}

func TestLogoutRejectsMalformedRequest(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	tokenRepo := &sessionTokenRepo{}

	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   tokenRepo,
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPost, "/v1/auth/logout", `{`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	if tokenRepo.deletedHash != "" || tokenRepo.deletedByUserID != "" {
		t.Fatalf("expected no token revocation on malformed logout request")
	}
}

func TestLogoutReturnsServerErrorWhenAllDeviceRevokeFails(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	tokenRepo := &sessionTokenRepo{deleteByUserErr: errors.New("delete by user failed")}

	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    stubUserRepo{},
		ChannelRepo: stubChannelRepo{},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   tokenRepo,
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := newAuthorizedRequest(t, http.MethodPost, "/v1/auth/logout", `{"allDevices":true}`, authService)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
	if tokenRepo.deletedByUserID != "" {
		t.Fatalf("expected failed all-device revoke to avoid recording success")
	}
}

func TestRegisterReturnsTokensAndHashedPassword(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	userRepo := &sessionUserRepo{
		createdUser: models.User{
			ID:          "user-42",
			Email:       "new@example.com",
			DisplayName: "New User",
		},
	}
	tokenRepo := &sessionTokenRepo{}

	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    userRepo,
		ChannelRepo: stubChannelRepo{},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   tokenRepo,
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := httptest.NewRequest(http.MethodPost, "/v1/auth/register", strings.NewReader(`{"email":"new@example.com","displayName":"New User","password":"password123"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", rec.Code)
	}
	if userRepo.createdEmail != "new@example.com" || userRepo.createdName != "New User" {
		t.Fatalf("unexpected create input: email=%q name=%q", userRepo.createdEmail, userRepo.createdName)
	}
	if userRepo.createdHash == "" || userRepo.createdHash == "password123" {
		t.Fatalf("expected hashed password to be persisted, got %q", userRepo.createdHash)
	}
	if !authService.VerifyPassword("password123", userRepo.createdHash) {
		t.Fatalf("expected stored password hash to verify")
	}
	if tokenRepo.createdUserID != "user-42" || tokenRepo.createdHash == "" {
		t.Fatalf("expected refresh token persistence for created user, got %#v", tokenRepo)
	}

	var body struct {
		User         models.User `json:"user"`
		AccessToken  string      `json:"accessToken"`
		RefreshToken string      `json:"refreshToken"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.User.ID != "user-42" || body.AccessToken == "" || body.RefreshToken == "" {
		t.Fatalf("unexpected register response: %#v", body)
	}
}

func TestRegisterReturnsConflictWhenUserCreationFails(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	userRepo := &sessionUserRepo{createErr: errors.New("duplicate user")}
	tokenRepo := &sessionTokenRepo{}

	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    userRepo,
		ChannelRepo: stubChannelRepo{},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   tokenRepo,
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := httptest.NewRequest(http.MethodPost, "/v1/auth/register", strings.NewReader(`{"email":"new@example.com","displayName":"New User","password":"password123"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}
	if tokenRepo.createdHash != "" {
		t.Fatalf("did not expect refresh token persistence on register conflict")
	}
}

func TestLoginReturnsTokensForValidCredentials(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	passwordHash, err := authService.HashPassword("password123")
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}
	userRepo := &sessionUserRepo{
		userByEmail: map[string]models.User{
			"demo@example.com": {
				ID:           "user-1",
				Email:        "demo@example.com",
				DisplayName:  "Demo",
				PasswordHash: passwordHash,
			},
		},
	}
	tokenRepo := &sessionTokenRepo{}

	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    userRepo,
		ChannelRepo: stubChannelRepo{},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   tokenRepo,
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(`{"email":"demo@example.com","password":"password123"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if tokenRepo.createdUserID != "user-1" || tokenRepo.createdHash == "" {
		t.Fatalf("expected refresh token persistence on login, got %#v", tokenRepo)
	}

	var body struct {
		User         models.User `json:"user"`
		AccessToken  string      `json:"accessToken"`
		RefreshToken string      `json:"refreshToken"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.User.ID != "user-1" || body.AccessToken == "" || body.RefreshToken == "" {
		t.Fatalf("unexpected login response: %#v", body)
	}
}

func TestLoginRejectsInvalidCredentials(t *testing.T) {
	gin.SetMode(gin.TestMode)

	authService := auth.NewService("walkietalkie", "secret")
	passwordHash, err := authService.HashPassword("correct-password")
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}
	userRepo := &sessionUserRepo{
		userByEmail: map[string]models.User{
			"demo@example.com": {
				ID:           "user-1",
				Email:        "demo@example.com",
				PasswordHash: passwordHash,
			},
		},
	}
	tokenRepo := &sessionTokenRepo{}

	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: authService,
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		UserRepo:    userRepo,
		ChannelRepo: stubChannelRepo{},
		InviteRepo:  stubInviteRepo{},
		AuditRepo:   stubAuditRepo{},
		DeviceRepo:  stubDeviceRepo{},
		TokenRepo:   tokenRepo,
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(`{"email":"demo@example.com","password":"wrong-password"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
	if tokenRepo.createdHash != "" {
		t.Fatalf("did not expect refresh token persistence on invalid login")
	}
}
