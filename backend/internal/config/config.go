package config

import (
	"os"
	"strconv"
)

type Config struct {
	AppEnv                   string
	Port                     string
	RedisAddr                string
	PostgresDSN              string
	LiveKitURL               string
	LiveKitAPIKey            string
	LiveKitSecret            string
	JWTIssuer                string
	JWTSecret                string
	WebSocketURL             string
	PushProvider             string
	FCMProjectID             string
	FCMCredentials           string
	PushQueueSize            int
	PushWorkers              int
	PushQueueName            string
	PushMaxAttempts          int
	PushRetryBaseMs          int
	PushProcessingTimeoutSec int
	PushDeadLetterQueueName  string
	WSConnectRateLimit       int
	WSConnectWindowSec       int
	WSMessageRateLimit       int
	WSMessageWindowSec       int
}

func Load() Config {
	return Config{
		AppEnv:                   envOr("APP_ENV", "development"),
		Port:                     envOr("PORT", "8080"),
		RedisAddr:                envOr("REDIS_ADDR", "localhost:6379"),
		PostgresDSN:              envOr("POSTGRES_DSN", "postgres://app:app@localhost:5432/walkietalkie?sslmode=disable"),
		LiveKitURL:               envOr("LIVEKIT_URL", "ws://localhost:7880"),
		LiveKitAPIKey:            envOr("LIVEKIT_API_KEY", "devkey"),
		LiveKitSecret:            envOr("LIVEKIT_API_SECRET", "devsecret"),
		JWTIssuer:                envOr("JWT_ISSUER", "walkietalkie"),
		JWTSecret:                envOr("JWT_SECRET", "change-me"),
		WebSocketURL:             envOr("WS_URL", "ws://localhost:8080/v1/ws"),
		PushProvider:             envOr("PUSH_PROVIDER", "noop"),
		FCMProjectID:             envOr("FCM_PROJECT_ID", ""),
		FCMCredentials:           envOr("FCM_CREDENTIALS_JSON", ""),
		PushQueueSize:            envIntOr("PUSH_QUEUE_SIZE", 128),
		PushWorkers:              envIntOr("PUSH_WORKERS", 2),
		PushQueueName:            envOr("PUSH_QUEUE_NAME", "push:invite:pending"),
		PushMaxAttempts:          envIntOr("PUSH_MAX_ATTEMPTS", 5),
		PushRetryBaseMs:          envIntOr("PUSH_RETRY_BASE_MS", 500),
		PushProcessingTimeoutSec: envIntOr("PUSH_PROCESSING_TIMEOUT_SEC", 30),
		PushDeadLetterQueueName:  envOr("PUSH_DLQ_NAME", "push:invite:dead"),
		WSConnectRateLimit:       envIntOr("WS_CONNECT_RATE_LIMIT", 30),
		WSConnectWindowSec:       envIntOr("WS_CONNECT_WINDOW_SEC", 60),
		WSMessageRateLimit:       envIntOr("WS_MESSAGE_RATE_LIMIT", 60),
		WSMessageWindowSec:       envIntOr("WS_MESSAGE_WINDOW_SEC", 10),
	}
}

func envOr(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

func envIntOr(key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}
