package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"walkietalkie/backend/internal/models"
)

type InviteRepository struct {
	pool *pgxpool.Pool
}

func NewInviteRepository(pool *pgxpool.Pool) *InviteRepository {
	return &InviteRepository{pool: pool}
}

func (r *InviteRepository) Create(ctx context.Context, channelID, createdBy, tokenHash string, expiresAt time.Time, maxUses int) (models.Invite, error) {
	invite := models.Invite{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO channel_invites (channel_id, token_hash, created_by, expires_at, max_uses)
		VALUES ($1::uuid, $2, $3::uuid, $4, $5)
		RETURNING id::text, channel_id::text, token_hash, created_by::text, expires_at, max_uses, used_count, created_at, revoked_at, COALESCE(revoked_by::text, '')
	`, channelID, tokenHash, createdBy, expiresAt, maxUses).Scan(
		&invite.ID,
		&invite.ChannelID,
		&invite.TokenHash,
		&invite.CreatedBy,
		&invite.ExpiresAt,
		&invite.MaxUses,
		&invite.UsedCount,
		&invite.CreatedAt,
		&invite.RevokedAt,
		&invite.RevokedBy,
	)
	if err != nil {
		return models.Invite{}, fmt.Errorf("create invite: %w", err)
	}
	return invite, nil
}

func (r *InviteRepository) GetValidByHash(ctx context.Context, tokenHash string) (models.Invite, error) {
	invite := models.Invite{}
	err := r.pool.QueryRow(ctx, `
		SELECT id::text, channel_id::text, token_hash, created_by::text, expires_at, max_uses, used_count, created_at, revoked_at, COALESCE(revoked_by::text, '')
		FROM channel_invites
		WHERE token_hash = $1
		  AND expires_at > NOW()
		  AND used_count < max_uses
		  AND revoked_at IS NULL
	`, tokenHash).Scan(
		&invite.ID,
		&invite.ChannelID,
		&invite.TokenHash,
		&invite.CreatedBy,
		&invite.ExpiresAt,
		&invite.MaxUses,
		&invite.UsedCount,
		&invite.CreatedAt,
		&invite.RevokedAt,
		&invite.RevokedBy,
	)
	if err != nil {
		return models.Invite{}, fmt.Errorf("get valid invite: %w", err)
	}
	return invite, nil
}

func (r *InviteRepository) GetByID(ctx context.Context, inviteID string) (models.Invite, error) {
	invite := models.Invite{}
	err := r.pool.QueryRow(ctx, `
		SELECT id::text, channel_id::text, token_hash, created_by::text, expires_at, max_uses, used_count, created_at, revoked_at, COALESCE(revoked_by::text, '')
		FROM channel_invites
		WHERE id::text = $1
	`, inviteID).Scan(
		&invite.ID,
		&invite.ChannelID,
		&invite.TokenHash,
		&invite.CreatedBy,
		&invite.ExpiresAt,
		&invite.MaxUses,
		&invite.UsedCount,
		&invite.CreatedAt,
		&invite.RevokedAt,
		&invite.RevokedBy,
	)
	if err != nil {
		return models.Invite{}, fmt.Errorf("get invite by id: %w", err)
	}
	return invite, nil
}

func (r *InviteRepository) IncrementUsage(ctx context.Context, inviteID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE channel_invites
		SET used_count = used_count + 1
		WHERE id::text = $1
	`, inviteID)
	if err != nil {
		return fmt.Errorf("increment invite usage: %w", err)
	}
	return nil
}

func (r *InviteRepository) Revoke(ctx context.Context, inviteID, revokedBy string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE channel_invites
		SET revoked_at = NOW(),
		    revoked_by = $2::uuid
		WHERE id::text = $1
		  AND revoked_at IS NULL
	`, inviteID, revokedBy)
	if err != nil {
		return fmt.Errorf("revoke invite: %w", err)
	}
	return nil
}

func (r *InviteRepository) ListByChannel(ctx context.Context, channelID string, limit int) ([]models.Invite, error) {
	if limit <= 0 {
		limit = 50
	}

	rows, err := r.pool.Query(ctx, `
		SELECT id::text, channel_id::text, token_hash, created_by::text, expires_at, max_uses, used_count, created_at, revoked_at, COALESCE(revoked_by::text, '')
		FROM channel_invites
		WHERE channel_id::text = $1
		ORDER BY created_at DESC
		LIMIT $2
	`, channelID, limit)
	if err != nil {
		return nil, fmt.Errorf("list invites by channel: %w", err)
	}
	defer rows.Close()

	invites := make([]models.Invite, 0)
	for rows.Next() {
		var invite models.Invite
		if err := rows.Scan(
			&invite.ID,
			&invite.ChannelID,
			&invite.TokenHash,
			&invite.CreatedBy,
			&invite.ExpiresAt,
			&invite.MaxUses,
			&invite.UsedCount,
			&invite.CreatedAt,
			&invite.RevokedAt,
			&invite.RevokedBy,
		); err != nil {
			return nil, fmt.Errorf("scan invite: %w", err)
		}
		invites = append(invites, invite)
	}

	return invites, rows.Err()
}
