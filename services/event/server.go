package event

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/heena5498/eks-microservices/internal/auth"
	"github.com/heena5498/eks-microservices/internal/cache"
	"github.com/heena5498/eks-microservices/internal/config"
	"github.com/heena5498/eks-microservices/internal/database"
	"github.com/heena5498/eks-microservices/internal/logger"
	"github.com/heena5498/eks-microservices/internal/middleware"
	"github.com/heena5498/eks-microservices/internal/repository/events"
	"github.com/heena5498/eks-microservices/internal/utils"
)

func SetupRoutes(config *APIConfig) *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", utils.HandleHealthz)
	mux.HandleFunc("GET /health/ready", config.HandleReadiness)

	mux.HandleFunc("POST /api/v1/auth/admin/register", config.AdminRegister)
	mux.HandleFunc("POST /api/v1/auth/admin/login", config.AdminLogin)
	mux.HandleFunc("POST /api/v1/auth/admin/refresh", config.AdminRefreshToken)
	mux.HandleFunc("POST /api/v1/auth/admin/logout", config.AdminLogout)

	mux.HandleFunc("GET /api/v1/events", config.ListPublishedEvents)
	mux.HandleFunc("GET /api/v1/events/{id}", config.GetEventByID)
	mux.HandleFunc("GET /api/v1/events/{id}/availability", config.GetEventAvailability)

	var adminAuth func(http.HandlerFunc) http.HandlerFunc
	if config.RedisClient != nil {
		adminAuth = auth.RequireAdminAuthWithCache(config.Config.JWTSecret, config.RedisClient)
	} else {
		adminAuth = auth.RequireAdminAuth(config.Config.JWTSecret)
	}
	mux.HandleFunc("POST /api/v1/admin/events", adminAuth(config.CreateEvent))
	mux.HandleFunc("PUT /api/v1/admin/events/{id}", adminAuth(config.UpdateEvent))
	mux.HandleFunc("DELETE /api/v1/admin/events/{id}", adminAuth(config.DeleteEvent))
	mux.HandleFunc("GET /api/v1/admin/events", adminAuth(config.ListAdminEvents))
	mux.HandleFunc("GET /api/v1/admin/events/{id}/analytics", adminAuth(config.GetEventAnalytics))

	mux.HandleFunc("POST /api/v1/admin/venues", adminAuth(config.CreateVenue))
	mux.HandleFunc("GET /api/v1/admin/venues", adminAuth(config.ListVenues))
	mux.HandleFunc("PUT /api/v1/admin/venues/{id}", adminAuth(config.UpdateVenue))
	mux.HandleFunc("DELETE /api/v1/admin/venues/{id}", adminAuth(config.DeleteVenue))

	mux.HandleFunc("GET /api/v1/admin/analytics/overview", adminAuth(config.GetPlatformOverview))
	mux.HandleFunc("GET /api/v1/admin/analytics/top-events", adminAuth(config.GetTopEvents))

	internalAuth := auth.RequireInternalAuth(config.Config.InternalAPIKey)
	mux.HandleFunc("POST /internal/events/{id}/update-availability", internalAuth(config.UpdateEventAvailability))
	mux.HandleFunc("GET /internal/events/{id}", internalAuth(config.GetEventForBooking))
	mux.HandleFunc("POST /internal/events/{id}/return-seats", internalAuth(config.ReturnEventSeats))

	return mux
}

func StartServer(config *APIConfig) {
	mux := SetupRoutes(config)

	handler := middleware.CORS(mux)
	handler = middleware.LoggingMiddleware(config.Logger)(handler)

	server := &http.Server{
		Handler: handler,
		Addr:    ":" + config.Config.Port,
	}

	config.Logger.Info("Starting Event Service", "port", config.Config.Port)
	if err := server.ListenAndServe(); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

func InitEventService() (*APIConfig, *sql.DB) {
	cfg := config.LoadEventServiceConfig()
	logger := logger.New(cfg.LogLevel).WithService("event-service")

	db, err := database.NewPostgresConnection(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	dbQueries := events.New(db)

	var searchClient *SearchServiceClient
	fmt.Printf("DEBUG: SearchServiceURL from config: '%s'\n", cfg.SearchServiceURL)
	if cfg.SearchServiceURL != "" {
		searchClient = NewSearchServiceClient(cfg.SearchServiceURL, cfg.InternalAPIKey, logger)
		logger.Info("Search service client initialized", "search_service_url", cfg.SearchServiceURL)
		fmt.Printf("DEBUG: SearchServiceClient created successfully\n")
	} else {
		logger.Info("Search service URL not configured, search indexing disabled")
		fmt.Printf("DEBUG: SearchServiceURL is empty, no SearchClient created\n")
	}

	var redisClient *cache.RedisClient
	redisURL := os.Getenv("REDIS_URL")
	if redisURL != "" {
		redisClient, err = cache.NewRedisClient(redisURL)
		if err != nil {
			logger.Warn("Failed to connect to Redis, caching disabled", "error", err)
		} else {
			logger.Info("Redis client initialized successfully")
		}
	} else {
		logger.Info("Redis URL not configured, caching disabled")
	}

	apiConfig := &APIConfig{
		DB:           dbQueries,
		DB_Conn:      db,
		Config:       cfg,
		Logger:       logger,
		SearchClient: searchClient,
		RedisClient:  redisClient,
	}

	return apiConfig, db
}
