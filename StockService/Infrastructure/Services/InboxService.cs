using Microsoft.EntityFrameworkCore;
using StockService.Application.Interfaces;
using StockService.Domain;
using StockService.Infrastructure.Data;

namespace StockService.Infrastructure.Services;

public class InboxService : IInboxService
{
    private readonly StockDbContext _dbContext;

    public InboxService(StockDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<InboxMessage?> GetByMessageIdAsync(Guid messageId)
    {
        return await _dbContext.InboxMessages
            .FirstOrDefaultAsync(m => m.MessageId == messageId);
    }

    public async Task<InboxMessage> CreateAsync(Guid messageId, string type, string payload)
    {
        var message = new InboxMessage
        {
            Id = Guid.NewGuid(),
            MessageId = messageId,
            Type = type,
            Payload = payload,
            ReceivedOn = DateTime.UtcNow,
            Status = InboxStatus.Processing
        };

        await _dbContext.InboxMessages.AddAsync(message);
        await _dbContext.SaveChangesAsync();
        return message;
    }

    public async Task UpdateStatusAsync(Guid id, string status, DateTime? processedDate = null)
    {
        var message = await _dbContext.InboxMessages.FindAsync(id);
        if (message != null)
        {
            message.Status = status;
            message.ProcessedDate = processedDate;
            await _dbContext.SaveChangesAsync();
        }
    }
}
