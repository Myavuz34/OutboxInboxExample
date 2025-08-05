package postgres

import (
	"context"
	"database/sql"
	"fmt"

	"order_service/internal/domain"
)

type OrderRepository struct {
	db *sql.DB
}

func (r *OrderRepository) DB() {
	panic("unimplemented")
}

func NewOrderRepository(db *sql.DB) *OrderRepository {
	return &OrderRepository{db: db}
}

func (r *OrderRepository) Save(ctx context.Context, tx *sql.Tx, order *domain.OrderAggregate) error {
	_, err := tx.ExecContext(ctx, `INSERT INTO orders (id, customer_id, order_date, status, total_amount) VALUES ($1, $2, $3, $4, $5)`,
		order.ID, order.CustomerID, order.OrderDate, order.Status, order.TotalAmount)
	if err != nil {
		return fmt.Errorf("failed to insert order: %w", err)
	}

	for _, item := range order.Items {
		_, err = tx.ExecContext(ctx, `INSERT INTO order_items (id, order_id, product_id, quantity, price) VALUES ($1, $2, $3, $4, $5)`,
			item.ID, order.ID, item.ProductID, item.Quantity, item.Price)
		if err != nil {
			return fmt.Errorf("failed to insert order item: %w", err)
		}
	}
	return nil
}
