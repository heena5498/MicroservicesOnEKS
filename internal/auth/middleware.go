package auth

import (
	"context"
	"net/http"
	"time"

	"github.com/heena5498/eks-microservices/internal/cache"
	"github.com/heena5498/eks-microservices/internal/utils"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

type UserContextKey string

type AdminContextKey string

const (
	UserIDKey  UserContextKey  = "user_id"
	AdminIDKey AdminContextKey = "admin_id"
)

func RequireAuth(jwtSecret string) func(http.HandlerFunc) http.HandlerFunc {
	return func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			token, err := GetBearerToken(r.Header)
			if err != nil {
				utils.RespondWithError(w, http.StatusUnauthorized, "Missing or invalid authorization header")
				return
			}

			userID, err := ValidateJWT(token, jwtSecret)
			if err != nil {
				utils.RespondWithError(w, http.StatusUnauthorized, "Invalid token")
				return
			}

			ctx := context.WithValue(r.Context(), UserIDKey, userID)
			r = r.WithContext(ctx)

			next(w, r)
		}
	}
}

func RequireInternalAuth(apiKey string) func(http.HandlerFunc) http.HandlerFunc {
	return func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			receivedKey, err := GetAPIKey(r.Header)
			if err != nil {
				utils.RespondWithError(w, http.StatusUnauthorized, "Missing or invalid API key")
				return
			}

			if receivedKey != apiKey {
				utils.RespondWithError(w, http.StatusForbidden, "Invalid API key")
				return
			}

			next(w, r)
		}
	}
}

func GetUserIDFromContext(ctx context.Context) (uuid.UUID, bool) {
	userID, ok := ctx.Value(UserIDKey).(uuid.UUID)
	return userID, ok
}

func RequireAdminAuth(jwtSecret string) func(http.HandlerFunc) http.HandlerFunc {
	return func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			token, err := GetBearerToken(r.Header)
			if err != nil {
				utils.RespondWithError(w, http.StatusUnauthorized, "Missing or invalid authorization header")
				return
			}

			claims, err := ValidateAdminJWT(token, jwtSecret)
			if err != nil {
				utils.RespondWithError(w, http.StatusUnauthorized, "Invalid admin token")
				return
			}

			ctx := context.WithValue(r.Context(), AdminIDKey, claims.AdminID)
			r = r.WithContext(ctx)

			next(w, r)
		}
	}
}

func GetAdminIDFromContext(ctx context.Context) (uuid.UUID, bool) {
	adminID, ok := ctx.Value(AdminIDKey).(uuid.UUID)
	return adminID, ok
}

func RequireAuthWithCache(jwtSecret string, redisClient *cache.RedisClient) func(http.HandlerFunc) http.HandlerFunc {
	return func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			token, err := GetBearerToken(r.Header)
			if err != nil {
				utils.RespondWithError(w, http.StatusUnauthorized, "Missing or invalid authorization header")
				return
			}

			var userID uuid.UUID

			if redisClient != nil {
				cachedUserID, err := redisClient.GetCachedJWT(r.Context(), token)
				if err == nil {
					userID, err = uuid.Parse(cachedUserID)
					if err == nil {
						ctx := context.WithValue(r.Context(), UserIDKey, userID)
						r = r.WithContext(ctx)
						next(w, r)
						return
					}
				} else if err != redis.Nil {
					utils.RespondWithError(w, http.StatusInternalServerError, "Cache error")
					return
				}
			}

			userID, err = ValidateJWT(token, jwtSecret)
			if err != nil {
				utils.RespondWithError(w, http.StatusUnauthorized, "Invalid token")
				return
			}

			if redisClient != nil {
				go redisClient.CacheJWT(context.Background(), token, userID.String(), 15*time.Minute)
			}

			ctx := context.WithValue(r.Context(), UserIDKey, userID)
			r = r.WithContext(ctx)

			next(w, r)
		}
	}
}

func RequireAdminAuthWithCache(jwtSecret string, redisClient *cache.RedisClient) func(http.HandlerFunc) http.HandlerFunc {
	return func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			token, err := GetBearerToken(r.Header)
			if err != nil {
				utils.RespondWithError(w, http.StatusUnauthorized, "Missing or invalid authorization header")
				return
			}

			var adminID uuid.UUID

			if redisClient != nil {
				cachedAdminID, err := redisClient.GetCachedJWT(r.Context(), token)
				if err == nil {
					adminID, err = uuid.Parse(cachedAdminID)
					if err == nil {
						ctx := context.WithValue(r.Context(), AdminIDKey, adminID)
						r = r.WithContext(ctx)
						next(w, r)
						return
					}
				} else if err != redis.Nil {
					utils.RespondWithError(w, http.StatusInternalServerError, "Cache error")
					return
				}
			}

			claims, err := ValidateAdminJWT(token, jwtSecret)
			if err != nil {
				utils.RespondWithError(w, http.StatusUnauthorized, "Invalid admin token")
				return
			}

			if redisClient != nil {
				go redisClient.CacheJWT(context.Background(), token, claims.AdminID.String(), 15*time.Minute)
			}

			ctx := context.WithValue(r.Context(), AdminIDKey, claims.AdminID)
			r = r.WithContext(ctx)

			next(w, r)
		}
	}
}
