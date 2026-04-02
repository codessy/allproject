package push

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	miniredis "github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

type stubPushService struct {
	err error
}

func (s stubPushService) SendInvite(context.Context, InviteNotification) error {
	return s.err
}

type recordingPushService struct {
	notifications chan InviteNotification
}

func (s recordingPushService) SendInvite(_ context.Context, notification InviteNotification) error {
	select {
	case s.notifications <- notification:
	default:
	}
	return nil
}

func newTestRedisQueueService(t *testing.T, base Service, cfg QueueConfig) (*RedisQueueService, *miniredis.Miniredis, context.Context) {
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

	if cfg.QueueName == "" {
		cfg.QueueName = "test:push:pending"
	}
	if cfg.DeadLetterQueueName == "" {
		cfg.DeadLetterQueueName = cfg.QueueName + ":dead"
	}
	if cfg.MaxAttempts <= 0 {
		cfg.MaxAttempts = 5
	}
	if cfg.RetryBaseMs <= 0 {
		cfg.RetryBaseMs = 1
	}
	if cfg.ProcessingTimeoutSec <= 0 {
		cfg.ProcessingTimeoutSec = 1
	}

	service := &RedisQueueService{
		base:          base,
		redisClient:   client,
		pendingKey:    cfg.QueueName,
		processingKey: cfg.QueueName + ":processing",
		leaseKey:      cfg.QueueName + ":leases",
		deadLetterKey: cfg.DeadLetterQueueName,
		queueSize:     queueSizeOrDefault(cfg.QueueSize),
		maxAttempts:   cfg.MaxAttempts,
		retryBaseMs:   cfg.RetryBaseMs,
		processingTTL: time.Duration(cfg.ProcessingTimeoutSec) * time.Second,
	}
	return service, mr, context.Background()
}

func TestRedisQueueServiceSendInviteEnqueuesAndReportsStats(t *testing.T) {
	service, _, ctx := newTestRedisQueueService(t, stubPushService{}, QueueConfig{
		QueueName: "test:push:pending",
		Workers:   0,
		QueueSize: 10,
	})

	err := service.SendInvite(ctx, InviteNotification{
		UserID:      "user-1",
		ChannelID:   "channel-1",
		ChannelName: "Alpha",
		InviteToken: "invite-token",
	})
	if err != nil {
		t.Fatalf("send invite: %v", err)
	}

	stats := service.Stats(ctx)
	if stats.PendingDepth != 1 {
		t.Fatalf("expected pending depth 1, got %d", stats.PendingDepth)
	}
	if stats.EnqueuedTotal != 1 {
		t.Fatalf("expected enqueued total 1, got %d", stats.EnqueuedTotal)
	}
}

func TestRedisQueueServiceHandleFailureMovesToDeadLetter(t *testing.T) {
	service, mr, ctx := newTestRedisQueueService(t, stubPushService{}, QueueConfig{
		QueueName:            "test:push:pending",
		DeadLetterQueueName:  "test:push:dead",
		MaxAttempts:          1,
		RetryBaseMs:          1,
		ProcessingTimeoutSec: 1,
	})

	job := inviteJob{
		ID: "job-1",
		Notification: InviteNotification{
			UserID:    "user-1",
			ChannelID: "channel-1",
		},
		Attempt: 0,
	}
	body, err := marshalJob(job)
	if err != nil {
		t.Fatalf("marshal job: %v", err)
	}
	mr.RPush(service.processingKey, body)

	service.handleFailure(ctx, body, job, errors.New("push failed"))

	if got, err := mr.List(service.deadLetterKey); err != nil || len(got) != 1 {
		t.Fatalf("expected 1 dead-letter item, got %d", len(got))
	}

	stats := service.Stats(ctx)
	if stats.DeadLetterTotal != 1 {
		t.Fatalf("expected dead letter total 1, got %d", stats.DeadLetterTotal)
	}
}

func TestRedisQueueServiceRecoverExpiredJobsRequeuesWork(t *testing.T) {
	service, mr, ctx := newTestRedisQueueService(t, stubPushService{}, QueueConfig{
		QueueName:            "test:push:pending",
		DeadLetterQueueName:  "test:push:dead",
		MaxAttempts:          3,
		RetryBaseMs:          1,
		ProcessingTimeoutSec: 1,
	})

	job := inviteJob{
		ID: "job-2",
		Notification: InviteNotification{
			UserID:    "user-2",
			ChannelID: "channel-2",
		},
		Attempt:         1,
		LeasedUntilUnix: time.Now().Add(-time.Minute).Unix(),
	}
	body, err := marshalJob(job)
	if err != nil {
		t.Fatalf("marshal job: %v", err)
	}
	mr.RPush(service.processingKey, body)

	service.recoverExpiredJobs(ctx)

	if got, err := mr.List(service.pendingKey); err != nil || len(got) != 1 {
		t.Fatalf("expected 1 pending item after recovery, got %d", len(got))
	}
	if got, err := mr.List(service.processingKey); err == nil && len(got) != 0 {
		t.Fatalf("expected empty processing queue, got %d", len(got))
	}

	stats := service.Stats(ctx)
	if stats.RecoveryTotal != 1 {
		t.Fatalf("expected recovery total 1, got %d", stats.RecoveryTotal)
	}
	if stats.RetryTotal != 1 {
		t.Fatalf("expected retry total 1, got %d", stats.RetryTotal)
	}
}

func TestRedisQueueServiceSendInviteRejectsWhenQueueFull(t *testing.T) {
	service, _, ctx := newTestRedisQueueService(t, stubPushService{}, QueueConfig{
		QueueName: "test:push:pending",
		Workers:   0,
		QueueSize: 1,
	})

	if err := service.SendInvite(ctx, InviteNotification{
		UserID:    "user-1",
		ChannelID: "channel-1",
	}); err != nil {
		t.Fatalf("first send invite: %v", err)
	}

	err := service.SendInvite(ctx, InviteNotification{
		UserID:    "user-2",
		ChannelID: "channel-1",
	})
	if !errors.Is(err, ErrQueueFull) {
		t.Fatalf("expected ErrQueueFull, got %v", err)
	}
}

func TestRedisQueueServiceRunWorkerProcessesAndAcknowledgesJob(t *testing.T) {
	notifications := make(chan InviteNotification, 1)
	service, _, baseCtx := newTestRedisQueueService(t, recordingPushService{notifications: notifications}, QueueConfig{
		QueueName:            "test:push:pending",
		DeadLetterQueueName:  "test:push:dead",
		MaxAttempts:          3,
		RetryBaseMs:          1,
		ProcessingTimeoutSec: 1,
	})

	ctx, cancel := context.WithCancel(baseCtx)
	defer cancel()
	done := make(chan struct{})
	go func() {
		service.runWorker(ctx)
		close(done)
	}()

	if err := service.SendInvite(ctx, InviteNotification{
		UserID:      "user-1",
		ChannelID:   "channel-1",
		ChannelName: "Alpha",
		InviteToken: "invite-token",
	}); err != nil {
		t.Fatalf("send invite: %v", err)
	}

	select {
	case notification := <-notifications:
		if notification.UserID != "user-1" || notification.ChannelID != "channel-1" {
			t.Fatalf("unexpected delivered notification: %#v", notification)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for worker to deliver notification")
	}

	deadline := time.Now().Add(2 * time.Second)
	for {
		stats := service.Stats(baseCtx)
		if stats.SuccessTotal == 1 && stats.PendingDepth == 0 && stats.ProcessingDepth == 0 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("worker did not ack job in time: %+v", stats)
		}
		time.Sleep(10 * time.Millisecond)
	}

	cancel()
	select {
	case <-done:
	case <-time.After(6 * time.Second):
		t.Fatal("worker did not stop after context cancellation")
	}

	stats := service.Stats(baseCtx)
	if stats.SuccessTotal != 1 {
		t.Fatalf("expected success total 1, got %d", stats.SuccessTotal)
	}
	if stats.PendingDepth != 0 || stats.ProcessingDepth != 0 {
		t.Fatalf("expected empty queues after ack, got pending=%d processing=%d", stats.PendingDepth, stats.ProcessingDepth)
	}
}

func TestRedisQueueServiceRecoverExpiredJobsMovesExhaustedWorkToDeadLetter(t *testing.T) {
	service, mr, ctx := newTestRedisQueueService(t, stubPushService{}, QueueConfig{
		QueueName:            "test:push:pending",
		DeadLetterQueueName:  "test:push:dead",
		MaxAttempts:          2,
		RetryBaseMs:          1,
		ProcessingTimeoutSec: 1,
	})

	job := inviteJob{
		ID: "job-3",
		Notification: InviteNotification{
			UserID:    "user-3",
			ChannelID: "channel-3",
		},
		Attempt:         2,
		LeasedUntilUnix: time.Now().Add(-time.Minute).Unix(),
	}
	body, err := marshalJob(job)
	if err != nil {
		t.Fatalf("marshal job: %v", err)
	}
	mr.RPush(service.processingKey, body)

	service.recoverExpiredJobs(ctx)

	if got, err := mr.List(service.deadLetterKey); err != nil || len(got) != 1 {
		t.Fatalf("expected 1 dead-letter item after recovery, got %d", len(got))
	}
	stats := service.Stats(ctx)
	if stats.PendingDepth != 0 {
		t.Fatalf("expected 0 pending items after recovery to DLQ, got %d", stats.PendingDepth)
	}
	if stats.RecoveryTotal != 1 {
		t.Fatalf("expected recovery total 1, got %d", stats.RecoveryTotal)
	}
	if stats.DeadLetterTotal != 1 {
		t.Fatalf("expected dead letter total 1, got %d", stats.DeadLetterTotal)
	}
}

func TestRedisQueueServiceRetryDelayCapsAtThirtySeconds(t *testing.T) {
	service, _, _ := newTestRedisQueueService(t, stubPushService{}, QueueConfig{
		RetryBaseMs: 1000,
	})

	if got := service.retryDelay(1); got != 1000 {
		t.Fatalf("expected first retry delay 1000ms, got %d", got)
	}
	if got := service.retryDelay(10); got != 30000 {
		t.Fatalf("expected retry delay cap 30000ms, got %d", got)
	}
}

func marshalJob(job inviteJob) (string, error) {
	body, err := json.Marshal(job)
	if err != nil {
		return "", err
	}
	return string(body), nil
}
