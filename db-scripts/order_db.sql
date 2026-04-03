-- =============================================================================
-- ORDER_DB - Veritabani Scripti (PostgreSQL 17)
-- =============================================================================
-- Kullanim:  psql -U user -d order_db -f order_db.sql
-- Docker:    docker exec -i order_db psql -U user -d order_db < db-scripts/order_db.sql
-- Not:       Docker compose ile calistirildiginda bu scriptler otomatik uygulanir
--            (docker-entrypoint-initdb.d uzerinden)
-- =============================================================================

-- =====================
-- SCHEMA
-- =====================

-- Siparisler tablosu
CREATE TABLE IF NOT EXISTS orders (
    id              UUID            PRIMARY KEY,
    customer_id     UUID            NOT NULL,
    order_date      TIMESTAMP       NOT NULL,
    status          VARCHAR(50)     NOT NULL,           -- 'Pending', 'Completed', vb.
    total_amount    DECIMAL(10, 2)  NOT NULL,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- Siparis kalemleri tablosu
CREATE TABLE IF NOT EXISTS order_items (
    id              UUID            PRIMARY KEY,
    order_id        UUID            NOT NULL,
    product_id      UUID            NOT NULL,
    quantity        INT             NOT NULL,
    price           DECIMAL(10, 2)  NOT NULL,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
);

-- Transactional Outbox tablosu
-- Outbox pattern: siparis olusturuldugunda ayni transaction icinde
-- bu tabloya event yazilir. Relayer bu tabloyu poll ederek RabbitMQ'ya yayinlar.
CREATE TABLE IF NOT EXISTS outbox_messages (
    id              UUID            PRIMARY KEY,
    aggregate_id    UUID            NOT NULL,           -- Hangi siparisin event'i
    aggregate_type  VARCHAR(100)    NOT NULL,           -- 'Order'
    type            VARCHAR(100)    NOT NULL,           -- 'OrderCreated'
    payload         JSONB           NOT NULL,           -- Event JSON verisi
    occurred_on     TIMESTAMP       NOT NULL,           -- Event olusma zamani
    processed_date  TIMESTAMP,                          -- RabbitMQ'ya gonderilme zamani
    status          VARCHAR(50)     NOT NULL DEFAULT 'Pending', -- 'Pending' | 'Sent'
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- =====================
-- INDEXES
-- =====================

-- Outbox Relayer bu index'i kullanir: WHERE status='Pending' ORDER BY occurred_on
CREATE INDEX IF NOT EXISTS idx_outbox_status
    ON outbox_messages(status, occurred_on);

-- Siparis kalemlerini order_id ile hizli sorgulama
CREATE INDEX IF NOT EXISTS idx_order_items_order_id
    ON order_items(order_id);

-- Musteriye gore siparis sorgulama
CREATE INDEX IF NOT EXISTS idx_orders_customer_id
    ON orders(customer_id);

-- =====================
-- SEED DATA
-- =====================
-- StockService'teki urunlerle eslesen ornek siparis
-- Product 1: f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c (Test Product 1, $10.00)
-- Product 2: a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d (Test Product 2, $5.00)

INSERT INTO orders (id, customer_id, order_date, status, total_amount)
VALUES ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', NOW(), 'Pending', 25.00)
ON CONFLICT DO NOTHING;

INSERT INTO order_items (id, order_id, product_id, quantity, price)
VALUES
    ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c', 1, 10.00),
    ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 3, 5.00)
ON CONFLICT DO NOTHING;
