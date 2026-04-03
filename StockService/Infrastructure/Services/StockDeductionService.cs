using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using StockService.Application.Interfaces;
using StockService.Events;
using StockService.Infrastructure.Data;

namespace StockService.Infrastructure.Services;

public class StockDeductionService : IStockDeductionService
{
    private readonly StockDbContext _dbContext;
    private readonly ILogger<StockDeductionService> _logger;

    public StockDeductionService(StockDbContext dbContext, ILogger<StockDeductionService> logger)
    {
        _dbContext = dbContext;
        _logger = logger;
    }

    public async Task DeductStockAsync(OrderItemEvent[] items)
    {
        foreach (var item in items)
        {
            var product = await _dbContext.Products
                .FirstOrDefaultAsync(p => p.Id == item.ProductId)
                ?? throw new InvalidOperationException($"Product {item.ProductId} not found.");

            if (product.StockQuantity < item.Quantity)
            {
                throw new InvalidOperationException(
                    $"Insufficient stock for Product {item.ProductId}. Available: {product.StockQuantity}, Requested: {item.Quantity}");
            }

            product.StockQuantity -= item.Quantity;
            _logger.LogInformation("Stock decreased for Product {ProductId} by {Quantity}. New stock: {NewStock}",
                item.ProductId, item.Quantity, product.StockQuantity);
        }

        await _dbContext.SaveChangesAsync();
    }
}
