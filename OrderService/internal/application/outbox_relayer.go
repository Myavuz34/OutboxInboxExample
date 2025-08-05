package application

import (
	"context"
	"log"
	"time"

	"order_service/internal/infrastructure/postgres"
	"order_service/internal/infrastructure/rabbitmq"
)

type OutboxRelayer struct {
	outboxRepo     *postgres.OutboxRepository
	eventPublisher *rabbitmq.EventPublisher
	pollInterval   time.Duration
}

func NewOutboxRelayer(obr *postgres.OutboxRepository, ep *rabbitmq.EventPublisher, interval time.Duration) *OutboxRelayer {
	return &OutboxRelayer{
		outboxRepo:     obr,
		eventPublisher: ep,
		pollInterval:   interval,
	}
}

func (r *OutboxRelayer) Start(ctx context.Context) {
	ticker := time.NewTicker(r.pollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			log.Println("Outbox Relayer: Shutting down.")
			return
		case <-ticker.C:
			r.processPendingMessages(ctx)
		}
	}
}

func (r *OutboxRelayer) processPendingMessages(ctx context.Context) {
	log.Println("Outbox Relayer: Checking for pending messages...")
	messages, err := r.outboxRepo.GetPendingMessages(ctx)
	if err != nil {
		log.Printf("Outbox Relayer Error fetching messages: %v", err)
		return
	}

	if len(messages) == 0 {
		return
	}

	for _, msg := range messages {
		err := r.eventPublisher.Publish(ctx, &msg)
		if err != nil {
			log.Printf("Outbox Relayer Error publishing message %s (Type: %s): %v", msg.ID, msg.Type, err)
			// In a real system, you might increment a retry count or move to a dead-letter queue.
			// For simplicity, we just log and continue. The message remains 'Pending' for next poll.
			continue
		}

		err = r.outboxRepo.UpdateMessageStatus(ctx, msg.ID, "Sent")
		if err != nil {
			log.Printf("Outbox Relayer Error updating message status %s: %v", msg.ID, err)
		} else {
			log.Printf("Outbox Relayer: Message %s (Type: %s) status updated to Sent.", msg.ID, msg.Type)
		}
	}
}