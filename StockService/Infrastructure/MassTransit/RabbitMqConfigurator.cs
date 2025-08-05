using MassTransit;
using StockService.Infrastructure.MassTransit.Consumers;

namespace StockService.Infrastructure.MassTransit
{
    public static class RabbitMqConfigurator
    {
        public static IServiceCollection AddMassTransitConfig(this IServiceCollection services, IConfiguration configuration)
        {
            services.AddMassTransit(x =>
            {
                // Register consumers
                x.AddConsumer<OrderCreatedConsumer>();

                x.UsingRabbitMq((context, cfg) =>
                {
                    cfg.Host("rabbitmq", "/", h =>
                    {
                        h.Username("guest");
                        h.Password("guest");
                    });

                    // Define receive endpoint for OrderCreated events
                    cfg.ReceiveEndpoint("order_created_queue", e =>
                    {
                        e.ConfigureConsumer<OrderCreatedConsumer>(context);
                        // Retry policy for transient errors (e.g., database connection issues)
                        e.UseMessageRetry(r => {
                            r.Interval(3, TimeSpan.FromSeconds(5)); // Retry 3 times with 5-second intervals
                            r.Ignore<InvalidOperationException>(); // Do NOT retry on specific business logic errors
                        });
                        // Optional: Configure durability, auto-delete, etc.
                        e.Durable = true;
                        e.AutoDelete = false;
                    });
                });
            });

            // This registers IHostedService to start and stop the bus automatically
            services.AddMassTransitHostedService();

            return services;
        }
    }
}