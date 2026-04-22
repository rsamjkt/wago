package rest

import (
	"net/http"
	"strings"

	"github.com/aldinokemal/go-whatsapp-web-multidevice/config"
	"github.com/aldinokemal/go-whatsapp-web-multidevice/ui/rest/middleware"
	"github.com/gofiber/fiber/v2"
)

type authLoginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// HandleAuthLogin validates credentials and issues a session token.
func HandleAuthLogin(c *fiber.Ctx) error {
	var req authLoginRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{
			"status":  400,
			"message": "Invalid request body",
		})
	}

	for _, cred := range config.AppBasicAuthCredential {
		parts := strings.SplitN(cred, ":", 2)
		if len(parts) == 2 && parts[0] == req.Username && parts[1] == req.Password {
			token := middleware.CreateSession(req.Username)
			return c.JSON(fiber.Map{
				"status":  200,
				"message": "Login successful",
				"results": fiber.Map{"token": token},
			})
		}
	}

	return c.Status(http.StatusUnauthorized).JSON(fiber.Map{
		"status":  401,
		"message": "Invalid username or password",
	})
}

// HandleAuthLogout invalidates the session token.
func HandleAuthLogout(c *fiber.Ctx) error {
	auth := c.Get("Authorization")
	if strings.HasPrefix(auth, "Bearer ") {
		middleware.DeleteSession(strings.TrimPrefix(auth, "Bearer "))
	}
	return c.JSON(fiber.Map{"status": 200, "message": "Logged out successfully"})
}

// HandleAuthVerify checks whether the current session token is valid.
func HandleAuthVerify(c *fiber.Ctx) error {
	if len(config.AppBasicAuthCredential) == 0 {
		return c.JSON(fiber.Map{
			"status":  200,
			"message": "OK",
			"results": fiber.Map{"auth_enabled": false},
		})
	}
	auth := c.Get("Authorization")
	if strings.HasPrefix(auth, "Bearer ") {
		if middleware.ValidateSession(strings.TrimPrefix(auth, "Bearer ")) {
			return c.JSON(fiber.Map{
				"status":  200,
				"message": "OK",
				"results": fiber.Map{"auth_enabled": true},
			})
		}
	}
	return c.Status(http.StatusUnauthorized).JSON(fiber.Map{
		"status":  401,
		"message": "Invalid or expired session",
		"results": fiber.Map{"auth_enabled": true},
	})
}
