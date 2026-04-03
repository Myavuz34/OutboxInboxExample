using Microsoft.EntityFrameworkCore;
using StockService.Domain;

namespace StockService.Infrastructure.Data;

public class StockDbContext : DbContext
{
    public StockDbContext(DbContextOptions<StockDbContext> options) : base(options) { }

    public DbSet<Product> Products { get; set; }
    public DbSet<InboxMessage> InboxMessages { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<InboxMessage>(entity =>
        {
            entity.HasIndex(m => m.MessageId).IsUnique();
            entity.HasIndex(m => m.Status);
            entity.HasIndex(m => m.ReceivedOn);
        });

        modelBuilder.Entity<Product>(entity =>
        {
            entity.Property(p => p.Price).HasColumnType("decimal(10, 2)");
            entity.Property(p => p.RowVersion).IsRowVersion();
        });
    }
}