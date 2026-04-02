package push

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"math"
	"sync/atomic"
	"time"

	"github.com/redis/go-redis/v9"
)

var ErrQueueFull = errors.New("push queue full")

type RedisQueueService struct {
	base           Service
	redisClient    *redis.Client
	pendingKey     string
	processingKey  string
	leaseKey       string
	deadLetterKey  string
	queueSize      int
	maxAttempts    int
	retryBaseMs    int
	processingTTL  time.Duration
	enqueuedCount  int64
	successCount   int64
	retryCount     int64
	deadCount      int64
	recoveredCount int64
	failureCount   int64
}

type QueueStats struct {
	PendingDepth         int64  `json:"pendingDepth"`
	ProcessingDepth      int64  `json:"processingDepth"`
	DeadLetterDepth      int64  `json:"deadLetterDepth"`
	EnqueuedTotal        int64  `json:"enqueuedTotal"`
	SuccessTotal         int64  `json:"successTotal"`
	RetryTotal           int64  `json:"retryTotal"`
	DeadLetterTotal      int64  `json:"deadLetterTotal"`
	RecoveryTotal        int64  `json:"recoveryTotal"`
	FailureTotal         int64  `json:"failureTotal"`
	MaxAttempts          int    `json:"maxAttempts"`
	RetryBaseMs          int    `json:"retryBaseMs"`
	ProcessingTimeoutSec int    `json:"processingTimeoutSec"`
	QueueName            string `json:"queueName"`
	ProcessingQueueName  string `json:"processingQueueName"`
	DeadLetterQueueName  string `json:"deadLetterQueueName"`
}

type inviteJob struct {
	ID                string             `json:"id"`
	Notification      InviteNotification `json:"notification"`
	Attempt           int                `json:"attempt"`
	LastError         string             `json:"lastError,omitempty"`
	LeasedUntilUnix   int64              `json:"leasedUntilUnix,omitempty"`
	CreatedAtUnix     int64              `json:"createdAtUnix"`
	LastAttemptAtUnix int64              `json:"lastAttemptAtUnix,omitempty"`
}

func NewRedisQueueService(
	ctx context.Context,
	base Service,
	redisClient *redis.Client,
	cfg QueueConfig,
) *RedisQueueService {
	if cfg.Workers <= 0 {
		cfg.Workers = 1
	}
	if cfg.QueueName == "" {
		cfg.QueueName = "push:invite:pending"
	}
	if cfg.DeadLetterQueueName == "" {
		cfg.DeadLetterQueueName = cfg.QueueName + ":dead"
	}
	if cfg.MaxAttempts <= 0 {
		cfg.MaxAttempts = 5
	}
	if cfg.RetryBaseMs <= 0 {
		cfg.RetryBaseMs = 500
	}
	if cfg.ProcessingTimeoutSec <= 0 {
		cfg.ProcessingTimeoutSec = 30
	}

	service := &RedisQueueService{
		base:          base,
		redisClient:   redisClient,
		pendingKey:    cfg.QueueName,
		processingKey: cfg.QueueName + ":processing",
		leaseKey:      cfg.QueueName + ":leases",
		deadLetterKey: cfg.DeadLetterQueueName,
		queueSize:     queueSizeOrDefault(cfg.QueueSize),
		maxAttempts:   cfg.MaxAttempts,
		retryBaseMs:   cfg.RetryBaseMs,
		processingTTL: time.Duration(cfg.ProcessingTimeoutSec) * time.Second,
	}

	for workerIndex := 0; workerIndex < cfg.Workers; workerIndex++ {
		go service.runWorker(ctx)
	}
	go service.runRecoveryLoop(ctx)

	return service
}

func (s *RedisQueueService) SendInvite(ctx context.Context, notification InviteNotification) error {
	job := inviteJob{
		ID:            notification.ChannelID + ":" + notification.UserID + ":" + time.Now().UTC().Format(time.RFC3339Nano),
		Notification:  notification,
		Attempt:       0,
		CreatedAtUnix: time.Now().Unix(),
	}

	body, err := json.Marshal(job)
	if err != nil {
		return err
	}

	currentLength, err := s.redisClient.LLen(ctx, s.pendingKey).Result()
	if err == nil && currentLength >= int64(s.queueSize) {
		return ErrQueueFull
	}

	if err := s.redisClient.LPush(ctx, s.pendingKey, body).Err(); err != nil {
		return err
	}
	atomic.AddInt64(&s.enqueuedCount, 1)
	return nil
}

func (s *RedisQueueService) runWorker(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		body, err := s.redisClient.BRPopLPush(ctx, s.pendingKey, s.processingKey, 5*time.Second).Result()
		if err != nil {
			if errors.Is(err, redis.Nil) || errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
				continue
			}
			log.Printf("push queue pop failed: %v", err)
			continue
		}

		var job inviteJob
		if err := json.Unmarshal([]byte(body), &job); err != nil {
			log.Printf("push queue decode failed: %v", err)
			_ = s.redisClient.LRem(ctx, s.processingKey, 1, body).Err()
			continue
		}

		job.LeasedUntilUnix = time.Now().Add(s.processingTTL).Unix()
		job.LastAttemptAtUnix = time.Now().Unix()
		leasedBody, err := json.Marshal(job)
		if err == nil {
			_ = s.redisClient.LRem(ctx, s.processingKey, 1, body).Err()
			if err := s.redisClient.LPush(ctx, s.processingKey, leasedBody).Err(); err == nil {
				body = string(leasedBody)
			}
			_ = s.redisClient.HSet(ctx, s.leaseKey, job.ID, job.LeasedUntilUnix).Err()
		}

		if err := s.base.SendInvite(ctx, job.Notification); err != nil {
			log.Printf("push delivery failed for user %s channel %s: %v", job.Notification.UserID, job.Notification.ChannelID, err)
			atomic.AddInt64(&s.failureCount, 1)
			s.handleFailure(ctx, body, job, err)
			continue
		}

		if err := s.redisClient.LRem(ctx, s.processingKey, 1, body).Err(); err != nil {
			log.Printf("push queue ack failed: %v", err)
		}
		_ = s.redisClient.HDel(ctx, s.leaseKey, job.ID).Err()
		atomic.AddInt64(&s.successCount, 1)
	}
}

func (s *RedisQueueService) handleFailure(ctx context.Context, body string, job inviteJob, deliveryErr error) {
	job.Attempt++
	job.LastError = deliveryErr.Error()
	job.LeasedUntilUnix = 0

	_ = s.redisClient.LRem(ctx, s.processingKey, 1, body).Err()
	_ = s.redisClient.HDel(ctx, s.leaseKey, job.ID).Err()

	if job.Attempt >= s.maxAttempts {
		deadBody, err := json.Marshal(job)
		if err != nil {
			log.Printf("push DLQ marshal failed: %v", err)
			return
		}
		if err := s.redisClient.LPush(ctx, s.deadLetterKey, deadBody).Err(); err != nil {
			log.Printf("push DLQ enqueue failed: %v", err)
		}
		atomic.AddInt64(&s.deadCount, 1)
		return
	}

	backoffMs := s.retryDelay(job.Attempt)
	time.Sleep(time.Duration(backoffMs) * time.Millisecond)

	retryBody, err := json.Marshal(job)
	if err != nil {
		log.Printf("push retry marshal failed: %v", err)
		return
	}
	if err := s.redisClient.RPush(ctx, s.pendingKey, retryBody).Err(); err != nil {
		log.Printf("push retry enqueue failed: %v", err)
		return
	}
	atomic.AddInt64(&s.retryCount, 1)
}

func (s *RedisQueueService) runRecoveryLoop(ctx context.Context) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.recoverExpiredJobs(ctx)
		}
	}
}

func (s *RedisQueueService) recoverExpiredJobs(ctx context.Context) {
	items, err := s.redisClient.LRange(ctx, s.processingKey, 0, -1).Result()
	if err != nil {
		log.Printf("push recovery lrange failed: %v", err)
		return
	}

	nowUnix := time.Now().Unix()
	for _, body := range items {
		var job inviteJob
		if err := json.Unmarshal([]byte(body), &job); err != nil {
			continue
		}
		if job.LeasedUntilUnix == 0 || job.LeasedUntilUnix > nowUnix {
			continue
		}

		if err := s.redisClient.LRem(ctx, s.processingKey, 1, body).Err(); err != nil {
			continue
		}
		_ = s.redisClient.HDel(ctx, s.leaseKey, job.ID).Err()
		atomic.AddInt64(&s.recoveredCount, 1)

		job.LastError = "processing lease expired"
		if job.Attempt >= s.maxAttempts {
			deadBody, err := json.Marshal(job)
			if err == nil {
				_ = s.redisClient.LPush(ctx, s.deadLetterKey, deadBody).Err()
				atomic.AddInt64(&s.deadCount, 1)
			}
			continue
		}

		retryBody, err := json.Marshal(job)
		if err == nil {
			_ = s.redisClient.RPush(ctx, s.pendingKey, retryBody).Err()
			atomic.AddInt64(&s.retryCount, 1)
		}
	}
}

func (s *RedisQueueService) Stats(ctx context.Context) QueueStats {
	pendingDepth, _ := s.redisClient.LLen(ctx, s.pendingKey).Result()
	processingDepth, _ := s.redisClient.LLen(ctx, s.processingKey).Result()
	deadDepth, _ := s.redisClient.LLen(ctx, s.deadLetterKey).Result()

	return QueueStats{
		PendingDepth:         pendingDepth,
		ProcessingDepth:      processingDepth,
		DeadLetterDepth:      deadDepth,
		EnqueuedTotal:        atomic.LoadInt64(&s.enqueuedCount),
		SuccessTotal:         atomic.LoadInt64(&s.successCount),
		RetryTotal:           atomic.LoadInt64(&s.retryCount),
		DeadLetterTotal:      atomic.LoadInt64(&s.deadCount),
		RecoveryTotal:        atomic.LoadInt64(&s.recoveredCount),
		FailureTotal:         atomic.LoadInt64(&s.failureCount),
		MaxAttempts:          s.maxAttempts,
		RetryBaseMs:          s.retryBaseMs,
		ProcessingTimeoutSec: int(s.processingTTL / time.Second),
		QueueName:            s.pendingKey,
		ProcessingQueueName:  s.processingKey,
		DeadLetterQueueName:  s.deadLetterKey,
	}
}

func (s *RedisQueueService) retryDelay(attempt int) int {
	multiplier := math.Pow(2, float64(attempt-1))
	delay := int(float64(s.retryBaseMs) * multiplier)
	if delay > 30000 {
		return 30000
	}
	if delay < s.retryBaseMs {
		return s.retryBaseMs
	}
	return delay
}

func queueSizeOrDefault(queueSize int) int {
	if queueSize <= 0 {
		return 128
	}
	return queueSize
}
