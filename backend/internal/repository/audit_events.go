package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"walkietalkie/backend/internal/models"
)

type AuditRepository struct {
	pool *pgxpool.Pool
}

func NewAuditRepository(pool *pgxpool.Pool) *AuditRepository {
	return &AuditRepository{pool: pool}
}

func (r *AuditRepository) Create(
	ctx context.Context,
	actorUserID string,
	action string,
	resourceType string,
	resourceID string,
	metadata map[string]any,
) error {
	if metadata == nil {
		metadata = map[string]any{}
	}

	metadataJSON, err := json.Marshal(metadata)
	if err != nil {
		return fmt.Errorf("marshal audit metadata: %w", err)
	}

	_, err = r.pool.Exec(ctx, `
		INSERT INTO audit_events (actor_user_id, action, resource_type, resource_id, metadata)
		VALUES (NULLIF($1, '')::uuid, $2, $3, $4, $5::jsonb)
	`, actorUserID, action, resourceType, resourceID, string(metadataJSON))
	if err != nil {
		return fmt.Errorf("create audit event: %w", err)
	}
	return nil
}

func (r *AuditRepository) ListByChannel(ctx context.Context, channelID string, limit int) ([]models.AuditEvent, error) {
	if limit <= 0 {
		limit = 50
	}

	rows, err := r.pool.Query(ctx, `
		SELECT id::text, COALESCE(actor_user_id::text, ''), action, resource_type, resource_id, metadata::text, created_at
		FROM audit_events
		WHERE metadata->>'channelId' = $1
		ORDER BY created_at DESC
		LIMIT $2
	`, channelID, limit)
	if err != nil {
		return nil, fmt.Errorf("list audit events by channel: %w", err)
	}
	defer rows.Close()

	events := make([]models.AuditEvent, 0)
	for rows.Next() {
		var event models.AuditEvent
		var metadata string
		if err := rows.Scan(
			&event.ID,
			&event.ActorUserID,
			&event.Action,
			&event.ResourceType,
			&event.ResourceID,
			&metadata,
			&event.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan audit event: %w", err)
		}
		event.Metadata = json.RawMessage(metadata)
		events = append(events, event)
	}

	return events, rows.Err()
}
