using StockService.Domain;

namespace StockService.Application.Interfaces;

public interface IInboxService
{
    Task<InboxMessage?> GetByMessageIdAsync(Guid messageId);
    Task<InboxMessage> CreateAsync(Guid messageId, string type, string payload);
    Task UpdateStatusAsync(Guid id, string status, DateTime? processedDate = null);
}
