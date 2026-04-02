package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"

	"walkietalkie/backend/internal/auth"
	"walkietalkie/backend/internal/config"
	"walkietalkie/backend/internal/push"
)

type testDatabase struct {
	err error
}

func (d testDatabase) Ping(context.Context) error {
	return d.err
}

type testRedisClient struct {
	err error
}

func (r testRedisClient) Ping(ctx context.Context) *redis.StatusCmd {
	cmd := redis.NewStatusCmd(ctx)
	if r.err != nil {
		cmd.SetErr(r.err)
	} else {
		cmd.SetVal("PONG")
	}
	return cmd
}

func (r testRedisClient) Incr(ctx context.Context, key string) *redis.IntCmd {
	cmd := redis.NewIntCmd(ctx)
	if r.err != nil {
		cmd.SetErr(r.err)
	} else {
		cmd.SetVal(1)
	}
	return cmd
}

func (r testRedisClient) Expire(ctx context.Context, key string, expiration time.Duration) *redis.BoolCmd {
	cmd := redis.NewBoolCmd(ctx)
	if r.err != nil {
		cmd.SetErr(r.err)
	} else {
		cmd.SetVal(true)
	}
	return cmd
}

func (r testRedisClient) TTL(ctx context.Context, key string) *redis.DurationCmd {
	cmd := redis.NewDurationCmd(ctx, time.Minute)
	if r.err != nil {
		cmd.SetErr(r.err)
	} else {
		cmd.SetVal(time.Minute)
	}
	return cmd
}

type testPushService struct {
	stats push.QueueStats
}

func (s testPushService) SendInvite(context.Context, push.InviteNotification) error {
	return nil
}

func (s testPushService) Stats(context.Context) push.QueueStats {
	return s.stats
}

func TestDiagnosticsHealthEndpointReturnsDependencyStates(t *testing.T) {
	gin.SetMode(gin.TestMode)

	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: auth.NewService("walkietalkie", "secret"),
		Database:    testDatabase{},
		RedisClient: testRedisClient{},
		PushService: testPushService{stats: push.QueueStats{PendingDepth: 2, QueueName: "push:invite:pending"}},
		Upgrader:    websocket.Upgrader{},
	})

	req := httptest.NewRequest(http.MethodGet, "/healthz/diagnostics", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}

	if body["status"] != "ok" {
		t.Fatalf("expected ok status, got %v", body["status"])
	}

	dependencies := body["dependencies"].(map[string]any)
	if dependencies["database"] != "ok" || dependencies["redis"] != "ok" {
		t.Fatalf("unexpected dependency states: %#v", dependencies)
	}

	if body["pushObserved"] != true {
		t.Fatalf("expected pushObserved true, got %v", body["pushObserved"])
	}
}

func TestDiagnosticsHealthEndpointReturnsDegradedOnFailures(t *testing.T) {
	gin.SetMode(gin.TestMode)

	router := NewRouter(RouterDeps{
		Config:      config.Config{},
		AuthService: auth.NewService("walkietalkie", "secret"),
		Database:    testDatabase{err: errors.New("db down")},
		RedisClient: testRedisClient{err: errors.New("redis down")},
		PushService: push.NewNoopService(),
		Upgrader:    websocket.Upgrader{},
	})

	req := httptest.NewRequest(http.MethodGet, "/healthz/diagnostics", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d", rec.Code)
	}

	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}

	if body["status"] != "degraded" {
		t.Fatalf("expected degraded status, got %v", body["status"])
	}

	if body["pushObserved"] != false {
		t.Fatalf("expected pushObserved false, got %v", body["pushObserved"])
	}
}
