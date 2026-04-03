using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace StockService.Migrations
{
    /// <inheritdoc />
    public partial class AddInboxIndexesAndRowVersion : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "IX_InboxMessages_Status",
                table: "InboxMessages",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_InboxMessages_ReceivedOn",
                table: "InboxMessages",
                column: "ReceivedOn");

            // RowVersion uses PostgreSQL xmin system column, no schema change needed
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_InboxMessages_Status",
                table: "InboxMessages");

            migrationBuilder.DropIndex(
                name: "IX_InboxMessages_ReceivedOn",
                table: "InboxMessages");
        }
    }
}
