package realtime

import (
	"sync"

	"github.com/gorilla/websocket"
)

type Hub struct {
	mu          sync.RWMutex
	subscribers map[string]map[*websocket.Conn]string
}

func NewHub() *Hub {
	return &Hub{
		subscribers: make(map[string]map[*websocket.Conn]string),
	}
}

func (h *Hub) Subscribe(channelID, userID string, conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if _, ok := h.subscribers[channelID]; !ok {
		h.subscribers[channelID] = make(map[*websocket.Conn]string)
	}
	h.subscribers[channelID][conn] = userID
}

func (h *Hub) Unsubscribe(conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()

	for channelID, conns := range h.subscribers {
		if _, ok := conns[conn]; ok {
			delete(conns, conn)
			if len(conns) == 0 {
				delete(h.subscribers, channelID)
			}
		}
	}
}

func (h *Hub) Broadcast(channelID string, payload map[string]any) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	for conn := range h.subscribers[channelID] {
		_ = conn.WriteJSON(payload)
	}
}
