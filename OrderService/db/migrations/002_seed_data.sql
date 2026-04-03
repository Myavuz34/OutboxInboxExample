-- Seed data: StockService'teki urunlerle eslesen ornek siparis
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
