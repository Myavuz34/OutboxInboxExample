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

        modelBuilder.Entity<InboxMessage>()
            .HasIndex(m => m.MessageId)
            .IsUnique(); // Ensure MessageId is unique

        // Optional: Configure precision for decimal types if needed
        modelBuilder.Entity<Product>()
            .Property(p => p.Price)
            .HasColumnType("decimal(10, 2)");
    }
}