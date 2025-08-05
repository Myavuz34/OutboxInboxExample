using System;
using System.Linq;
using System.Threading.Tasks;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using StockService.Domain;
using StockService.Events;
using StockService.Infrastructure.Data;
using System.Data; // For IsolationLevel
using System.Text.Json; // For JSON serialization

namespace StockService.Infrastructure.MassTransit.Consumers
{
    public class OrderCreatedConsumer : IConsumer<OrderCreatedEvent>
    {
        private readonly StockDbContext _dbContext;

        public OrderCreatedConsumer(StockDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public async Task Consume(ConsumeContext<OrderCreatedEvent> context)
        {
            Console.WriteLine($"[StockService] Received OrderCreatedEvent for Order ID: {context.Message.OrderId}");

            var messageId = context.MessageId ?? throw new InvalidOperationException("MessageId cannot be null.");

            // Use a transaction for atomicity of Inbox and business logic
            // ReadCommitted is generally a good balance for concurrency.
            await using var transaction = await _dbContext.Database.BeginTransactionAsync(IsolationLevel.ReadCommitted);

            try
            {
                // Step 1: Check Inbox for idempotency
                var existingInboxMessage = await _dbContext.InboxMessages
                    .FirstOrDefaultAsync(m => m.MessageId == messageId);

                if (existingInboxMessage != null)
                {
                    if (existingInboxMessage.Status == "Processed")
                    {
                        Console.WriteLine($"[StockService] Message {messageId} already processed. Skipping further processing.");
                        await transaction.RollbackAsync(); // Rollback this transaction as no work is needed
                        return;
                    }
                    else if (existingInboxMessage.Status == "Processing")
                    {
                        Console.WriteLine($"[StockService] Message {messageId} is currently being processed by another consumer instance or a previous retry. Skipping to avoid contention.");
                        await transaction.RollbackAsync(); // Avoid concurrent updates
                        return;
                    }
                }

                // Step 2: Record message in Inbox as "Processing"
                InboxMessage inboxMessage;
                if (existingInboxMessage == null)
                {
                    inboxMessage = new InboxMessage
                    {
                        Id = Guid.NewGuid(),
                        MessageId = messageId,
                        Type = typeof(OrderCreatedEvent).Name,
                        Payload = JsonSerializer.Serialize(context.Message),
                        ReceivedOn = DateTime.UtcNow,
                        Status = "Processing"
                    };
                    await _dbContext.InboxMessages.AddAsync(inboxMessage);
                }
                else
                {
                    inboxMessage = existingInboxMessage;
                    inboxMessage.Status = "Processing"; // Update status for retry cases
                    _dbContext.InboxMessages.Update(inboxMessage);
                }
                await _dbContext.SaveChangesAsync(); // Persist inbox status within the transaction

                // Step 3: Process business logic (decrease stock)
                foreach (var item in context.Message.Items)
                {
                    var product = await _dbContext.Products
                                                .Where(p => p.Id == item.ProductId)
                                                .FirstOrDefaultAsync();

                    if (product == null)
                    {
                        Console.WriteLine($"[StockService] Product {item.ProductId} not found. Cannot update stock.");
                        throw new InvalidOperationException($"Product {item.ProductId} not found."); // Business error
                    }
                    if (product.StockQuantity < item.Quantity)
                    {
                        Console.WriteLine($"[StockService] Insufficient stock for Product {item.ProductId}. Available: {product.StockQuantity}, Requested: {item.Quantity}");
                        throw new InvalidOperationException($"Insufficient stock for Product {item.ProductId}."); // Business error
                    }
                    
                    product.StockQuantity -= item.Quantity;
                    // EF Core tracks changes, so no explicit .Update() is usually needed if fetched within the same context
                    Console.WriteLine($"[StockService] Decreased stock for Product {item.ProductId} by {item.Quantity}. New stock: {product.StockQuantity}");
                }

                await _dbContext.SaveChangesAsync(); // Save product changes within the transaction

                // Step 4: Mark Inbox message as "Processed"
                inboxMessage.Status = "Processed";
                inboxMessage.ProcessedDate = DateTime.UtcNow;
                await _dbContext.SaveChangesAsync();

                await transaction.CommitAsync(); // Commit the entire transaction
                Console.WriteLine($"[StockService] Stock updated and Inbox message {messageId} marked as Processed successfully.");
            }
            catch (InvalidOperationException ex)
            {
                // This is a business-level failure (e.g., product not found, insufficient stock).
                // We mark the Inbox message as "Failed" and DO NOT re-throw for MassTransit retries.
                await transaction.RollbackAsync();
                Console.Error.WriteLine($"[StockService] Business logic error processing message {messageId}: {ex.Message}");

                var inboxMessage = await _dbContext.InboxMessages.FirstOrDefaultAsync(m => m.MessageId == messageId);
                if (inboxMessage != null)
                {
                    inboxMessage.Status = "Failed";
                    inboxMessage.ProcessedDate = DateTime.UtcNow;
                    await _dbContext.SaveChangesAsync();
                }
                // MassTransit will acknowledge the message as consumed, preventing further retries for this business error.
            }
            catch (Exception ex)
            {
                // This is a technical/transient failure (e.g., database connection lost).
                // Rollback the transaction and re-throw so MassTransit can retry the message.
                await transaction.RollbackAsync();
                Console.Error.WriteLine($"[StockService] Technical error processing message {messageId}: {ex.Message}");
                // No need to update Inbox status here, as MassTransit's retry mechanism will handle it.
                throw; // Re-throw the exception for MassTransit to apply retry policy or move to dead-letter queue.
            }
        }
    }
}