package config

import (
	"fmt"
	"log/slog"
	"os"
	"strconv"
	"time"
)

type Config struct {
	Port               string
	DBConnStr          string
	RabbitMQConnStr    string
	ExchangeName       string
	OutboxPollInterval time.Duration
}

func LoadConfig() (*Config, error) {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	dbConnStr := os.Getenv("DB_CONNECTION_STRING")
	if dbConnStr == "" {
		return nil, fmt.Errorf("DB_CONNECTION_STRING environment variable is required")
	}

	rabbitMQConnStr := os.Getenv("RABBITMQ_CONNECTION_STRING")
	if rabbitMQConnStr == "" {
		return nil, fmt.Errorf("RABBITMQ_CONNECTION_STRING environment variable is required")
	}

	exchangeName := os.Getenv("RABBITMQ_EXCHANGE_NAME")
	if exchangeName == "" {
		exchangeName = "order_events"
	}

	outboxPollIntervalSec := 5
	if val := os.Getenv("OUTBOX_POLL_INTERVAL_SECONDS"); val != "" {
		if parsed, err := strconv.Atoi(val); err == nil {
			outboxPollIntervalSec = parsed
		} else {
			slog.Warn("Invalid OUTBOX_POLL_INTERVAL_SECONDS, using default", "value", val, "default", 5)
		}
	}

	return &Config{
		Port:               port,
		DBConnStr:          dbConnStr,
		RabbitMQConnStr:    rabbitMQConnStr,
		ExchangeName:       exchangeName,
		OutboxPollInterval: time.Duration(outboxPollIntervalSec) * time.Second,
	}, nil
}