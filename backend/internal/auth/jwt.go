package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

type Claims struct {
	UserID string
	Email  string
}

type tokenClaims struct {
	Email string `json:"email"`
	jwt.RegisteredClaims
}

type Service struct {
	issuer string
	secret []byte
}

func NewService(issuer, secret string) *Service {
	return &Service{
		issuer: issuer,
		secret: []byte(secret),
	}
}

func (s *Service) HashPassword(raw string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(raw), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

func (s *Service) VerifyPassword(raw, encoded string) bool {
	return bcrypt.CompareHashAndPassword([]byte(encoded), []byte(raw)) == nil
}

func (s *Service) IssueAccessToken(userID, email string) (string, error) {
	claims := tokenClaims{
		Email: email,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			Issuer:    s.issuer,
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(15 * time.Minute)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(s.secret)
}

func (s *Service) NewRefreshToken() (raw string, hash string, expiresAt time.Time, err error) {
	buf := make([]byte, 32)
	if _, err = rand.Read(buf); err != nil {
		return "", "", time.Time{}, err
	}

	raw = hex.EncodeToString(buf)
	sum := sha256.Sum256([]byte(raw))
	hash = hex.EncodeToString(sum[:])
	expiresAt = time.Now().Add(30 * 24 * time.Hour)
	return raw, hash, expiresAt, nil
}

func (s *Service) HashOpaqueToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

func (s *Service) NewOpaqueToken() (raw string, hash string, err error) {
	buf := make([]byte, 24)
	if _, err = rand.Read(buf); err != nil {
		return "", "", err
	}
	raw = hex.EncodeToString(buf)
	hash = s.HashOpaqueToken(raw)
	return raw, hash, nil
}

func (s *Service) ParseAccessToken(token string) (Claims, error) {
	if token == "" {
		return Claims{}, errors.New("missing token")
	}

	parsed, err := jwt.ParseWithClaims(token, &tokenClaims{}, func(t *jwt.Token) (any, error) {
		return s.secret, nil
	}, jwt.WithIssuer(s.issuer))
	if err != nil {
		return Claims{}, err
	}

	claims, ok := parsed.Claims.(*tokenClaims)
	if !ok || !parsed.Valid {
		return Claims{}, errors.New("invalid token")
	}

	return Claims{
		UserID: claims.Subject,
		Email:  claims.Email,
	}, nil
}
