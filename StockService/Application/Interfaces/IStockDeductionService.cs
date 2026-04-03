using StockService.Events;

namespace StockService.Application.Interfaces;

public interface IStockDeductionService
{
    Task DeductStockAsync(OrderItemEvent[] items);
}
