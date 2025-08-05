package api

import (
	"encoding/json"
	"log"
	"net/http"

	"order_service/internal/application"
	"order_service/internal/domain"

	"github.com/google/uuid"
)

// API request structure for creating an order
type CreateOrderRequest struct {
	CustomerID string                 `json:"customerId"`
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
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req CreateOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request payload", http.StatusBadRequest)
		log.Printf("Error decoding request: %v", err)
		return
	}

	customerID, err := uuid.Parse(req.CustomerID)
	if err != nil {
		http.Error(w, "Invalid customer ID", http.StatusBadRequest)
		log.Printf("Error parsing customer ID: %v", err)
		return
	}

	orderItems := make([]domain.OrderItem, len(req.Items))
	for i, itemReq := range req.Items {
		productID, err := uuid.Parse(itemReq.ProductID)
		if err != nil {
			http.Error(w, "Invalid product ID", http.StatusBadRequest)
			log.Printf("Error parsing product ID: %v", err)
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
		log.Printf("Error creating order: %v", err)
		http.Error(w, "Internal server error: failed to create order", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{"orderId": orderID.String(), "message": "Order created and event saved to Outbox."})
	log.Printf("Order %s created and event saved to Outbox.", orderID)
}