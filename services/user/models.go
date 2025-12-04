package user

import (
	"database/sql"
	"time"

	"github.com/heena5498/eks-microservices/internal/cache"
	"github.com/heena5498/eks-microservices/internal/config"
	"github.com/heena5498/eks-microservices/internal/logger"
	"github.com/heena5498/eks-microservices/internal/repository/users"
	"github.com/google/uuid"
)

type APIConfig struct {
	DB          users.Querier
	DB_Conn     *sql.DB
	Config      *config.UserServiceConfig
	Logger      *logger.Logger
	RedisClient *cache.RedisClient
}

type CreateUserRequest struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	Name        string `json:"name"`
	PhoneNumber string `json:"phone_number,omitempty"`
}

type UserLoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type UpdateUserRequest struct {
	Name        *string `json:"name,omitempty"`
	PhoneNumber *string `json:"phone_number,omitempty"`
}

type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type LogoutRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type UserResponse struct {
	UserID      uuid.UUID `json:"user_id"`
	Email       string    `json:"email"`
	Name        string    `json:"name"`
	PhoneNumber *string   `json:"phone_number,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
}

type AuthResponse struct {
	UserID       uuid.UUID `json:"user_id"`
	Email        string    `json:"email"`
	Name         string    `json:"name"`
	AccessToken  string    `json:"access_token"`
	RefreshToken string    `json:"refresh_token"`
}

type RefreshTokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}

type LogoutResponse struct {
	Message string `json:"message"`
}

type TokenVerificationResponse struct {
	UserID uuid.UUID `json:"user_id"`
	Email  string    `json:"email"`
	Valid  bool      `json:"valid"`
}

type VerifyTokenRequest struct {
	Token string `json:"token"`
}
