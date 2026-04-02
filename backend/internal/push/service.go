package push

import (
	"context"
	"fmt"

	"walkietalkie/backend/internal/config"
)

type Platform string

const (
	PlatformAndroid Platform = "android"
	PlatformIOS     Platform = "ios"
)

type DeviceTarget struct {
	UserID    string   `json:"userId"`
	Platform  Platform `json:"platform"`
	PushToken string   `json:"pushToken"`
}

type InviteNotification struct {
	UserID      string         `json:"userId"`
	ChannelID   string         `json:"channelId"`
	ChannelName string         `json:"channelName"`
	InviteToken string         `json:"inviteToken"`
	Targets     []DeviceTarget `json:"targets"`
}

type Service interface {
	SendInvite(context.Context, InviteNotification) error
}

type NoopService struct{}

func NewNoopService() *NoopService {
	return &NoopService{}
}

func (s *NoopService) SendInvite(context.Context, InviteNotification) error {
	return nil
}

func NewService(cfg config.Config) (Service, error) {
	switch cfg.PushProvider {
	case "", "noop":
		return NewNoopService(), nil
	case "fcm":
		return NewFCMService(cfg)
	default:
		return nil, fmt.Errorf("unsupported push provider: %s", cfg.PushProvider)
	}
}
