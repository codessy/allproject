package httpapi

import (
	"testing"
	"time"
)

func TestWSMessageLimiterBlocksWithinWindow(t *testing.T) {
	limiter := newWSMessageLimiter(2, time.Second)
	now := time.Now()

	if !limiter.Allow(now) {
		t.Fatal("expected first message to pass")
	}
	if !limiter.Allow(now.Add(100 * time.Millisecond)) {
		t.Fatal("expected second message to pass")
	}
	if limiter.Allow(now.Add(200 * time.Millisecond)) {
		t.Fatal("expected third message to be blocked")
	}
}

func TestWSMessageLimiterResetsAfterWindow(t *testing.T) {
	limiter := newWSMessageLimiter(1, time.Second)
	now := time.Now()

	if !limiter.Allow(now) {
		t.Fatal("expected first message to pass")
	}
	if limiter.Allow(now.Add(100 * time.Millisecond)) {
		t.Fatal("expected second message in same window to be blocked")
	}
	if !limiter.Allow(now.Add(1100 * time.Millisecond)) {
		t.Fatal("expected limiter to reset after window")
	}
}
