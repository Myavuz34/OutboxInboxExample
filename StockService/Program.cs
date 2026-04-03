using Microsoft.EntityFrameworkCore;
using StockService.Application.Interfaces;
using StockService.Domain;
using StockService.Infrastructure.Data;
using StockService.Infrastructure.MassTransit;
using StockService.Infrastructure.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddDbContext<StockDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("StockDbConnection")));

builder.Services.AddScoped<IInboxService, InboxService>();
builder.Services.AddScoped<IStockDeductionService, StockDeductionService>();

builder.Services.AddMassTransitConfig(builder.Configuration);

builder.Services.AddHealthChecks()
    .AddDbContextCheck<StockDbContext>("database");

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var logger = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();
    try
    {
        var dbContext = scope.ServiceProvider.GetRequiredService<StockDbContext>();
        await dbContext.Database.MigrateAsync();

        if (!await dbContext.Products.AnyAsync())
        {
            dbContext.Products.AddRange(
                new Product { Id = Guid.Parse("f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c"), Name = "Test Product 1", StockQuantity = 1000000, Price = 10.00m },
                new Product { Id = Guid.Parse("a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d"), Name = "Test Product 2", StockQuantity = 1000000, Price = 5.00m }
            );
            await dbContext.SaveChangesAsync();
            logger.LogInformation("Products seeded successfully");
        }
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Error applying migrations or seeding the database");
    }
}

app.MapHealthChecks("/health");

await app.RunAsync();