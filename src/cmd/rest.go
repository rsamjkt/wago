package cmd

import (
	"net/http"

	"github.com/aldinokemal/go-whatsapp-web-multidevice/config"
	"github.com/aldinokemal/go-whatsapp-web-multidevice/infrastructure/whatsapp"
	"github.com/aldinokemal/go-whatsapp-web-multidevice/ui/rest"
	"github.com/aldinokemal/go-whatsapp-web-multidevice/ui/rest/helpers"
	"github.com/aldinokemal/go-whatsapp-web-multidevice/ui/rest/middleware"
	"github.com/aldinokemal/go-whatsapp-web-multidevice/ui/websocket"
	"github.com/dustin/go-humanize"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/filesystem"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/template/html/v2"
	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

var restCmd = &cobra.Command{
	Use:   "rest",
	Short: "Send whatsapp API over http",
	Long:  `This application is from clone https://github.com/aldinokemal/go-whatsapp-web-multidevice`,
	Run:   restServer,
}

func init() {
	rootCmd.AddCommand(restCmd)
}

func restServer(_ *cobra.Command, _ []string) {
	engine := html.NewFileSystem(http.FS(EmbedIndex), ".html")
	engine.AddFunc("isEnableBasicAuth", func(token any) bool {
		return token != nil
	})

	fiberConfig := fiber.Config{
		Views:                   engine,
		EnableTrustedProxyCheck: true,
		BodyLimit:               int(config.WhatsappSettingMaxVideoSize),
		Network:                 "tcp",
	}

	if len(config.AppTrustedProxies) > 0 {
		fiberConfig.TrustedProxies = config.AppTrustedProxies
		fiberConfig.ProxyHeader = fiber.HeaderXForwardedHost
	}

	app := fiber.New(fiberConfig)

	app.Static(config.AppBasePath+"/statics", "./statics")
	app.Use(config.AppBasePath+"/components", filesystem.New(filesystem.Config{
		Root:       http.FS(EmbedViews),
		PathPrefix: "views/components",
		Browse:     true,
	}))
	app.Use(config.AppBasePath+"/assets", filesystem.New(filesystem.Config{
		Root:       http.FS(EmbedViews),
		PathPrefix: "views/assets",
		Browse:     true,
	}))

	app.Use(middleware.Recovery())
	app.Use(middleware.RequestTimeout(middleware.DefaultRequestTimeout))
	app.Use(middleware.BasicAuth())
	if config.AppDebug {
		app.Use(logger.New())
	}
	app.Use(cors.New(cors.Config{
		AllowOrigins: "*",
		AllowHeaders: "Origin, Content-Type, Accept, Authorization, X-Device-Id",
	}))

	dm := whatsapp.GetDeviceManager()
	authEnabled := len(config.AppBasicAuthCredential) > 0

	// Health check — always public (no base path prefix for infra probes)
	app.Get("/health", func(c *fiber.Ctx) error {
		if dm != nil && dm.IsHealthy() {
			return c.SendString("OK")
		}
		return c.Status(http.StatusServiceUnavailable).SendString("Service Unavailable")
	})

	// Chatwoot webhook — public, registered before auth middleware
	if config.ChatwootEnabled {
		chatwootHandler := rest.NewChatwootHandler(appUsecase, sendUsecase, dm, chatStorageRepo)
		webhookPath := "/chatwoot/webhook"
		if config.AppBasePath != "" {
			webhookPath = config.AppBasePath + webhookPath
		}
		app.Post(webhookPath, chatwootHandler.HandleWebhook)
	}

	var apiGroup fiber.Router = app
	if config.AppBasePath != "" {
		apiGroup = app.Group(config.AppBasePath)
	}

	// ── Public routes (no auth required) ───────────────────────────────

	// Dashboard page — client-side JS handles auth redirect
	apiGroup.Get("/", func(c *fiber.Ctx) error {
		return c.Render("views/index", fiber.Map{
			"AppVersion":     config.AppVersion,
			"AppBasePath":    config.AppBasePath,
			"AuthEnabled":    authEnabled,
			"BasicAuthToken": c.UserContext().Value(middleware.AuthorizationValue("BASIC_AUTH")),
			"MaxFileSize":    humanize.Bytes(uint64(config.WhatsappSettingMaxFileSize)),
			"MaxVideoSize":   humanize.Bytes(uint64(config.WhatsappSettingMaxVideoSize)),
		})
	})

	// Login page — redirect to dashboard when auth is not configured
	apiGroup.Get("/login", func(c *fiber.Ctx) error {
		if !authEnabled {
			return c.Redirect(config.AppBasePath + "/")
		}
		return c.Render("views/login", fiber.Map{
			"AppBasePath": config.AppBasePath,
			"AppVersion":  config.AppVersion,
		})
	})

	// Auth API endpoints — always public
	apiGroup.Post("/auth/login", rest.HandleAuthLogin)
	apiGroup.Post("/auth/logout", rest.HandleAuthLogout)
	apiGroup.Get("/auth/verify", rest.HandleAuthVerify)

	// ── Protected routes (session token required when auth is enabled) ──
	apiGroup.Use(middleware.SessionAuth())

	// Device management (no device_id header required)
	rest.InitRestDevice(apiGroup, deviceUsecase)

	// Device-scoped operations (require X-Device-Id header)
	headerDeviceGroup := apiGroup.Group("", middleware.DeviceMiddleware(dm))
	rest.InitRestApp(headerDeviceGroup, appUsecase)
	rest.InitRestChat(headerDeviceGroup, chatUsecase)
	rest.InitRestSend(headerDeviceGroup, sendUsecase)
	rest.InitRestUser(headerDeviceGroup, userUsecase)
	rest.InitRestMessage(headerDeviceGroup, messageUsecase)
	rest.InitRestGroup(headerDeviceGroup, groupUsecase)
	rest.InitRestNewsletter(headerDeviceGroup, newsletterUsecase)
	websocket.RegisterRoutes(headerDeviceGroup, appUsecase)

	// Chatwoot sync routes — authenticated
	if config.ChatwootEnabled {
		chatwootHandler := rest.NewChatwootHandler(appUsecase, sendUsecase, dm, chatStorageRepo)
		apiGroup.Post("/chatwoot/sync", chatwootHandler.SyncHistory)
		apiGroup.Get("/chatwoot/sync/status", chatwootHandler.SyncStatus)
	}

	go websocket.RunHub()
	go helpers.SetAutoConnectAfterBooting(appUsecase)
	startAutoReconnectCheckerIfClientAvailable()

	if err := app.Listen(config.AppHost + ":" + config.AppPort); err != nil {
		logrus.Fatalln("Failed to start: ", err.Error())
	}
}
