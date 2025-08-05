package config

import (
	"log"
	"os"
	"strconv"
	"time"
)

type Config struct {
	Port               string
	DBConnStr          string
	RabbitMQConnStr    string
	OutboxPollInterval time.Duration
}

func LoadConfig() *Config {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	dbConnStr := os.Getenv("DB_CONNECTION_STRING")
	if dbConnStr == "" {
		dbConnStr = "postgresql://user:password@order_db:5432/order_db?sslmode=disable"
		log.Printf("DB_CONNECTION_STRING not set, using default: %s", dbConnStr)
	}

	rabbitMQConnStr := os.Getenv("RABBITMQ_CONNECTION_STRING")
	if rabbitMQConnStr == "" {
		rabbitMQConnStr = "amqp://guest:guest@rabbitmq:5672/"
		log.Printf("RABBITMQ_CONNECTION_STRING not set, using default: %s", rabbitMQConnStr)
	}

	outboxPollIntervalStr := os.Getenv("OUTBOX_POLL_INTERVAL_SECONDS")
	outboxPollIntervalSec := 5
	if outboxPollIntervalStr != "" {
		if val, err := strconv.Atoi(outboxPollIntervalStr); err == nil {
			outboxPollIntervalSec = val
		}
	}
	outboxPollInterval := time.Duration(outboxPollIntervalSec) * time.Second

	return &Config{
		Port:               port,
		DBConnStr:          dbConnStr,
		RabbitMQConnStr:    rabbitMQConnStr,
		OutboxPollInterval: outboxPollInterval,
	}
}