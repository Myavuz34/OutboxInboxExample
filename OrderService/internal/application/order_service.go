package application

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"order_service/internal/domain"
	"order_service/internal/infrastructure/postgres"

	"github.com/google/uuid"
)

type OrderService struct {
	orderRepo  *postgres.OrderRepository
	outboxRepo *postgres.OutboxRepository
}

func NewOrderService(or *postgres.OrderRepository, obr *postgres.OutboxRepository) *OrderService {
	return &OrderService{orderRepo: or, outboxRepo: obr}
}

func (s *OrderService) CreateOrder(ctx context.Context, customerID uuid.UUID, items []domain.OrderItem) (uuid.UUID, error) {
	tx, err := s.orderRepo.DB().BeginTx(ctx, nil) // Use the underlying DB connection for transaction
	if err != nil {
		return uuid.Nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
			panic(r) // Re-throw panic
		} else if err != nil {
			tx.Rollback() // Rollback on error
		} else {
			err = tx.Commit() // Commit on success
			if err != nil {
				log.Printf("Failed to commit transaction: %v", err)
			}
		}
	}()

	// 1. Create new Order Aggregate
	order := domain.NewOrder(customerID, items)

	// 2. Save Order to orders table within the transaction
	err = s.orderRepo.Save(ctx, tx, order)
	if err != nil {
		return uuid.Nil, err
	}

	// 3. Create OrderCreatedEvent
	orderCreatedEvent, err := domain.NewOrderCreatedEvent(order)
	if err != nil {
		return uuid.Nil, fmt.Errorf("failed to create order created event: %w", err)
	}
	eventPayload, err := json.Marshal(orderCreatedEvent)
	if err != nil {
		return uuid.Nil, fmt.Errorf("failed to marshal event payload: %w", err)
	}

	// 4. Save event to Outbox table within the same transaction
	outboxMsg := domain.NewOutboxMessage(order.ID, "Order", "OrderCreated", eventPayload)
	err = s.outboxRepo.Save(ctx, tx, outboxMsg)
	if err != nil {
		return uuid.Nil, err
	}

	return order.ID, nil
}