package api

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"

	"order_service/internal/application"
	"order_service/internal/domain"

	"github.com/google/uuid"
	amqp "github.com/rabbitmq/amqp091-go"
)

type CreateOrderRequest struct {
	CustomerID string                   `json:"customerId"`
	Items      []CreateOrderItemRequest `json:"items"`
}

type CreateOrderItemRequest struct {
	ProductID string  `json:"productId"`
	Quantity  int     `json:"quantity"`
	Price     float64 `json:"price"`
}

type OrderHandler struct {
	orderService *application.OrderService
}

func NewOrderHandler(os *application.OrderService) *OrderHandler {
	return &OrderHandler{orderService: os}
}

func (h *OrderHandler) CreateOrder(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSONError(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req CreateOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, "Invalid request payload", http.StatusBadRequest)
		return
	}

	customerID, err := uuid.Parse(req.CustomerID)
	if err != nil {
		writeJSONError(w, "Invalid customer ID format", http.StatusBadRequest)
		return
	}

	if len(req.Items) == 0 {
		writeJSONError(w, "Order must contain at least one item", http.StatusBadRequest)
		return
	}

	orderItems := make([]domain.OrderItem, len(req.Items))
	for i, itemReq := range req.Items {
		productID, err := uuid.Parse(itemReq.ProductID)
		if err != nil {
			writeJSONError(w, fmt.Sprintf("Invalid product ID at index %d", i), http.StatusBadRequest)
			return
		}
		if itemReq.Quantity <= 0 {
			writeJSONError(w, fmt.Sprintf("Quantity must be positive at index %d", i), http.StatusBadRequest)
			return
		}
		if itemReq.Price <= 0 {
			writeJSONError(w, fmt.Sprintf("Price must be positive at index %d", i), http.StatusBadRequest)
			return
		}
		orderItems[i] = domain.OrderItem{
			ProductID: productID,
			Quantity:  itemReq.Quantity,
			Price:     itemReq.Price,
		}
	}

	orderID, err := h.orderService.CreateOrder(r.Context(), customerID, orderItems)
	if err != nil {
		slog.Error("Failed to create order", "error", err)
		writeJSONError(w, "Failed to create order", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{
		"orderId": orderID.String(),
		"message": "Order created and event saved to Outbox.",
	})

	slog.Info("Order created", "order_id", orderID)
}

func writeJSONError(w http.ResponseWriter, message string, statusCode int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(map[string]string{"error": message})
}

// NewHealthHandler returns an HTTP handler that checks DB and RabbitMQ connectivity
func NewHealthHandler(db *sql.DB, amqpCh *amqp.Channel) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSONError(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		if err := db.PingContext(r.Context()); err != nil {
			slog.Error("Health check: database ping failed", "error", err)
			writeJSONError(w, "Database unhealthy", http.StatusServiceUnavailable)
			return
		}

		if amqpCh.IsClosed() {
			slog.Error("Health check: RabbitMQ channel closed")
			writeJSONError(w, "RabbitMQ unhealthy", http.StatusServiceUnavailable)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
	}
}