using System.Data;
using System.Text.Json;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using StockService.Application.Interfaces;
using StockService.Domain;
using StockService.Events;
using StockService.Infrastructure.Data;

namespace StockService.Infrastructure.MassTransit.Consumers;

public class OrderCreatedConsumer : IConsumer<OrderCreatedEvent>
{
    private readonly StockDbContext _dbContext;
    private readonly IInboxService _inboxService;
    private readonly IStockDeductionService _stockService;
    private readonly ILogger<OrderCreatedConsumer> _logger;

    public OrderCreatedConsumer(
        StockDbContext dbContext,
        IInboxService inboxService,
        IStockDeductionService stockService,
        ILogger<OrderCreatedConsumer> logger)
    {
        _dbContext = dbContext;
        _inboxService = inboxService;
        _stockService = stockService;
        _logger = logger;
    }

    public async Task Consume(ConsumeContext<OrderCreatedEvent> context)
    {
        _logger.LogInformation("Received OrderCreatedEvent for Order {OrderId}", context.Message.OrderId);

        var messageId = context.MessageId ?? throw new InvalidOperationException("MessageId cannot be null.");

        await using var transaction = await _dbContext.Database.BeginTransactionAsync(IsolationLevel.ReadCommitted);

        try
        {
            var existingMessage = await _inboxService.GetByMessageIdAsync(messageId);

            if (existingMessage != null)
            {
                if (existingMessage.Status == InboxStatus.Processed)
                {
                    _logger.LogInformation("Message {MessageId} already processed, skipping", messageId);
                    await transaction.RollbackAsync();
                    return;
                }

                if (existingMessage.Status == InboxStatus.Processing)
                {
                    _logger.LogWarning("Message {MessageId} is currently being processed, skipping", messageId);
                    await transaction.RollbackAsync();
                    return;
                }
            }

            InboxMessage inboxMessage;
            if (existingMessage == null)
            {
                inboxMessage = await _inboxService.CreateAsync(
                    messageId,
                    nameof(OrderCreatedEvent),
                    JsonSerializer.Serialize(context.Message));
            }
            else
            {
                existingMessage.Status = InboxStatus.Processing;
                await _dbContext.SaveChangesAsync();
                inboxMessage = existingMessage;
            }

            await _stockService.DeductStockAsync(context.Message.Items);

            await _inboxService.UpdateStatusAsync(inboxMessage.Id, InboxStatus.Processed, DateTime.UtcNow);

            await transaction.CommitAsync();
            _logger.LogInformation("Message {MessageId} processed successfully", messageId);
        }
        catch (InvalidOperationException ex)
        {
            await transaction.RollbackAsync();
            _logger.LogError(ex, "Business error processing message {MessageId}", messageId);

            try
            {
                var inbox = await _inboxService.GetByMessageIdAsync(messageId);
                if (inbox != null)
                {
                    inbox.Status = InboxStatus.Failed;
                    inbox.ProcessedDate = DateTime.UtcNow;
                }
                else
                {
                    _dbContext.InboxMessages.Add(new InboxMessage
                    {
                        Id = Guid.NewGuid(),
                        MessageId = messageId,
                        Type = nameof(OrderCreatedEvent),
                        Payload = JsonSerializer.Serialize(context.Message),
                        ReceivedOn = DateTime.UtcNow,
                        ProcessedDate = DateTime.UtcNow,
                        Status = InboxStatus.Failed
                    });
                }
                await _dbContext.SaveChangesAsync();
            }
            catch (Exception saveEx)
            {
                _logger.LogError(saveEx, "Failed to mark inbox message {MessageId} as Failed", messageId);
            }
        }
        catch (Exception ex)
        {
            await transaction.RollbackAsync();
            _logger.LogError(ex, "Technical error processing message {MessageId}", messageId);
            throw;
        }
    }
}