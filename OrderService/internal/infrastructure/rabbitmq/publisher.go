package rabbitmq

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"order_service/internal/domain"

	amqp "github.com/rabbitmq/amqp091-go"
)

type EventPublisher struct {
	channel      *amqp.Channel
	exchangeName string
}

func NewRabbitMQChannel(connStr, exchangeName string) (*amqp.Channel, error) {
	conn, err := amqp.Dial(connStr)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to RabbitMQ: %w", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("failed to open a channel: %w", err)
	}

	if err := ch.ExchangeDeclare(exchangeName, "topic", true, false, false, false, nil); err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to declare exchange: %w", err)
	}

	return ch, nil
}

func NewEventPublisher(ch *amqp.Channel, exchangeName string) *EventPublisher {
	return &EventPublisher{channel: ch, exchangeName: exchangeName}
}

func (p *EventPublisher) Publish(ctx context.Context, msg *domain.OutboxMessage) error {
	publishCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	err := p.channel.PublishWithContext(publishCtx,
		p.exchangeName,
		msg.Type,
		false,
		false,
		amqp.Publishing{
			ContentType: "application/json",
			Body:        msg.Payload,
			MessageId:   msg.ID.String(),
			Timestamp:   time.Now(),
		})
	if err != nil {
		return fmt.Errorf("failed to publish message to RabbitMQ: %w", err)
	}

	slog.Info("Published message to RabbitMQ",
		"message_id", msg.ID, "type", msg.Type, "exchange", p.exchangeName)
	return nil
}

// Channel returns the underlying AMQP channel for health checks
func (p *EventPublisher) Channel() *amqp.Channel {
	return p.channel
}