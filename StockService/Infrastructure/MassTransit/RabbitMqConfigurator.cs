using MassTransit;
using MassTransit.Serialization;
using StockService.Infrastructure.MassTransit.Consumers;

namespace StockService.Infrastructure.MassTransit;

public static class RabbitMqConfigurator
{
    public static IServiceCollection AddMassTransitConfig(this IServiceCollection services, IConfiguration configuration)
    {
        var rabbitHost = configuration["RabbitMQ:Host"] ?? "rabbitmq";
        var rabbitUser = configuration["RabbitMQ:Username"]
            ?? throw new InvalidOperationException("RabbitMQ:Username configuration is required");
        var rabbitPass = configuration["RabbitMQ:Password"]
            ?? throw new InvalidOperationException("RabbitMQ:Password configuration is required");

        services.AddMassTransit(x =>
        {
            x.AddConsumer<OrderCreatedConsumer>();

            x.UsingRabbitMq((context, cfg) =>
            {
                cfg.Host(rabbitHost, "/", h =>
                {
                    h.Username(rabbitUser);
                    h.Password(rabbitPass);
                });

                cfg.ReceiveEndpoint("order_created_queue", e =>
                {
                    e.Bind("order_events", s =>
                    {
                        s.RoutingKey = "OrderCreated";
                        s.ExchangeType = "topic";
                    });
                    e.UseRawJsonDeserializer(RawSerializerOptions.AnyMessageType);
                    e.UseMessageRetry(r =>
                    {
                        r.Interval(3, TimeSpan.FromSeconds(5));
                        r.Ignore<InvalidOperationException>();
                    });
                    e.ConfigureConsumer<OrderCreatedConsumer>(context);
                });
            });
        });

        return services;
    }
}