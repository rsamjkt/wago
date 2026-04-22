package middleware

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/aldinokemal/go-whatsapp-web-multidevice/config"
	"github.com/gofiber/fiber/v2"
)

type sessionEntry struct {
	username  string
	expiresAt time.Time
}

var (
	sessionStore   = make(map[string]*sessionEntry)
	sessionStoreMu sync.RWMutex
)

func newToken() string {
	b := make([]byte, 20)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// CreateSession stores a new session and returns the bearer token.
func CreateSession(username string) string {
	token := newToken()
	sessionStoreMu.Lock()
	sessionStore[token] = &sessionEntry{
		username:  username,
		expiresAt: time.Now().Add(24 * time.Hour),
	}
	sessionStoreMu.Unlock()
	return token
}

// ValidateSession returns true if the token is valid and not expired.
func ValidateSession(token string) bool {
	sessionStoreMu.RLock()
	entry, ok := sessionStore[token]
	sessionStoreMu.RUnlock()
	if !ok {
		return false
	}
	if time.Now().After(entry.expiresAt) {
		sessionStoreMu.Lock()
		delete(sessionStore, token)
		sessionStoreMu.Unlock()
		return false
	}
	return true
}

// DeleteSession removes a session token.
func DeleteSession(token string) {
	sessionStoreMu.Lock()
	delete(sessionStore, token)
	sessionStoreMu.Unlock()
}

// SessionAuth validates Bearer tokens for protected routes.
// If no credentials are configured, all requests pass through.
func SessionAuth() fiber.Handler {
	return func(c *fiber.Ctx) error {
		if len(config.AppBasicAuthCredential) == 0 {
			return c.Next()
		}
		auth := c.Get("Authorization")
		if strings.HasPrefix(auth, "Bearer ") {
			if ValidateSession(strings.TrimPrefix(auth, "Bearer ")) {
				return c.Next()
			}
		}
		return c.Status(http.StatusUnauthorized).JSON(fiber.Map{
			"status":  401,
			"code":    "UNAUTHORIZED",
			"message": "Authentication required. Please sign in.",
		})
	}
}
