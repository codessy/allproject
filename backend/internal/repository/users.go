package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"walkietalkie/backend/internal/models"
)

type UserRepository struct {
	pool *pgxpool.Pool
}

func NewUserRepository(pool *pgxpool.Pool) *UserRepository {
	return &UserRepository{pool: pool}
}

func (r *UserRepository) Create(ctx context.Context, email, displayName, passwordHash string) (models.User, error) {
	user := models.User{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO users (email, display_name, password_hash)
		VALUES ($1, $2, $3)
		RETURNING id::text, email, display_name, password_hash, created_at
	`, email, displayName, passwordHash).Scan(
		&user.ID,
		&user.Email,
		&user.DisplayName,
		&user.PasswordHash,
		&user.CreatedAt,
	)
	if err != nil {
		return models.User{}, fmt.Errorf("create user: %w", err)
	}
	return user, nil
}

func (r *UserRepository) GetByEmail(ctx context.Context, email string) (models.User, error) {
	user := models.User{}
	err := r.pool.QueryRow(ctx, `
		SELECT id::text, email, display_name, password_hash, created_at
		FROM users
		WHERE email = $1
	`, email).Scan(
		&user.ID,
		&user.Email,
		&user.DisplayName,
		&user.PasswordHash,
		&user.CreatedAt,
	)
	if err != nil {
		return models.User{}, err
	}
	return user, nil
}

func (r *UserRepository) GetByID(ctx context.Context, userID string) (models.User, error) {
	user := models.User{}
	err := r.pool.QueryRow(ctx, `
		SELECT id::text, email, display_name, password_hash, created_at
		FROM users
		WHERE id::text = $1
	`, userID).Scan(
		&user.ID,
		&user.Email,
		&user.DisplayName,
		&user.PasswordHash,
		&user.CreatedAt,
	)
	if err != nil {
		return models.User{}, err
	}
	return user, nil
}

func (r *UserRepository) SeedDemoUser(ctx context.Context) error {
	email := "demo@example.com"
	// bcrypt hash for the demo password "password"
	_, err := r.pool.Exec(ctx, `
		INSERT INTO users (email, display_name, password_hash)
		VALUES ($1, $2, $3)
		ON CONFLICT (email)
		DO UPDATE SET
			display_name = EXCLUDED.display_name,
			password_hash = EXCLUDED.password_hash
	`, email, "Demo User", "$2a$10$PES9W6xtBu/pMAwLCZUhSuZGXM4cUmUquJi9J3l9D.aAOznRm4B5W")
	return err
}
