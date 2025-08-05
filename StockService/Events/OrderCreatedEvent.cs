using System;

namespace StockService.Events
{
    // Records are immutable by default and good for events
    public record OrderCreatedEvent(Guid OrderId, Guid CustomerId, decimal TotalAmount, OrderItemEvent[] Items);
    public record OrderItemEvent(Guid ProductId, int Quantity, decimal Price);
}