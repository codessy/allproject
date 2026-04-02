package push

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"

	"walkietalkie/backend/internal/config"
)

const fcmScope = "https://www.googleapis.com/auth/firebase.messaging"

type FCMService struct {
	projectID  string
	httpClient *http.Client
	tokenURL   string
}

type fcmMessageRequest struct {
	Message fcmMessage `json:"message"`
}

type fcmMessage struct {
	Token        string                 `json:"token"`
	Notification fcmNotification        `json:"notification"`
	Data         map[string]string      `json:"data,omitempty"`
	Android      map[string]interface{} `json:"android,omitempty"`
	APNS         map[string]interface{} `json:"apns,omitempty"`
}

type fcmNotification struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

func NewFCMService(cfg config.Config) (*FCMService, error) {
	if cfg.FCMProjectID == "" {
		return nil, fmt.Errorf("FCM_PROJECT_ID is required for fcm push provider")
	}
	if cfg.FCMCredentials == "" {
		return nil, fmt.Errorf("FCM_CREDENTIALS_JSON is required for fcm push provider")
	}

	creds, err := google.CredentialsFromJSON(
		context.Background(),
		[]byte(cfg.FCMCredentials),
		fcmScope,
	)
	if err != nil {
		return nil, fmt.Errorf("load fcm credentials: %w", err)
	}

	return &FCMService{
		projectID:  cfg.FCMProjectID,
		httpClient: oauthClientWithTimeout(context.Background(), creds),
		tokenURL:   fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", cfg.FCMProjectID),
	}, nil
}

func (s *FCMService) SendInvite(ctx context.Context, notification InviteNotification) error {
	for _, target := range notification.Targets {
		if target.PushToken == "" {
			continue
		}

		payload := fcmMessageRequest{
			Message: fcmMessage{
				Token: target.PushToken,
				Notification: fcmNotification{
					Title: "New channel invite",
					Body:  fmt.Sprintf("You were invited to join %s", notification.ChannelName),
				},
				Data: map[string]string{
					"type":        "channel_invite",
					"channelId":   notification.ChannelID,
					"channelName": notification.ChannelName,
					"inviteToken": notification.InviteToken,
				},
			},
		}

		switch target.Platform {
		case PlatformAndroid:
			payload.Message.Android = map[string]interface{}{
				"priority": "high",
			}
		case PlatformIOS:
			payload.Message.APNS = map[string]interface{}{
				"headers": map[string]string{
					"apns-priority": "10",
				},
				"payload": map[string]interface{}{
					"aps": map[string]interface{}{
						"sound": "default",
					},
				},
			}
		}

		if err := s.sendMessage(ctx, payload); err != nil {
			return err
		}
	}

	return nil
}

func (s *FCMService) sendMessage(ctx context.Context, payload fcmMessageRequest) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal fcm payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.tokenURL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create fcm request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("send fcm request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("fcm send failed with status %d", resp.StatusCode)
	}

	return nil
}

func oauthClientWithTimeout(ctx context.Context, creds *google.Credentials) *http.Client {
	client := oauthHTTPClient(ctx, creds)
	client.Timeout = 10 * time.Second
	return client
}

func oauthHTTPClient(ctx context.Context, creds *google.Credentials) *http.Client {
	return oauth2.NewClient(ctx, creds.TokenSource)
}
