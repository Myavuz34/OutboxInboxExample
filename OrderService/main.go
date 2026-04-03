package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"order_service/config"
	"order_service/internal/api"
	"order_service/internal/application"
	"order_service/internal/infrastructure/postgres"
	"order_service/internal/infrastructure/rabbitmq"

	_ "github.com/lib/pq"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelDebug})))

	cfg, err := config.LoadConfig()
	if err != nil {
		slog.Error("Failed to load configuration", "error", err)
		os.Exit(1)
	}

	db, err := postgres.NewPostgresDB(cfg.DBConnStr)
	if err != nil {
		slog.Error("Failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer db.Close()
	slog.Info("Connected to PostgreSQL")

	amqpChannel, err := rabbitmq.NewRabbitMQChannel(cfg.RabbitMQConnStr, cfg.ExchangeName)
	if err != nil {
		slog.Error("Failed to connect to RabbitMQ", "error", err)
		os.Exit(1)
	}
	defer amqpChannel.Close()
	slog.Info("Connected to RabbitMQ", "exchange", cfg.ExchangeName)

	orderRepo := postgres.NewOrderRepository(db)
	outboxRepo := postgres.NewOutboxRepository(db)
	eventPublisher := rabbitmq.NewEventPublisher(amqpChannel, cfg.ExchangeName)

	orderAppService := application.NewOrderService(orderRepo, outboxRepo)
	outboxRelayer := application.NewOutboxRelayer(outboxRepo, eventPublisher, cfg.OutboxPollInterval)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go outboxRelayer.Start(ctx)

	orderHandler := api.NewOrderHandler(orderAppService)
	mux := http.NewServeMux()
	mux.HandleFunc("/orders", orderHandler.CreateOrder)
	mux.HandleFunc("/health", api.NewHealthHandler(db, amqpChannel))

	srv := &http.Server{Addr: ":" + cfg.Port, Handler: mux}

	go func() {
		slog.Info("OrderService listening", "port", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("HTTP server error", "error", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	slog.Info("Shutting down OrderService...")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		slog.Error("HTTP server shutdown error", "error", err)
	}

	slog.Info("OrderService stopped")
}