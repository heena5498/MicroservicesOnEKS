package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/heena5498/eks-microservices/services/user"
	"github.com/joho/godotenv"
)

func main() {
	loadEnv()
	validateUserEnv()

	appConfig, db := user.InitUserService()
	defer db.Close()

	user.StartServer(appConfig)
}

func loadEnv() {
	wd, _ := os.Getwd()
	for {
		envPath := filepath.Join(wd, ".env")
		if _, err := os.Stat(envPath); err == nil {
			if err := godotenv.Load(envPath); err != nil {
				log.Fatalf("Error loading .env: %v", err)
			}
			return
		}
		parent := filepath.Dir(wd)
		if parent == wd {
			log.Println(".env file not found - using environment variables")
			return
		}
		wd = parent
	}
}

func validateUserEnv() {
	required := []string{
		"USER_SERVICE_PORT",
		"USER_SERVICE_DB_URL",
		"JWT_SECRET",
		"INTERNAL_API_KEY",
	}

	var missing []string
	for _, env := range required {
		if os.Getenv(env) == "" {
			missing = append(missing, env)
		}

	}

	if len(missing) > 0 {
		log.Fatalf("Missing env vars: %v", missing)
	}

	fmt.Println("Environment loaded")
}
