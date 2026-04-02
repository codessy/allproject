package channel

import (
	"context"
	"testing"
	"time"

	miniredis "github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

func newTestChannelService(t *testing.T) (*Service, *miniredis.Miniredis, context.Context) {
	t.Helper()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("start miniredis: %v", err)
	}

	client := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() {
		_ = client.Close()
		mr.Close()
	})

	return NewService(client), mr, context.Background()
}

func TestSpeakerLockKeyUsesChannelID(t *testing.T) {
	service, _, _ := newTestChannelService(t)

	if got := service.SpeakerLockKey("alpha"); got != "channel:alpha:speaker_lock" {
		t.Fatalf("unexpected speaker lock key: %q", got)
	}
}

func TestTryAcquireSpeakerAllowsFirstUserOnly(t *testing.T) {
	service, _, ctx := newTestChannelService(t)

	if !service.TryAcquireSpeaker(ctx, "alpha", "user-1") {
		t.Fatal("expected first acquire to succeed")
	}
	if service.TryAcquireSpeaker(ctx, "alpha", "user-2") {
		t.Fatal("expected second acquire to fail while lock is held")
	}
	if got := service.ActiveSpeaker(ctx, "alpha"); got != "user-1" {
		t.Fatalf("expected active speaker user-1, got %q", got)
	}
}

func TestRenewSpeakerExtendsLeaseForOwnerOnly(t *testing.T) {
	service, mr, ctx := newTestChannelService(t)

	if !service.TryAcquireSpeaker(ctx, "alpha", "user-1") {
		t.Fatal("expected acquire to succeed")
	}

	initialTTL := mr.TTL(service.SpeakerLockKey("alpha"))
	if initialTTL <= 0 {
		t.Fatalf("expected positive initial TTL, got %v", initialTTL)
	}

	mr.FastForward(2 * time.Second)
	if !service.RenewSpeaker(ctx, "alpha", "user-1") {
		t.Fatal("expected owner renewal to succeed")
	}

	renewedTTL := mr.TTL(service.SpeakerLockKey("alpha"))
	if renewedTTL <= initialTTL/2 {
		t.Fatalf("expected renewed TTL to be extended, got %v after %v", renewedTTL, initialTTL)
	}

	if service.RenewSpeaker(ctx, "alpha", "user-2") {
		t.Fatal("expected non-owner renewal to fail")
	}
}

func TestReleaseSpeakerOnlyRemovesOwnerLock(t *testing.T) {
	service, _, ctx := newTestChannelService(t)

	if !service.TryAcquireSpeaker(ctx, "alpha", "user-1") {
		t.Fatal("expected acquire to succeed")
	}

	service.ReleaseSpeaker(ctx, "alpha", "user-2")
	if got := service.ActiveSpeaker(ctx, "alpha"); got != "user-1" {
		t.Fatalf("expected lock to remain with user-1, got %q", got)
	}

	service.ReleaseSpeaker(ctx, "alpha", "user-1")
	if got := service.ActiveSpeaker(ctx, "alpha"); got != "" {
		t.Fatalf("expected lock to be cleared, got %q", got)
	}
}

func TestActiveSpeakerReturnsEmptyWhenLeaseExpires(t *testing.T) {
	service, mr, ctx := newTestChannelService(t)

	if !service.TryAcquireSpeaker(ctx, "alpha", "user-1") {
		t.Fatal("expected acquire to succeed")
	}

	mr.FastForward(4 * time.Second)
	if got := service.ActiveSpeaker(ctx, "alpha"); got != "" {
		t.Fatalf("expected no active speaker after expiry, got %q", got)
	}
}
