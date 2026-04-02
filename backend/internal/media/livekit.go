package media

import (
	"time"

	lkauth "github.com/livekit/protocol/auth"
)

type LiveKitService struct {
	apiKey    string
	apiSecret string
}

func NewLiveKitService(apiKey, apiSecret string) *LiveKitService {
	return &LiveKitService{
		apiKey:    apiKey,
		apiSecret: apiSecret,
	}
}

func (s *LiveKitService) IssueRoomToken(identity, roomName string, canPublish bool) (string, error) {
	canSubscribe := true
	grant := &lkauth.VideoGrant{
		RoomJoin:     true,
		Room:         roomName,
		CanPublish:   &canPublish,
		CanSubscribe: &canSubscribe,
	}

	at := lkauth.NewAccessToken(s.apiKey, s.apiSecret)
	at.SetIdentity(identity)
	at.SetValidFor(30 * time.Minute)
	at.AddGrant(grant)

	return at.ToJWT()
}
