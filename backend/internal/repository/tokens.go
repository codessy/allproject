package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type RefreshTokenRepository struct {
	pool *pgxpool.Pool
}

type RefreshTokenRecord struct {
	UserID    string
	TokenHash string
	ExpiresAt time.Time
}

func NewRefreshTokenRepository(pool *pgxpool.Pool) *RefreshTokenRepository {
	return &RefreshTokenRepository{pool: pool}
}

func (r *RefreshTokenRepository) Create(ctx context.Context, userID, tokenHash string, expiresAt time.Time) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
		VALUES ($1::uuid, $2, $3)
	`, userID, tokenHash, expiresAt)
	if err != nil {
		return fmt.Errorf("create refresh token: %w", err)
	}
	return nil
}

func (r *RefreshTokenRepository) GetByHash(ctx context.Context, tokenHash string) (RefreshTokenRecord, error) {
	var item RefreshTokenRecord
	err := r.pool.QueryRow(ctx, `
		SELECT user_id::text, token_hash, expires_at
		FROM refresh_tokens
		WHERE token_hash = $1
	`, tokenHash).Scan(&item.UserID, &item.TokenHash, &item.ExpiresAt)
	if err != nil {
		return RefreshTokenRecord{}, err
	}
	return item, nil
}

func (r *RefreshTokenRepository) DeleteByHash(ctx context.Context, tokenHash string) error {
	_, err := r.pool.Exec(ctx, `
		DELETE FROM refresh_tokens
		WHERE token_hash = $1
	`, tokenHash)
	if err != nil {
		return fmt.Errorf("delete refresh token by hash: %w", err)
	}
	return nil
}

func (r *RefreshTokenRepository) DeleteByUserID(ctx context.Context, userID string) error {
	_, err := r.pool.Exec(ctx, `
		DELETE FROM refresh_tokens
		WHERE user_id::text = $1
	`, userID)
	if err != nil {
		return fmt.Errorf("delete refresh tokens by user id: %w", err)
	}
	return nil
}
