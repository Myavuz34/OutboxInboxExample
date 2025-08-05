package rabbitmq

import (
	"context"
	"fmt"
	"log"
	"time"

	"order_service/internal/domain"

	amqp "github.com/rabbitmq/amqp091-go"
)

type EventPublisher struct {
	channel *amqp.Channel
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

	err = ch.ExchangeDeclare(
		exchangeName, // name
		"topic",      // type
		true,         // durable
		false,        // auto-deleted
		false,        // internal
		false,        // no-wait
		nil,          // arguments
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to declare an exchange: %w", err)
	}
	return ch, nil
}

func NewEventPublisher(ch *amqp.Channel) *EventPublisher {
	return &EventPublisher{channel: ch}
}

func (p *EventPublisher) Publish(ctx context.Context, msg *domain.OutboxMessage) error {
	publishCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	err := p.channel.PublishWithContext(publishCtx,
		"order_events", // exchange
		msg.Type,       // routing key (event type)
		false,          // mandatory
		false,          // immediate
		amqp.Publishing{
			ContentType: "application/json",
			Body:        msg.Payload,
			MessageId:   msg.ID.String(), // Use outbox message ID as RabbitMQ message ID for idempotency
			Timestamp:   time.Now(),
		})
	if err != nil {
		return fmt.Errorf("failed to publish message to RabbitMQ: %w", err)
	}
	log.Printf("Published message %s (Type: %s) to RabbitMQ.", msg.ID, msg.Type)
	return nil
}