package application

import (
	"context"
	"log/slog"
	"time"

	"order_service/internal/application/ports"
	"order_service/internal/domain"
)

type OutboxRelayer struct {
	outboxRepo     ports.OutboxRepository
	eventPublisher ports.EventPublisher
	pollInterval   time.Duration
}

func NewOutboxRelayer(obr ports.OutboxRepository, ep ports.EventPublisher, interval time.Duration) *OutboxRelayer {
	return &OutboxRelayer{
		outboxRepo:     obr,
		eventPublisher: ep,
		pollInterval:   interval,
	}
}

func (r *OutboxRelayer) Start(ctx context.Context) {
	ticker := time.NewTicker(r.pollInterval)
	defer ticker.Stop()

	slog.Info("Outbox Relayer started", "poll_interval", r.pollInterval)

	for {
		select {
		case <-ctx.Done():
			slog.Info("Outbox Relayer shutting down")
			return
		case <-ticker.C:
			r.processPendingMessages(ctx)
		}
	}
}

func (r *OutboxRelayer) processPendingMessages(ctx context.Context) {
	slog.Debug("Outbox Relayer checking for pending messages")

	tx, err := r.outboxRepo.DB().BeginTx(ctx, nil)
	if err != nil {
		slog.Error("Outbox Relayer failed to begin transaction", "error", err)
		return
	}
	defer tx.Rollback()

	messages, err := r.outboxRepo.GetAndLockPendingMessages(ctx, tx)
	if err != nil {
		slog.Error("Outbox Relayer failed to fetch messages", "error", err)
		return
	}

	if len(messages) == 0 {
		return
	}

	slog.Info("Outbox Relayer processing messages", "count", len(messages))

	for _, msg := range messages {
		if err := r.eventPublisher.Publish(ctx, &msg); err != nil {
			slog.Error("Outbox Relayer failed to publish message",
				"message_id", msg.ID, "type", msg.Type, "error", err)
			continue
		}

		if err := r.outboxRepo.UpdateMessageStatusTx(ctx, tx, msg.ID, domain.StatusSent); err != nil {
			slog.Error("Outbox Relayer failed to update message status",
				"message_id", msg.ID, "error", err)
		} else {
			slog.Info("Outbox Relayer message sent",
				"message_id", msg.ID, "type", msg.Type)
		}
	}

	if err := tx.Commit(); err != nil {
		slog.Error("Outbox Relayer failed to commit transaction", "error", err)
	}
}