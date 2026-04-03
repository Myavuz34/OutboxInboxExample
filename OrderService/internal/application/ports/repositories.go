package ports

import (
	"context"
	"database/sql"

	"order_service/internal/domain"

	"github.com/google/uuid"
)

type OrderRepository interface {
	Save(ctx context.Context, tx *sql.Tx, order *domain.OrderAggregate) error
	DB() *sql.DB
}

type OutboxRepository interface {
	Save(ctx context.Context, tx *sql.Tx, msg *domain.OutboxMessage) error
	GetAndLockPendingMessages(ctx context.Context, tx *sql.Tx) ([]domain.OutboxMessage, error)
	UpdateMessageStatusTx(ctx context.Context, tx *sql.Tx, id uuid.UUID, status string) error
	DB() *sql.DB
}

type EventPublisher interface {
	Publish(ctx context.Context, msg *domain.OutboxMessage) error
}
