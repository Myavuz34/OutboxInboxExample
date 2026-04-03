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

func (r *OrderRepository) DB() *sql.DB {
	return r.db
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

	if len(order.Items) > 0 {
		query := "INSERT INTO order_items (id, order_id, product_id, quantity, price) VALUES "
		args := make([]interface{}, 0, len(order.Items)*5)
		for i, item := range order.Items {
			base := i * 5
			if i > 0 {
				query += ", "
			}
			query += fmt.Sprintf("($%d, $%d, $%d, $%d, $%d)", base+1, base+2, base+3, base+4, base+5)
			args = append(args, item.ID, order.ID, item.ProductID, item.Quantity, item.Price)
		}
		if _, err := tx.ExecContext(ctx, query, args...); err != nil {
			return fmt.Errorf("failed to insert order items: %w", err)
		}
	}

	return nil
}
