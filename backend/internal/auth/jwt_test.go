package auth

import "testing"

func TestPasswordHashAndVerify(t *testing.T) {
	service := NewService("walkietalkie", "secret")

	hash, err := service.HashPassword("password")
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}

	if !service.VerifyPassword("password", hash) {
		t.Fatal("expected password verification to succeed")
	}

	if service.VerifyPassword("wrong", hash) {
		t.Fatal("expected password verification to fail for wrong password")
	}
}

func TestIssueAndParseAccessToken(t *testing.T) {
	service := NewService("walkietalkie", "secret")

	token, err := service.IssueAccessToken("user-1", "user@example.com")
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}

	claims, err := service.ParseAccessToken(token)
	if err != nil {
		t.Fatalf("parse access token: %v", err)
	}

	if claims.UserID != "user-1" {
		t.Fatalf("expected user id user-1, got %s", claims.UserID)
	}
	if claims.Email != "user@example.com" {
		t.Fatalf("expected email user@example.com, got %s", claims.Email)
	}
}
