package httpapi

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	miniredis "github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"

	"walkietalkie/backend/internal/auth"
	"walkietalkie/backend/internal/channel"
	"walkietalkie/backend/internal/config"
	"walkietalkie/backend/internal/push"
	"walkietalkie/backend/internal/realtime"
)

func newWSTestServer(t *testing.T) (*httptest.Server, *auth.Service, func()) {
	t.Helper()
	gin.SetMode(gin.TestMode)

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("start miniredis: %v", err)
	}
	redisClient := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	authService := auth.NewService("walkietalkie", "secret")

	router := NewRouter(RouterDeps{
		Config: config.Config{
			WSConnectRateLimit: 100,
			WSConnectWindowSec: 60,
			WSMessageRateLimit: 100,
			WSMessageWindowSec: 60,
		},
		AuthService:    authService,
		ChannelService: channel.NewService(redisClient),
		Database:       testDatabase{},
		RedisClient:    redisClient,
		UserRepo:       stubUserRepo{},
		ChannelRepo:    stubChannelRepo{},
		InviteRepo:     stubInviteRepo{},
		AuditRepo:      stubAuditRepo{},
		DeviceRepo:     stubDeviceRepo{},
		TokenRepo:      stubTokenRepo{},
		PushService:    push.NewNoopService(),
		RealtimeHub:    realtime.NewHub(),
		Upgrader: websocket.Upgrader{
			CheckOrigin: func(*http.Request) bool { return true },
		},
	})

	server := httptest.NewServer(router)
	cleanup := func() {
		server.Close()
		_ = redisClient.Close()
		mr.Close()
	}
	return server, authService, cleanup
}

func wsConnect(t *testing.T, server *httptest.Server, authService *auth.Service, userID string) *websocket.Conn {
	t.Helper()

	token, err := authService.IssueAccessToken(userID, userID+"@example.com")
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}

	wsURL, err := url.Parse(server.URL)
	if err != nil {
		t.Fatalf("parse server url: %v", err)
	}
	wsURL.Scheme = "ws"
	wsURL.Path = "/v1/ws"

	headers := http.Header{}
	headers.Set("Authorization", "Bearer "+token)
	conn, _, err := websocket.DefaultDialer.Dial(wsURL.String(), headers)
	if err != nil {
		t.Fatalf("dial websocket: %v", err)
	}
	t.Cleanup(func() {
		_ = conn.Close()
	})
	return conn
}

func readWSMessage(t *testing.T, conn *websocket.Conn) map[string]any {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	var msg map[string]any
	if err := conn.ReadJSON(&msg); err != nil {
		t.Fatalf("read websocket message: %v", err)
	}
	return msg
}

func readWSMessageOfType(t *testing.T, conn *websocket.Conn, expectedType string) map[string]any {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for {
		msg := readWSMessage(t, conn)
		if msg["type"] == expectedType {
			return msg
		}
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for websocket message type %q", expectedType)
		}
	}
}

func writeWSMessage(t *testing.T, conn *websocket.Conn, msg map[string]any) {
	t.Helper()
	_ = conn.SetWriteDeadline(time.Now().Add(2 * time.Second))
	if err := conn.WriteJSON(msg); err != nil {
		t.Fatalf("write websocket message: %v", err)
	}
}

func TestWebSocketSubscribeAndPresencePing(t *testing.T) {
	server, authService, cleanup := newWSTestServer(t)
	defer cleanup()

	conn := wsConnect(t, server, authService, "user-1")
	writeWSMessage(t, conn, map[string]any{
		"type":      "channel.subscribe",
		"channelId": "alpha",
	})

	state := readWSMessage(t, conn)
	if state["type"] != "channel.state" || state["channelId"] != "alpha" || state["userId"] != "" {
		t.Fatalf("unexpected channel state message: %#v", state)
	}

	writeWSMessage(t, conn, map[string]any{"type": "presence.ping"})
	pong := readWSMessage(t, conn)
	if pong["type"] != "presence.pong" {
		t.Fatalf("unexpected presence response: %#v", pong)
	}
}

func TestWebSocketSpeakerRequestDeniedWhenBusy(t *testing.T) {
	server, authService, cleanup := newWSTestServer(t)
	defer cleanup()

	conn1 := wsConnect(t, server, authService, "user-1")
	conn2 := wsConnect(t, server, authService, "user-2")

	writeWSMessage(t, conn1, map[string]any{"type": "channel.subscribe", "channelId": "alpha"})
	_ = readWSMessage(t, conn1)
	writeWSMessage(t, conn2, map[string]any{"type": "channel.subscribe", "channelId": "alpha"})
	_ = readWSMessage(t, conn2)

	writeWSMessage(t, conn1, map[string]any{"type": "speaker.request", "channelId": "alpha"})
	granted := readWSMessageOfType(t, conn1, "speaker.granted")
	if granted["type"] != "speaker.granted" || granted["userId"] != "user-1" {
		t.Fatalf("unexpected granted message: %#v", granted)
	}

	changed1 := readWSMessageOfType(t, conn1, "speaker.changed")
	if changed1["type"] != "speaker.changed" || changed1["userId"] != "user-1" {
		t.Fatalf("unexpected changed message for first client: %#v", changed1)
	}

	changed2 := readWSMessageOfType(t, conn2, "speaker.changed")
	if changed2["type"] != "speaker.changed" || changed2["userId"] != "user-1" {
		t.Fatalf("unexpected changed message for second client: %#v", changed2)
	}

	writeWSMessage(t, conn2, map[string]any{"type": "speaker.request", "channelId": "alpha"})
	denied := readWSMessage(t, conn2)
	if denied["type"] != "speaker.denied" || denied["owner"] != "user-1" {
		t.Fatalf("unexpected denied message: %#v", denied)
	}
}

func TestWebSocketSpeakerReleaseBroadcastsEmptySpeaker(t *testing.T) {
	server, authService, cleanup := newWSTestServer(t)
	defer cleanup()

	conn1 := wsConnect(t, server, authService, "user-1")
	conn2 := wsConnect(t, server, authService, "user-2")

	writeWSMessage(t, conn1, map[string]any{"type": "channel.subscribe", "channelId": "alpha"})
	_ = readWSMessage(t, conn1)
	writeWSMessage(t, conn2, map[string]any{"type": "channel.subscribe", "channelId": "alpha"})
	_ = readWSMessage(t, conn2)

	writeWSMessage(t, conn1, map[string]any{"type": "speaker.request", "channelId": "alpha"})
	_ = readWSMessageOfType(t, conn1, "speaker.granted")
	_ = readWSMessageOfType(t, conn1, "speaker.changed")
	_ = readWSMessageOfType(t, conn2, "speaker.changed")

	writeWSMessage(t, conn1, map[string]any{"type": "speaker.release", "channelId": "alpha"})

	released1 := readWSMessageOfType(t, conn1, "speaker.changed")
	released2 := readWSMessageOfType(t, conn2, "speaker.changed")
	if released1["type"] != "speaker.changed" || released1["userId"] != "" {
		t.Fatalf("unexpected release message for first client: %#v", released1)
	}
	if released2["type"] != "speaker.changed" || released2["userId"] != "" {
		t.Fatalf("unexpected release message for second client: %#v", released2)
	}
}

func TestWebSocketRejectsInvalidMessage(t *testing.T) {
	server, authService, cleanup := newWSTestServer(t)
	defer cleanup()

	conn := wsConnect(t, server, authService, "user-1")
	writeWSMessage(t, conn, map[string]any{"type": "speaker.request"})

	msg := readWSMessage(t, conn)
	if msg["type"] != "error" || msg["error"] != "invalid websocket message" {
		t.Fatalf("unexpected invalid-message response: %#v", msg)
	}
}

func TestWebSocketDefaultsToDemoUserWithoutAuthHeader(t *testing.T) {
	server, authService, cleanup := newWSTestServer(t)
	_ = authService
	defer cleanup()

	wsURL, err := url.Parse(server.URL)
	if err != nil {
		t.Fatalf("parse server url: %v", err)
	}
	wsURL.Scheme = "ws"
	wsURL.Path = "/v1/ws"

	conn, _, err := websocket.DefaultDialer.Dial(wsURL.String(), http.Header{})
	if err != nil {
		t.Fatalf("dial websocket without auth: %v", err)
	}
	defer conn.Close()

	writeWSMessage(t, conn, map[string]any{"type": "channel.subscribe", "channelId": "alpha"})
	_ = readWSMessage(t, conn)

	writeWSMessage(t, conn, map[string]any{"type": "speaker.request", "channelId": "alpha"})
	granted := readWSMessage(t, conn)
	if granted["type"] != "speaker.granted" || granted["userId"] != "demo-user" {
		t.Fatalf("unexpected demo-user grant: %#v", granted)
	}
}

func TestWebSocketConnectionClosesOnContextFreeReadPath(t *testing.T) {
	server, authService, cleanup := newWSTestServer(t)
	defer cleanup()

	conn := wsConnect(t, server, authService, "user-1")
	writeWSMessage(t, conn, map[string]any{"type": "presence.ping"})
	_ = readWSMessage(t, conn)

	// Verify connection remains usable after one valid round-trip.
	writeWSMessage(t, conn, map[string]any{"type": "presence.ping"})
	msg := readWSMessage(t, conn)
	if msg["type"] != "presence.pong" {
		t.Fatalf("unexpected second pong: %#v", msg)
	}
}

