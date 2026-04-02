package push

type QueueConfig struct {
	QueueSize            int
	Workers              int
	QueueName            string
	MaxAttempts          int
	RetryBaseMs          int
	ProcessingTimeoutSec int
	DeadLetterQueueName  string
}
