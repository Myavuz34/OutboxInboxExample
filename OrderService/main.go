package main

import (
	"context"
	"log"
	"net/http"

	"order_service/config"
	"order_service/internal/api"
	"order_service/internal/application"
	"order_service/internal/infrastructure/postgres"
	"order_service/internal/infrastructure/rabbitmq"

	_ "github.com/lib/pq" // PostgreSQL sürücüsü
)

func main() {
	cfg := config.LoadConfig()

	// Connect to PostgreSQL
	db, err := postgres.NewPostgresDB(cfg.DBConnStr)
	if err != nil {
		log.Fatalf("Error connecting to database: %v", err)
	}
	defer db.Close()
	log.Println("Connected to PostgreSQL (OrderService)")

	// Connect to RabbitMQ
	amqpChannel, err := rabbitmq.NewRabbitMQChannel(cfg.RabbitMQConnStr, "order_events")
	if err != nil {
		log.Fatalf("Error connecting to RabbitMQ: %v", err)
	}
	defer amqpChannel.Close()
	log.Println("Connected to RabbitMQ (OrderService)")

	// Initialize Repositories
	orderRepo := postgres.NewOrderRepository(db)
	outboxRepo := postgres.NewOutboxRepository(db)
	eventPublisher := rabbitmq.NewEventPublisher(amqpChannel)

	// Initialize Application Services
	orderAppService := application.NewOrderService(orderRepo, outboxRepo)
	outboxRelayer := application.NewOutboxRelayer(outboxRepo, eventPublisher, cfg.OutboxPollInterval)

	// Start Outbox Relayer in a goroutine
	go outboxRelayer.Start(context.Background())
	log.Println("Outbox Relayer started.")

	// Setup HTTP API
	orderHandler := api.NewOrderHandler(orderAppService)
	http.HandleFunc("/orders", orderHandler.CreateOrder)
	log.Printf("OrderService listening on :%s", cfg.Port)
	log.Fatal(http.ListenAndServe(":"+cfg.Port, nil))
}