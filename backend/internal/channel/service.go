package channel

import (
	"context"
	"time"

	"github.com/redis/go-redis/v9"
)

type Service struct {
	redis *redis.Client
}

func NewService(redisClient *redis.Client) *Service {
	return &Service{redis: redisClient}
}

func (s *Service) SpeakerLockKey(channelID string) string {
	return "channel:" + channelID + ":speaker_lock"
}

func (s *Service) TryAcquireSpeaker(ctx context.Context, channelID, userID string) bool {
	ok, err := s.redis.SetNX(ctx, s.SpeakerLockKey(channelID), userID, 3*time.Second).Result()
	return err == nil && ok
}

func (s *Service) RenewSpeaker(ctx context.Context, channelID, userID string) bool {
	key := s.SpeakerLockKey(channelID)
	owner, err := s.redis.Get(ctx, key).Result()
	if err != nil || owner != userID {
		return false
	}
	return s.redis.Expire(ctx, key, 3*time.Second).Err() == nil
}

func (s *Service) ReleaseSpeaker(ctx context.Context, channelID, userID string) {
	key := s.SpeakerLockKey(channelID)
	owner, err := s.redis.Get(ctx, key).Result()
	if err == nil && owner == userID {
		_ = s.redis.Del(ctx, key).Err()
	}
}

func (s *Service) ActiveSpeaker(ctx context.Context, channelID string) string {
	owner, _ := s.redis.Get(ctx, s.SpeakerLockKey(channelID)).Result()
	return owner
}
