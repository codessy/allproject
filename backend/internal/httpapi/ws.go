package httpapi

import (
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"

	"walkietalkie/backend/internal/channel"
	"walkietalkie/backend/internal/realtime"
)

func handleWS(
	c *gin.Context,
	upgrader websocket.Upgrader,
	channelService *channel.Service,
	hub *realtime.Hub,
	messageRateLimit int,
	messageWindow time.Duration,
) {
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}
	defer func() {
		hub.Unsubscribe(conn)
		conn.Close()
	}()

	userID := c.GetString("userID")
	if userID == "" {
		userID = "demo-user"
	}

	limiter := newWSMessageLimiter(messageRateLimit, messageWindow)
	conn.SetReadLimit(16 * 1024)
	_ = conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	})

	for {
		var msg map[string]any
		if err := conn.ReadJSON(&msg); err != nil {
			return
		}
		if !limiter.Allow(time.Now()) {
			_ = conn.WriteJSON(gin.H{
				"type":  "error",
				"error": "rate limit exceeded",
			})
			_ = conn.WriteControl(
				websocket.CloseMessage,
				websocket.FormatCloseMessage(websocket.ClosePolicyViolation, "message rate limit exceeded"),
				time.Now().Add(time.Second),
			)
			return
		}
		_ = conn.SetReadDeadline(time.Now().Add(60 * time.Second))

		msgType, _ := msg["type"].(string)
		channelID, _ := msg["channelId"].(string)

		if msgType == "" || (msgType != "presence.ping" && channelID == "") {
			_ = conn.WriteJSON(gin.H{
				"type":  "error",
				"error": "invalid websocket message",
			})
			continue
		}

		switch msgType {
		case "channel.subscribe":
			hub.Subscribe(channelID, userID, conn)
			_ = conn.WriteJSON(gin.H{
				"type":      "channel.state",
				"channelId": channelID,
				"userId":    channelService.ActiveSpeaker(c.Request.Context(), channelID),
			})
		case "speaker.request":
			ok := channelService.TryAcquireSpeaker(c.Request.Context(), channelID, userID)
			if ok {
				hub.Broadcast(channelID, gin.H{
					"type":      "speaker.granted",
					"channelId": channelID,
					"userId":    userID,
					"leaseMs":   3000,
				})
				hub.Broadcast(channelID, gin.H{
					"type":      "speaker.changed",
					"channelId": channelID,
					"userId":    userID,
				})
			} else {
				owner := channelService.ActiveSpeaker(c.Request.Context(), channelID)
				_ = conn.WriteJSON(gin.H{
					"type":      "speaker.denied",
					"channelId": channelID,
					"reason":    "busy",
					"owner":     owner,
				})
			}
		case "speaker.renew":
			renewed := channelService.RenewSpeaker(c.Request.Context(), channelID, userID)
			_ = conn.WriteJSON(gin.H{
				"type":      "speaker.renewed",
				"channelId": channelID,
				"ok":        renewed,
				"leaseMs":   3000,
			})
		case "speaker.release":
			channelService.ReleaseSpeaker(c.Request.Context(), channelID, userID)
			hub.Broadcast(channelID, gin.H{
				"type":      "speaker.changed",
				"channelId": channelID,
				"userId":    "",
			})
		case "presence.ping":
			_ = conn.WriteJSON(gin.H{"type": "presence.pong"})
		default:
			_ = conn.WriteJSON(gin.H{
				"type":  "error",
				"error": "unsupported message type",
			})
		}
	}
}
