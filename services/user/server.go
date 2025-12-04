package user

import (
	"database/sql"
	"log"
	"net/http"
	"os"

	"github.com/heena5498/eks-microservices/internal/auth"
	"github.com/heena5498/eks-microservices/internal/cache"
	"github.com/heena5498/eks-microservices/internal/config"
	"github.com/heena5498/eks-microservices/internal/database"
	"github.com/heena5498/eks-microservices/internal/logger"
	"github.com/heena5498/eks-microservices/internal/middleware"
	"github.com/heena5498/eks-microservices/internal/repository/users"
)

func SetupRoutes(config *APIConfig) *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", HandleHealthz)
	mux.HandleFunc("GET /health/ready", config.HandleReadiness)

	mux.HandleFunc("POST /api/v1/auth/register", config.AddUser)
	mux.HandleFunc("POST /api/v1/auth/login", config.LoginUser)
	mux.HandleFunc("POST /api/v1/auth/refresh", config.RefreshToken)
	mux.HandleFunc("POST /api/v1/auth/logout", config.RevokeToken)

	var authMiddleware func(http.HandlerFunc) http.HandlerFunc
	if config.RedisClient != nil {
		authMiddleware = auth.RequireAuthWithCache(config.Config.JWTSecret, config.RedisClient)
	} else {
		authMiddleware = auth.RequireAuth(config.Config.JWTSecret)
	}
	mux.HandleFunc("GET /api/v1/users/profile", authMiddleware(config.GetProfile))
	mux.HandleFunc("PUT /api/v1/users/profile", authMiddleware(config.UpdateProfile))
	mux.HandleFunc("GET /api/v1/users/bookings", authMiddleware(config.GetUserBookings))

	internalAuth := auth.RequireInternalAuth(config.Config.InternalAPIKey)
	mux.HandleFunc("POST /internal/auth/verify", internalAuth(config.HandleInternalVerify))
	mux.HandleFunc("GET /internal/users/{userId}", internalAuth(config.HandleInternalGetUser))

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

	config.Logger.Info("Starting User Service", "port", config.Config.Port)
	if err := server.ListenAndServe(); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

func InitUserService() (*APIConfig, *sql.DB) {
	cfg := config.LoadUserServiceConfig()
	logger := logger.New(cfg.LogLevel).WithService("user-service")

	db, err := database.NewPostgresConnection(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	dbQueries := users.New()

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
		DB:          dbQueries,
		DB_Conn:     db,
		Config:      cfg,
		Logger:      logger,
		RedisClient: redisClient,
	}

	return apiConfig, db
}
