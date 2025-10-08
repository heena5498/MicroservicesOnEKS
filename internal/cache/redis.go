package cache

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

type RedisClient struct {
	client *redis.Client
}

func NewRedisClient(url string) (*RedisClient, error) {
	opts, err := redis.ParseURL(url)
	if err != nil {
		return nil, fmt.Errorf("failed to parse redis URL: %w", err)
	}

	client := redis.NewClient(opts)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := client.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to connect to redis: %w", err)
	}

	return &RedisClient{client: client}, nil
}

func (r *RedisClient) Close() error {
	return r.client.Close()
}

func (r *RedisClient) Set(ctx context.Context, key string, value interface{}, ttl time.Duration) error {
	return r.client.Set(ctx, key, value, ttl).Err()
}

func (r *RedisClient) Get(ctx context.Context, key string) (string, error) {
	return r.client.Get(ctx, key).Result()
}

func (r *RedisClient) Delete(ctx context.Context, key string) error {
	return r.client.Del(ctx, key).Err()
}

func (r *RedisClient) Exists(ctx context.Context, key string) (bool, error) {
	count, err := r.client.Exists(ctx, key).Result()
	return count > 0, err
}

func HashToken(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}

func (r *RedisClient) CacheJWT(ctx context.Context, token string, userID string, ttl time.Duration) error {
	key := fmt.Sprintf("jwt:%s", HashToken(token))
	return r.Set(ctx, key, userID, ttl)
}

func (r *RedisClient) GetCachedJWT(ctx context.Context, token string) (string, error) {
	key := fmt.Sprintf("jwt:%s", HashToken(token))
	return r.Get(ctx, key)
}

func (r *RedisClient) InvalidateJWT(ctx context.Context, token string) error {
	key := fmt.Sprintf("jwt:%s", HashToken(token))
	return r.Delete(ctx, key)
}

func (r *RedisClient) Increment(ctx context.Context, key string, ttl time.Duration) (int64, error) {
	pipe := r.client.Pipeline()
	incr := pipe.Incr(ctx, key)
	pipe.Expire(ctx, key, ttl)
	_, err := pipe.Exec(ctx)
	if err != nil {
		return 0, err
	}
	return incr.Val(), nil
}

func (r *RedisClient) RateLimit(ctx context.Context, identifier string, limit int64, window time.Duration) (bool, error) {
	key := fmt.Sprintf("rate:%s", identifier)
	count, err := r.Increment(ctx, key, window)
	if err != nil {
		return false, err
	}
	return count <= limit, nil
}
