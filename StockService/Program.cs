using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using StockService.Domain;
using StockService.Infrastructure.Data;
using StockService.Infrastructure.MassTransit; // Custom namespace for MassTransit config

namespace StockService
{
    public class Program
    {
        public static async Task Main(string[] args)
        {
            var host = CreateHostBuilder(args).Build();

            // Apply migrations and seed data on startup
            using (var scope = host.Services.CreateScope())
            {
                var services = scope.ServiceProvider;
                try
                {
                    var dbContext = services.GetRequiredService<StockDbContext>();
                    await dbContext.Database.MigrateAsync(); // Apply pending migrations

                    if (!await dbContext.Products.AnyAsync())
                    {
                        dbContext.Products.AddRange(
                            new Product { Id = Guid.Parse("f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c"), Name = "Test Product 1", StockQuantity = 1000000, Price = 10.00m },
                            new Product { Id = Guid.Parse("a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d"), Name = "Test Product 2", StockQuantity = 1000000, Price = 5.00m }
                        );
                        await dbContext.SaveChangesAsync();
                        Console.WriteLine("Products seeded successfully.");
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"An error occurred while applying migrations or seeding the DB: {ex.Message}");
                    // Log the error appropriately
                }
            }

            await host.RunAsync();
        }

        public static IHostBuilder CreateHostBuilder(string[] args) =>
            Host.CreateDefaultBuilder(args)
                .ConfigureServices((hostContext, services) =>
                {
                    // Configure PostgreSQL for StockService
                    services.AddDbContext<StockDbContext>(options =>
                        options.UseNpgsql(hostContext.Configuration.GetConnectionString("StockDbConnection")));

                    // Configure MassTransit
                    services.AddMassTransitConfig(hostContext.Configuration);
                });
    }
}