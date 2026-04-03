-- =============================================================================
-- STOCK_DB - Veritabani Scripti (PostgreSQL 17)
-- =============================================================================
-- Kullanim:  psql -U user -d stock_db -f stock_db.sql
-- Docker:    docker exec -i stock_db psql -U user -d stock_db < db-scripts/stock_db.sql
-- Not:       Docker compose ile calistirildiginda bu scriptler EF Core MigrateAsync()
--            tarafindan otomatik uygulanir. Bu dosya manuel referans icindir.
-- =============================================================================

-- =====================
-- SCHEMA
-- =====================

-- Urunler tablosu
CREATE TABLE IF NOT EXISTS "Products" (
    "Id"                UUID            PRIMARY KEY,
    "Name"              TEXT            NOT NULL,
    "StockQuantity"     INTEGER         NOT NULL,
    "Price"             DECIMAL(10, 2)  NOT NULL
    -- RowVersion: PostgreSQL xmin system column kullanilir (EF Core [Timestamp])
    -- Optimistic concurrency icin otomatik yonetilir, schema'da gorunmez
);

-- Inbox mesajlari tablosu (Inbox Pattern - Idempotent mesaj isleme)
-- Her gelen mesaj once bu tabloya "Processing" olarak yazilir.
-- Basarili isleme sonrasi "Processed", hata durumunda "Failed" olarak guncellenir.
CREATE TABLE IF NOT EXISTS "InboxMessages" (
    "Id"                UUID                        PRIMARY KEY,
    "MessageId"         UUID                        NOT NULL,   -- RabbitMQ message ID (idempotency key)
    "Type"              TEXT                        NOT NULL,   -- 'OrderCreatedEvent'
    "Payload"           TEXT                        NOT NULL,   -- JSON event verisi
    "ReceivedOn"        TIMESTAMP WITH TIME ZONE    NOT NULL,   -- Mesajin alindigi zaman
    "ProcessedDate"     TIMESTAMP WITH TIME ZONE,               -- Islemenin tamamlandigi zaman
    "Status"            TEXT                        NOT NULL    -- 'Received' | 'Processing' | 'Processed' | 'Failed'
);

-- EF Core migration takip tablosu (EF Core tarafindan otomatik olusturulur)
CREATE TABLE IF NOT EXISTS "__EFMigrationsHistory" (
    "MigrationId"       VARCHAR(150)    PRIMARY KEY,
    "ProductVersion"    VARCHAR(32)     NOT NULL
);

-- =====================
-- INDEXES
-- =====================

-- Idempotency: Ayni MessageId ile birden fazla kayit olusturulamaz
CREATE UNIQUE INDEX IF NOT EXISTS "IX_InboxMessages_MessageId"
    ON "InboxMessages" ("MessageId");

-- Inbox sorgularinda status filtresi icin
CREATE INDEX IF NOT EXISTS "IX_InboxMessages_Status"
    ON "InboxMessages" ("Status");

-- Temizlik/izleme sorgulari icin (eski mesajlari bul)
CREATE INDEX IF NOT EXISTS "IX_InboxMessages_ReceivedOn"
    ON "InboxMessages" ("ReceivedOn");

-- =====================
-- SEED DATA
-- =====================
-- 2 test urunu (OrderService'teki siparis kalemleriyle eslesiyor)

INSERT INTO "Products" ("Id", "Name", "StockQuantity", "Price")
VALUES
    ('f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c', 'Test Product 1', 1000000, 10.00),
    ('a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'Test Product 2', 1000000, 5.00)
ON CONFLICT DO NOTHING;

-- Migration kayitlari (EF Core'un migration'larin uygulandigini bilmesi icin)
INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
VALUES
    ('20250112000000_InitialCreate', '9.0.7'),
    ('20250403000000_AddInboxIndexesAndRowVersion', '9.0.7')
ON CONFLICT DO NOTHING;
