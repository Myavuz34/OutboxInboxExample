package postgres

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"order_service/internal/domain"

	"github.com/google/uuid"
)

type OutboxRepository struct {
	db *sql.DB
}

func NewOutboxRepository(db *sql.DB) *OutboxRepository {
	return &OutboxRepository{db: db}
}

func (r *OutboxRepository) DB() *sql.DB {
	return r.db
}

func (r *OutboxRepository) Save(ctx context.Context, tx *sql.Tx, msg *domain.OutboxMessage) error {
	_, err := tx.ExecContext(ctx, `INSERT INTO outbox_messages (id, aggregate_id, aggregate_type, type, payload, occurred_on, status) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		msg.ID, msg.AggregateID, msg.AggregateType, msg.Type, msg.Payload, msg.OccurredOn, msg.Status)
	if err != nil {
		return fmt.Errorf("failed to insert into outbox: %w", err)
	}
	return nil
}

func (r *OutboxRepository) GetAndLockPendingMessages(ctx context.Context, tx *sql.Tx) ([]domain.OutboxMessage, error) {
	rows, err := tx.QueryContext(ctx,
		`SELECT id, aggregate_id, aggregate_type, type, payload, occurred_on, processed_date, status
		 FROM outbox_messages
		 WHERE status = $1
		 ORDER BY occurred_on ASC
		 LIMIT 100
		 FOR UPDATE SKIP LOCKED`, domain.StatusPending)
	if err != nil {
		return nil, fmt.Errorf("querying outbox messages failed: %w", err)
	}
	defer rows.Close()

	var messages []domain.OutboxMessage
	for rows.Next() {
		var msg domain.OutboxMessage
		if err := rows.Scan(&msg.ID, &msg.AggregateID, &msg.AggregateType, &msg.Type, &msg.Payload, &msg.OccurredOn, &msg.ProcessedDate, &msg.Status); err != nil {
			return nil, fmt.Errorf("scanning outbox message failed: %w", err)
		}
		messages = append(messages, msg)
	}
	return messages, nil
}

func (r *OutboxRepository) UpdateMessageStatusTx(ctx context.Context, tx *sql.Tx, id uuid.UUID, status string) error {
	_, err := tx.ExecContext(ctx, `UPDATE outbox_messages SET status = $1, processed_date = $2 WHERE id = $3`, status, time.Now(), id)
	if err != nil {
		return fmt.Errorf("failed to update outbox message status: %w", err)
	}
	return nil
}