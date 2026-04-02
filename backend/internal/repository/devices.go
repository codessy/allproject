package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"walkietalkie/backend/internal/models"
)

type DeviceRepository struct {
	pool *pgxpool.Pool
}

func NewDeviceRepository(pool *pgxpool.Pool) *DeviceRepository {
	return &DeviceRepository{pool: pool}
}

func (r *DeviceRepository) Upsert(ctx context.Context, userID, platform, pushToken, appVersion string) (models.Device, error) {
	device := models.Device{}
	err := r.pool.QueryRow(ctx, `
		WITH existing AS (
			SELECT id
			FROM devices
			WHERE user_id::text = $1 AND push_token = $2
			LIMIT 1
		), updated AS (
			UPDATE devices
			SET platform = $3,
			    app_version = $4,
			    last_seen_at = NOW()
			WHERE id IN (SELECT id FROM existing)
			RETURNING id::text, user_id::text, platform, push_token, app_version, last_seen_at
		), inserted AS (
			INSERT INTO devices (user_id, platform, push_token, app_version)
			SELECT $1::uuid, $3, $2, $4
			WHERE NOT EXISTS (SELECT 1 FROM existing)
			RETURNING id::text, user_id::text, platform, push_token, app_version, last_seen_at
		)
		SELECT * FROM updated
		UNION ALL
		SELECT * FROM inserted
	`, userID, pushToken, platform, appVersion).Scan(
		&device.ID,
		&device.UserID,
		&device.Platform,
		&device.PushToken,
		&device.AppVersion,
		&device.LastSeenAt,
	)
	if err != nil {
		return models.Device{}, fmt.Errorf("upsert device: %w", err)
	}
	return device, nil
}

func (r *DeviceRepository) ListByUserID(ctx context.Context, userID string) ([]models.Device, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id::text, user_id::text, platform, push_token, app_version, last_seen_at
		FROM devices
		WHERE user_id::text = $1
		ORDER BY last_seen_at DESC
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("list devices by user id: %w", err)
	}
	defer rows.Close()

	devices := make([]models.Device, 0)
	for rows.Next() {
		var device models.Device
		if err := rows.Scan(
			&device.ID,
			&device.UserID,
			&device.Platform,
			&device.PushToken,
			&device.AppVersion,
			&device.LastSeenAt,
		); err != nil {
			return nil, fmt.Errorf("scan device: %w", err)
		}
		devices = append(devices, device)
	}

	return devices, rows.Err()
}
