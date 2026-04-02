package realtime

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func newHubTestPair(t *testing.T) (*websocket.Conn, *websocket.Conn, func()) {
	t.Helper()

	upgrader := websocket.Upgrader{
		CheckOrigin: func(*http.Request) bool { return true },
	}
	serverConnCh := make(chan *websocket.Conn, 1)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			t.Errorf("upgrade websocket: %v", err)
			return
		}
		serverConnCh <- conn
	}))

	wsURL, err := url.Parse(server.URL)
	if err != nil {
		server.Close()
		t.Fatalf("parse server url: %v", err)
	}
	wsURL.Scheme = "ws"

	clientConn, _, err := websocket.DefaultDialer.Dial(wsURL.String(), nil)
	if err != nil {
		server.Close()
		t.Fatalf("dial websocket: %v", err)
	}

	var serverConn *websocket.Conn
	select {
	case serverConn = <-serverConnCh:
	case <-time.After(2 * time.Second):
		clientConn.Close()
		server.Close()
		t.Fatal("timed out waiting for server websocket connection")
	}

	cleanup := func() {
		_ = clientConn.Close()
		_ = serverConn.Close()
		server.Close()
	}
	return serverConn, clientConn, cleanup
}

func readHubMessage(t *testing.T, conn *websocket.Conn) map[string]any {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	var msg map[string]any
	if err := conn.ReadJSON(&msg); err != nil {
		t.Fatalf("read websocket message: %v", err)
	}
	return msg
}

func TestHubSubscribeStoresConnectionPerChannel(t *testing.T) {
	hub := NewHub()
	serverConn, _, cleanup := newHubTestPair(t)
	defer cleanup()

	hub.Subscribe("alpha", "user-1", serverConn)

	hub.mu.RLock()
	defer hub.mu.RUnlock()

	channelSubs, ok := hub.subscribers["alpha"]
	if !ok {
		t.Fatal("expected alpha channel subscribers to exist")
	}
	if got := channelSubs[serverConn]; got != "user-1" {
		t.Fatalf("expected stored user id user-1, got %q", got)
	}
}

func TestHubUnsubscribeRemovesConnectionAndEmptyChannel(t *testing.T) {
	hub := NewHub()
	serverConn, _, cleanup := newHubTestPair(t)
	defer cleanup()

	hub.Subscribe("alpha", "user-1", serverConn)
	hub.Unsubscribe(serverConn)

	hub.mu.RLock()
	defer hub.mu.RUnlock()
	if _, ok := hub.subscribers["alpha"]; ok {
		t.Fatal("expected alpha channel to be removed after unsubscribe")
	}
}

func TestHubUnsubscribeRemovesConnectionAcrossChannels(t *testing.T) {
	hub := NewHub()
	serverConn, _, cleanup := newHubTestPair(t)
	defer cleanup()

	hub.Subscribe("alpha", "user-1", serverConn)
	hub.Subscribe("bravo", "user-1", serverConn)
	hub.Unsubscribe(serverConn)

	hub.mu.RLock()
	defer hub.mu.RUnlock()
	if len(hub.subscribers) != 0 {
		t.Fatalf("expected all channel subscriptions removed, got %#v", hub.subscribers)
	}
}

func TestHubBroadcastSendsPayloadToAllSubscribersInChannel(t *testing.T) {
	hub := NewHub()
	serverConn1, clientConn1, cleanup1 := newHubTestPair(t)
	defer cleanup1()
	serverConn2, clientConn2, cleanup2 := newHubTestPair(t)
	defer cleanup2()

	hub.Subscribe("alpha", "user-1", serverConn1)
	hub.Subscribe("alpha", "user-2", serverConn2)

	payload := map[string]any{
		"type":      "speaker.changed",
		"channelId": "alpha",
		"userId":    "user-1",
	}
	hub.Broadcast("alpha", payload)

	msg1 := readHubMessage(t, clientConn1)
	msg2 := readHubMessage(t, clientConn2)
	if msg1["type"] != "speaker.changed" || msg1["channelId"] != "alpha" || msg1["userId"] != "user-1" {
		t.Fatalf("unexpected payload for first subscriber: %#v", msg1)
	}
	if msg2["type"] != "speaker.changed" || msg2["channelId"] != "alpha" || msg2["userId"] != "user-1" {
		t.Fatalf("unexpected payload for second subscriber: %#v", msg2)
	}
}

func TestHubBroadcastDoesNotSendToOtherChannels(t *testing.T) {
	hub := NewHub()
	serverConn1, clientConn1, cleanup1 := newHubTestPair(t)
	defer cleanup1()
	serverConn2, clientConn2, cleanup2 := newHubTestPair(t)
	defer cleanup2()

	hub.Subscribe("alpha", "user-1", serverConn1)
	hub.Subscribe("bravo", "user-2", serverConn2)

	hub.Broadcast("alpha", map[string]any{
		"type":      "speaker.changed",
		"channelId": "alpha",
		"userId":    "user-1",
	})

	msg := readHubMessage(t, clientConn1)
	if msg["channelId"] != "alpha" {
		t.Fatalf("unexpected alpha payload: %#v", msg)
	}

	_ = clientConn2.SetReadDeadline(time.Now().Add(200 * time.Millisecond))
	var ignored map[string]any
	if err := clientConn2.ReadJSON(&ignored); err == nil {
		t.Fatalf("expected no payload for non-subscriber channel, got %#v", ignored)
	}
}
