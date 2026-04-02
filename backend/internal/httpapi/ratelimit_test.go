package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	miniredis "github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

func TestRateLimitMiddlewareBlocksAfterLimit(t *testing.T) {
	gin.SetMode(gin.TestMode)

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("start miniredis: %v", err)
	}
	defer mr.Close()

	client := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer client.Close()

	router := gin.New()
	router.POST(
		"/login",
		RateLimitMiddleware(client, "auth_login_test", 2, time.Minute, EmailOrIPKey),
		func(c *gin.Context) {
			c.Status(http.StatusOK)
		},
	)

	body := `{"email":"demo@example.com","password":"password"}`
	for i := 0; i < 2; i++ {
		req := httptest.NewRequest(http.MethodPost, "/login", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 before limit, got %d", rec.Code)
		}
	}

	req := httptest.NewRequest(http.MethodPost, "/login", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429 after limit, got %d", rec.Code)
	}
}

func TestUserOrIPKeyPrefersUserID(t *testing.T) {
	gin.SetMode(gin.TestMode)

	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Set("userID", "user-123")

	if got := UserOrIPKey(ctx); got != "user-123" {
		t.Fatalf("expected user-123, got %s", got)
	}
}

func TestWebsocketConnectRateLimitBlocksAfterLimit(t *testing.T) {
	gin.SetMode(gin.TestMode)

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("start miniredis: %v", err)
	}
	defer mr.Close()

	client := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer client.Close()

	router := gin.New()
	router.GET(
		"/ws",
		RateLimitMiddleware(client, "ws_connect_test", 1, time.Minute, UserOrIPKey),
		func(c *gin.Context) {
			c.Status(http.StatusSwitchingProtocols)
		},
	)

	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusSwitchingProtocols {
		t.Fatalf("expected first websocket request to pass, got %d", rec.Code)
	}

	req2 := httptest.NewRequest(http.MethodGet, "/ws", nil)
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusTooManyRequests {
		t.Fatalf("expected second websocket request to be limited, got %d", rec2.Code)
	}
}
