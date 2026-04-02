package main

import (
	"context"
	"log"

	"walkietalkie/backend/internal/app"
	"walkietalkie/backend/internal/config"
)

func main() {
	cfg := config.Load()
	application, err := app.New(context.Background(), cfg)
	if err != nil {
		log.Fatal(err)
	}
	router := application.Router()

	log.Printf("api listening on :%s", cfg.Port)
	if err := router.Run(":" + cfg.Port); err != nil {
		log.Fatal(err)
	}
}
