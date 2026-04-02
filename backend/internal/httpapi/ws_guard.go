package httpapi

import "time"

type wsMessageLimiter struct {
	limit       int
	window      time.Duration
	windowStart time.Time
	count       int
}

func newWSMessageLimiter(limit int, window time.Duration) *wsMessageLimiter {
	return &wsMessageLimiter{
		limit:       limit,
		window:      window,
		windowStart: time.Now(),
	}
}

func (l *wsMessageLimiter) Allow(now time.Time) bool {
	if l.limit <= 0 || l.window <= 0 {
		return true
	}

	if now.Sub(l.windowStart) >= l.window {
		l.windowStart = now
		l.count = 0
	}

	if l.count >= l.limit {
		return false
	}

	l.count++
	return true
}
