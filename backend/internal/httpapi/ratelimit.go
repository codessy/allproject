package httpapi

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

func RateLimitMiddleware(
	redisClient interface {
		Incr(context.Context, string) *redis.IntCmd
		Expire(context.Context, string, time.Duration) *redis.BoolCmd
		TTL(context.Context, string) *redis.DurationCmd
	},
	bucket string,
	limit int64,
	window time.Duration,
	keyFn func(*gin.Context) string,
) gin.HandlerFunc {
	return func(c *gin.Context) {
		if redisClient == nil || limit <= 0 || window <= 0 {
			c.Next()
			return
		}

		identity := keyFn(c)
		key := fmt.Sprintf("ratelimit:%s:%s", bucket, identity)

		count, err := redisClient.Incr(c.Request.Context(), key).Result()
		if err != nil {
			c.Next()
			return
		}
		if count == 1 {
			_, _ = redisClient.Expire(c.Request.Context(), key, window).Result()
		}

		if count > limit {
			retryAfter := int(window.Seconds())
			if ttl, err := redisClient.TTL(c.Request.Context(), key).Result(); err == nil && ttl > 0 {
				retryAfter = int(ttl.Seconds())
				if retryAfter <= 0 {
					retryAfter = 1
				}
			}
			c.Header("Retry-After", fmt.Sprintf("%d", retryAfter))
			c.JSON(http.StatusTooManyRequests, gin.H{"error": "rate limit exceeded"})
			c.Abort()
			return
		}

		c.Next()
	}
}

func ClientIPKey(c *gin.Context) string {
	ip := c.ClientIP()
	if ip == "" {
		ip = "unknown"
	}
	return sanitizeRateLimitKey(ip)
}

func UserOrIPKey(c *gin.Context) string {
	if userID := c.GetString("userID"); userID != "" {
		return sanitizeRateLimitKey(userID)
	}
	return ClientIPKey(c)
}

func EmailOrIPKey(c *gin.Context) string {
	var body struct {
		Email string `json:"email"`
	}
	_ = c.ShouldBindBodyWithJSON(&body)
	if body.Email != "" {
		return sanitizeRateLimitKey(strings.ToLower(body.Email))
	}
	return ClientIPKey(c)
}

func sanitizeRateLimitKey(value string) string {
	value = strings.TrimSpace(strings.ToLower(value))
	replacer := strings.NewReplacer(":", "_", " ", "_", "@", "_at_", "/", "_")
	value = replacer.Replace(value)
	if ip := net.ParseIP(value); ip != nil {
		return ip.String()
	}
	if value == "" {
		return "unknown"
	}
	return value
}
