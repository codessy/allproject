package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"

	"walkietalkie/backend/internal/auth"
)

func TestAuthMiddlewareAllowsDemoUserWithoutHeader(t *testing.T) {
	gin.SetMode(gin.TestMode)

	service := auth.NewService("walkietalkie", "secret")
	router := gin.New()
	router.Use(AuthMiddleware(service))
	router.GET("/protected", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"userID": c.GetString("userID")})
	})

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if rec.Body.String() != "{\"userID\":\"demo-user\"}" {
		t.Fatalf("unexpected body: %s", rec.Body.String())
	}
}

func TestAuthMiddlewareRejectsInvalidToken(t *testing.T) {
	gin.SetMode(gin.TestMode)

	service := auth.NewService("walkietalkie", "secret")
	router := gin.New()
	router.Use(AuthMiddleware(service))
	router.GET("/protected", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer invalid-token")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestAuthMiddlewareAcceptsValidToken(t *testing.T) {
	gin.SetMode(gin.TestMode)

	service := auth.NewService("walkietalkie", "secret")
	token, err := service.IssueAccessToken("user-123", "user@example.com")
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}

	router := gin.New()
	router.Use(AuthMiddleware(service))
	router.GET("/protected", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"userID": c.GetString("userID")})
	})

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if rec.Body.String() != "{\"userID\":\"user-123\"}" {
		t.Fatalf("unexpected body: %s", rec.Body.String())
	}
}
