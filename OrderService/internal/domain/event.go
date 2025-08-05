package domain

import (
	"database/sql"
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

// OrderCreatedEvent struct represents the event data
type OrderCreatedEvent struct {
	OrderID   uuid.UUID       `json:"orderId"`
	CustomerID uuid.UUID       `json:"customerId"`
	TotalAmount float64         `json:"totalAmount"`
	Items     []OrderItemEvent `json:"items"`
}

type OrderItemEvent struct {
	ProductID uuid.UUID `json:"productId"`
	Quantity  int       `json:"quantity"`
	Price     float64   `json:"price"`
}

// OutboxMessage struct represents an entry in the outbox table
type OutboxMessage struct {
	ID           uuid.UUID
	AggregateID  uuid.UUID
	AggregateType string
	Type         string
	Payload      json.RawMessage
	OccurredOn   time.Time
	ProcessedDate sql.NullTime
	Status       string
}

func NewOrderCreatedEvent(order *OrderAggregate) (OrderCreatedEvent, error) {
	eventItems := make([]OrderItemEvent, len(order.Items))
	for i, item := range order.Items {
		eventItems[i] = OrderItemEvent{
			ProductID: item.ProductID,
			Quantity:  item.Quantity,
			Price:     item.Price,
		}
	}
	return OrderCreatedEvent{
		OrderID:   order.ID,
		CustomerID: order.CustomerID,
		TotalAmount: order.TotalAmount,
		Items:     eventItems,
	}, nil
}

func NewOutboxMessage(aggregateID uuid.UUID, aggregateType, eventType string, eventPayload json.RawMessage) *OutboxMessage {
	return &OutboxMessage{
		ID:            uuid.New(),
		AggregateID:   aggregateID,
		AggregateType: aggregateType,
		Type:          eventType,
		Payload:       eventPayload,
		OccurredOn:    time.Now(),
		Status:        "Pending",
	}
}