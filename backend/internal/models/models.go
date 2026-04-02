package models

import (
	"encoding/json"
	"time"
)

type User struct {
	ID           string    `json:"id"`
	Email        string    `json:"email"`
	DisplayName  string    `json:"displayName"`
	PasswordHash string    `json:"-"`
	CreatedAt    time.Time `json:"createdAt"`
}

type Channel struct {
	ID                  string    `json:"id"`
	Name                string    `json:"name"`
	Type                string    `json:"type"`
	OwnerUserID         string    `json:"ownerUserId"`
	Role                string    `json:"role,omitempty"`
	ActiveSpeakerUserID string    `json:"activeSpeakerUserId,omitempty"`
	CreatedAt           time.Time `json:"createdAt"`
}

type ChannelMembership struct {
	ChannelID string    `json:"channelId"`
	UserID    string    `json:"userId"`
	Role      string    `json:"role"`
	JoinedAt  time.Time `json:"joinedAt"`
}

type Invite struct {
	ID        string     `json:"id"`
	ChannelID string     `json:"channelId"`
	TokenHash string     `json:"-"`
	CreatedBy string     `json:"createdBy"`
	ExpiresAt time.Time  `json:"expiresAt"`
	MaxUses   int        `json:"maxUses"`
	UsedCount int        `json:"usedCount"`
	CreatedAt time.Time  `json:"createdAt"`
	RevokedAt *time.Time `json:"revokedAt,omitempty"`
	RevokedBy string     `json:"revokedBy,omitempty"`
}

type Device struct {
	ID         string    `json:"id"`
	UserID     string    `json:"userId"`
	Platform   string    `json:"platform"`
	PushToken  string    `json:"pushToken"`
	AppVersion string    `json:"appVersion"`
	LastSeenAt time.Time `json:"lastSeenAt"`
}

type AuditEvent struct {
	ID           string          `json:"id"`
	ActorUserID  string          `json:"actorUserId,omitempty"`
	Action       string          `json:"action"`
	ResourceType string          `json:"resourceType"`
	ResourceID   string          `json:"resourceId"`
	Metadata     json.RawMessage `json:"metadata"`
	CreatedAt    time.Time       `json:"createdAt"`
}
