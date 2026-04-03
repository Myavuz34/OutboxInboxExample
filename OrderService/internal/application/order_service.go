package application

import (
	"context"
	"encoding/json"
	"fmt"

	"order_service/internal/application/ports"
	"order_service/internal/domain"

	"github.com/google/uuid"
)

type OrderService struct {
	orderRepo  ports.OrderRepository
	outboxRepo ports.OutboxRepository
}

func NewOrderService(or ports.OrderRepository, obr ports.OutboxRepository) *OrderService {
	return &OrderService{orderRepo: or, outboxRepo: obr}
}

func (s *OrderService) CreateOrder(ctx context.Context, customerID uuid.UUID, items []domain.OrderItem) (uuid.UUID, error) {
	tx, err := s.orderRepo.DB().BeginTx(ctx, nil)
	if err != nil {
		return uuid.Nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	order := domain.NewOrder(customerID, items)

	if err := s.orderRepo.Save(ctx, tx, order); err != nil {
		return uuid.Nil, fmt.Errorf("failed to save order: %w", err)
	}

	orderCreatedEvent, err := domain.NewOrderCreatedEvent(order)
	if err != nil {
		return uuid.Nil, fmt.Errorf("failed to create order event: %w", err)
	}
	eventPayload, err := json.Marshal(orderCreatedEvent)
	if err != nil {
		return uuid.Nil, fmt.Errorf("failed to marshal event payload: %w", err)
	}

	outboxMsg := domain.NewOutboxMessage(order.ID, "Order", "OrderCreated", eventPayload)
	if err := s.outboxRepo.Save(ctx, tx, outboxMsg); err != nil {
		return uuid.Nil, fmt.Errorf("failed to save outbox message: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return uuid.Nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	return order.ID, nil
}