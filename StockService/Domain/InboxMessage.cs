public class InboxMessage
{
    public Guid Id { get; set; }
    public Guid MessageId { get; set; } // Unique ID from the incoming message
    public string Type { get; set; } = string.Empty;
    public string Payload { get; set; } = string.Empty;
    public DateTime ReceivedOn { get; set; }
    public DateTime? ProcessedDate { get; set; }
    public string Status { get; set; } = "Received"; // Received, Processing, Processed, Failed
}