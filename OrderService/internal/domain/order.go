package domain

import (
	"time"

	"github.com/google/uuid"
)

type OrderAggregate struct {
	ID          uuid.UUID
	CustomerID  uuid.UUID
	OrderDate   time.Time
	Status      string
	TotalAmount float64
	Items       []OrderItem
}

type OrderItem struct {
	ID        uuid.UUID
	ProductID uuid.UUID
	Quantity  int
	Price     float64
}

func NewOrder(customerID uuid.UUID, items []OrderItem) *OrderAggregate {
	totalAmount := 0.0
	for _, item := range items {
		totalAmount += item.Price * float64(item.Quantity)
	}

	// Assign new UUIDs for order items here or in the service layer if preferred
	for i := range items {
		items[i].ID = uuid.New()
	}

	return &OrderAggregate{
		ID:          uuid.New(),
		CustomerID:  customerID,
		OrderDate:   time.Now(),
		Status:      "Pending",
		TotalAmount: totalAmount,
		Items:       items,
	}
}