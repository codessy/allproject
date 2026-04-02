package httpapi

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"walkietalkie/backend/internal/auth"
)

func AuthMiddleware(authService *auth.Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if header == "" {
			c.Set("userID", "demo-user")
			c.Next()
			return
		}

		token := strings.TrimPrefix(header, "Bearer ")
		claims, err := authService.ParseAccessToken(token)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
			return
		}

		c.Set("userID", claims.UserID)
		c.Next()
	}
}
