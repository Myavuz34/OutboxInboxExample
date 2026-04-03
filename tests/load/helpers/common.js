import http from 'k6/http';
import { check } from 'k6';
import { Counter, Trend } from 'k6/metrics';

// Metrikleri tanimla
export const ordersCreated = new Counter('orders_created');
export const orderLatency = new Trend('order_latency', true);

// Sabitler
export const BASE_URL = __ENV.ORDER_SERVICE_URL || 'http://host.docker.internal:8080';

export const PRODUCT_IDS = [
    'f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c', // Test Product 1, $10.00
    'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', // Test Product 2, $5.00
];

export const CUSTOMER_ID = '22222222-2222-2222-2222-222222222222';

// Rastgele urun secip siparis payload'i olustur
export function generateOrderPayload() {
    const productId = PRODUCT_IDS[Math.floor(Math.random() * PRODUCT_IDS.length)];
    return JSON.stringify({
        customerId: CUSTOMER_ID,
        items: [
            {
                productId: productId,
                quantity: 1,
                price: productId === PRODUCT_IDS[0] ? 10.00 : 5.00,
            },
        ],
    });
}

// Siparis olustur ve sonucu kontrol et
export function createOrder() {
    const payload = generateOrderPayload();
    const params = { headers: { 'Content-Type': 'application/json' } };

    const res = http.post(`${BASE_URL}/orders`, payload, params);

    const success = check(res, {
        'status 201': (r) => r.status === 201,
        'orderId mevcut': (r) => {
            try {
                const body = JSON.parse(r.body);
                return body.orderId && body.orderId.length > 0;
            } catch (e) {
                return false;
            }
        },
    });

    if (success) {
        ordersCreated.add(1);
    }
    orderLatency.add(res.timings.duration);

    return res;
}
