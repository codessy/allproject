package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"walkietalkie/backend/internal/models"
)

type ChannelRepository struct {
	pool *pgxpool.Pool
}

func NewChannelRepository(pool *pgxpool.Pool) *ChannelRepository {
	return &ChannelRepository{pool: pool}
}

func (r *ChannelRepository) ListByUser(ctx context.Context, userID string) ([]models.Channel, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT c.id::text, c.name, c.type, c.owner_user_id::text, cm.role, COALESCE(c.active_speaker_user_id::text, ''), c.created_at
		FROM channels c
		INNER JOIN channel_members cm ON cm.channel_id = c.id
		WHERE cm.user_id::text = $1
		ORDER BY c.created_at ASC
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("list channels: %w", err)
	}
	defer rows.Close()

	var channels []models.Channel
	for rows.Next() {
		var item models.Channel
		if err := rows.Scan(
			&item.ID,
			&item.Name,
			&item.Type,
			&item.OwnerUserID,
			&item.Role,
			&item.ActiveSpeakerUserID,
			&item.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan channel: %w", err)
		}
		channels = append(channels, item)
	}

	if channels == nil {
		channels = []models.Channel{}
	}

	return channels, rows.Err()
}

func (r *ChannelRepository) GetByID(ctx context.Context, channelID string) (models.Channel, error) {
	var channel models.Channel
	err := r.pool.QueryRow(ctx, `
		SELECT id::text, name, type, owner_user_id::text, COALESCE(active_speaker_user_id::text, ''), created_at
		FROM channels
		WHERE id::text = $1
	`, channelID).Scan(
		&channel.ID,
		&channel.Name,
		&channel.Type,
		&channel.OwnerUserID,
		&channel.ActiveSpeakerUserID,
		&channel.CreatedAt,
	)
	if err != nil {
		return models.Channel{}, fmt.Errorf("get channel by id: %w", err)
	}
	return channel, nil
}

func (r *ChannelRepository) UserHasMembership(ctx context.Context, channelID, userID string) (bool, error) {
	var exists bool
	if err := r.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1
			FROM channel_members
			WHERE channel_id::text = $1 AND user_id::text = $2
		)
	`, channelID, userID).Scan(&exists); err != nil {
		return false, fmt.Errorf("check membership: %w", err)
	}
	return exists, nil
}

func (r *ChannelRepository) GetMembershipRole(ctx context.Context, channelID, userID string) (string, error) {
	var role string
	if err := r.pool.QueryRow(ctx, `
		SELECT role
		FROM channel_members
		WHERE channel_id::text = $1 AND user_id::text = $2
	`, channelID, userID).Scan(&role); err != nil {
		return "", fmt.Errorf("get membership role: %w", err)
	}
	return role, nil
}

func (r *ChannelRepository) Create(ctx context.Context, ownerUserID, name, channelType string) (models.Channel, error) {
	channel := models.Channel{}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return models.Channel{}, fmt.Errorf("begin create channel tx: %w", err)
	}
	defer tx.Rollback(ctx)

	err = tx.QueryRow(ctx, `
		INSERT INTO channels (name, type, owner_user_id)
		VALUES ($1, $2, $3::uuid)
		RETURNING id::text, name, type, owner_user_id::text, COALESCE(active_speaker_user_id::text, ''), created_at
	`, name, channelType, ownerUserID).Scan(
		&channel.ID,
		&channel.Name,
		&channel.Type,
		&channel.OwnerUserID,
		&channel.ActiveSpeakerUserID,
		&channel.CreatedAt,
	)
	if err != nil {
		return models.Channel{}, fmt.Errorf("insert channel: %w", err)
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO channel_members (channel_id, user_id, role)
		VALUES ($1::uuid, $2::uuid, 'owner')
	`, channel.ID, ownerUserID); err != nil {
		return models.Channel{}, fmt.Errorf("insert channel owner membership: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return models.Channel{}, fmt.Errorf("commit create channel: %w", err)
	}

	return channel, nil
}

func (r *ChannelRepository) AddMember(ctx context.Context, channelID, userID, role string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO channel_members (channel_id, user_id, role)
		VALUES ($1::uuid, $2::uuid, $3)
		ON CONFLICT (channel_id, user_id) DO NOTHING
	`, channelID, userID, role)
	if err != nil {
		return fmt.Errorf("add channel member: %w", err)
	}
	return nil
}

func (r *ChannelRepository) Update(ctx context.Context, channelID, name, channelType string) (models.Channel, error) {
	var channel models.Channel
	err := r.pool.QueryRow(ctx, `
		UPDATE channels
		SET name = $2,
		    type = $3
		WHERE id::text = $1
		RETURNING id::text, name, type, owner_user_id::text, COALESCE(active_speaker_user_id::text, ''), created_at
	`, channelID, name, channelType).Scan(
		&channel.ID,
		&channel.Name,
		&channel.Type,
		&channel.OwnerUserID,
		&channel.ActiveSpeakerUserID,
		&channel.CreatedAt,
	)
	if err != nil {
		return models.Channel{}, fmt.Errorf("update channel: %w", err)
	}
	return channel, nil
}

func (r *ChannelRepository) ListMemberships(ctx context.Context, channelID string) ([]models.ChannelMembership, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT channel_id::text, user_id::text, role, joined_at
		FROM channel_members
		WHERE channel_id::text = $1
		ORDER BY joined_at ASC
	`, channelID)
	if err != nil {
		return nil, fmt.Errorf("list channel memberships: %w", err)
	}
	defer rows.Close()

	memberships := make([]models.ChannelMembership, 0)
	for rows.Next() {
		var item models.ChannelMembership
		if err := rows.Scan(&item.ChannelID, &item.UserID, &item.Role, &item.JoinedAt); err != nil {
			return nil, fmt.Errorf("scan channel membership: %w", err)
		}
		memberships = append(memberships, item)
	}

	return memberships, rows.Err()
}

func (r *ChannelRepository) UpsertMembershipRole(ctx context.Context, channelID, userID, role string) (models.ChannelMembership, error) {
	var membership models.ChannelMembership
	err := r.pool.QueryRow(ctx, `
		INSERT INTO channel_members (channel_id, user_id, role)
		VALUES ($1::uuid, $2::uuid, $3)
		ON CONFLICT (channel_id, user_id)
		DO UPDATE SET role = EXCLUDED.role
		RETURNING channel_id::text, user_id::text, role, joined_at
	`, channelID, userID, role).Scan(
		&membership.ChannelID,
		&membership.UserID,
		&membership.Role,
		&membership.JoinedAt,
	)
	if err != nil {
		return models.ChannelMembership{}, fmt.Errorf("upsert channel membership role: %w", err)
	}
	return membership, nil
}

func (r *ChannelRepository) DeleteMembership(ctx context.Context, channelID, userID string) error {
	_, err := r.pool.Exec(ctx, `
		DELETE FROM channel_members
		WHERE channel_id::text = $1 AND user_id::text = $2
	`, channelID, userID)
	if err != nil {
		return fmt.Errorf("delete channel membership: %w", err)
	}
	return nil
}

func (r *ChannelRepository) CountMembersByRole(ctx context.Context, channelID, role string) (int, error) {
	var count int
	if err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM channel_members
		WHERE channel_id::text = $1 AND role = $2
	`, channelID, role).Scan(&count); err != nil {
		return 0, fmt.Errorf("count channel members by role: %w", err)
	}
	return count, nil
}

func (r *ChannelRepository) TransferOwnership(ctx context.Context, channelID, newOwnerUserID string) (models.ChannelMembership, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return models.ChannelMembership{}, fmt.Errorf("begin transfer ownership tx: %w", err)
	}
	defer tx.Rollback(ctx)

	var previousOwnerUserID string
	if err := tx.QueryRow(ctx, `
		SELECT owner_user_id::text
		FROM channels
		WHERE id::text = $1
		FOR UPDATE
	`, channelID).Scan(&previousOwnerUserID); err != nil {
		return models.ChannelMembership{}, fmt.Errorf("load current owner: %w", err)
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO channel_members (channel_id, user_id, role)
		VALUES ($1::uuid, $2::uuid, 'owner')
		ON CONFLICT (channel_id, user_id)
		DO UPDATE SET role = 'owner'
	`, channelID, newOwnerUserID); err != nil {
		return models.ChannelMembership{}, fmt.Errorf("promote new owner: %w", err)
	}

	if previousOwnerUserID != newOwnerUserID {
		if _, err := tx.Exec(ctx, `
			UPDATE channel_members
			SET role = 'admin'
			WHERE channel_id::text = $1 AND user_id::text = $2
		`, channelID, previousOwnerUserID); err != nil {
			return models.ChannelMembership{}, fmt.Errorf("demote previous owner: %w", err)
		}
	}

	if _, err := tx.Exec(ctx, `
		UPDATE channels
		SET owner_user_id = $2::uuid
		WHERE id::text = $1
	`, channelID, newOwnerUserID); err != nil {
		return models.ChannelMembership{}, fmt.Errorf("update channel owner: %w", err)
	}

	var membership models.ChannelMembership
	if err := tx.QueryRow(ctx, `
		SELECT channel_id::text, user_id::text, role, joined_at
		FROM channel_members
		WHERE channel_id::text = $1 AND user_id::text = $2
	`, channelID, newOwnerUserID).Scan(
		&membership.ChannelID,
		&membership.UserID,
		&membership.Role,
		&membership.JoinedAt,
	); err != nil {
		return models.ChannelMembership{}, fmt.Errorf("load new owner membership: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return models.ChannelMembership{}, fmt.Errorf("commit transfer ownership: %w", err)
	}

	return membership, nil
}

func (r *ChannelRepository) SeedDemoChannel(ctx context.Context, userEmail string) error {
	const query = `
		WITH u AS (
			SELECT id FROM users WHERE email = $1
		), inserted_channel AS (
			INSERT INTO channels (name, type, owner_user_id)
			SELECT 'Alpha', 'private', u.id FROM u
			WHERE NOT EXISTS (SELECT 1 FROM channels WHERE name = 'Alpha')
			RETURNING id, owner_user_id
		), selected_channel AS (
			SELECT id, owner_user_id FROM inserted_channel
			UNION
			SELECT id, owner_user_id FROM channels WHERE name = 'Alpha'
		)
		INSERT INTO channel_members (channel_id, user_id, role)
		SELECT sc.id, sc.owner_user_id, 'owner' FROM selected_channel sc
		ON CONFLICT (channel_id, user_id) DO NOTHING
	`

	if _, err := r.pool.Exec(ctx, query, userEmail); err != nil {
		return fmt.Errorf("seed demo channel: %w", err)
	}
	return nil
}
