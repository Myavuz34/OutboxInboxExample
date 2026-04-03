#!/bin/bash
# =============================================================================
# Outbox/Inbox Pattern - Uctan Uca (E2E) Test Senaryolari
# =============================================================================
# Kullanim: bash tests/e2e_tests.sh
# Onkosul: docker compose up --build -d ile servisler ayakta olmali
# =============================================================================

set -e

PASS=0
FAIL=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

assert_eq() {
    TOTAL=$((TOTAL + 1))
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo -e "  ${GREEN}PASS${NC} [$TOTAL] $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} [$TOTAL] $test_name"
        echo -e "       Expected: $expected"
        echo -e "       Actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    TOTAL=$((TOTAL + 1))
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if echo "$actual" | grep -q "$expected"; then
        echo -e "  ${GREEN}PASS${NC} [$TOTAL] $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} [$TOTAL] $test_name"
        echo -e "       Expected to contain: $expected"
        echo -e "       Actual: $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_http_status() {
    TOTAL=$((TOTAL + 1))
    local test_name="$1"
    local expected_status="$2"
    local url="$3"
    local method="${4:-GET}"
    local data="$5"

    if [ "$method" = "POST" ] && [ -n "$data" ]; then
        actual_status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$url" -H "Content-Type: application/json" -d "$data")
    else
        actual_status=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    fi

    if [ "$expected_status" = "$actual_status" ]; then
        echo -e "  ${GREEN}PASS${NC} [$TOTAL] $test_name (HTTP $actual_status)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} [$TOTAL] $test_name"
        echo -e "       Expected HTTP: $expected_status"
        echo -e "       Actual HTTP:   $actual_status"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}  BOLUM 1: CONTAINER SAGLIK KONTROLLERI  ${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 1.1: Tum container'lar calisiyor mu?
RUNNING=$(docker compose ps --format json 2>/dev/null | grep -c '"running"' || echo "0")
assert_eq "5 container calisiyor" "5" "$RUNNING"

# Test 1.2-1.6: Her bir container saglikli mi?
for svc in order_db stock_db rabbitmq order_service stock_service; do
    health=$(docker inspect --format='{{.State.Health.Status}}' "$svc" 2>/dev/null || echo "none")
    assert_eq "$svc container healthy" "healthy" "$health"
done

# =============================================================================
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}  BOLUM 2: HEALTH CHECK ENDPOINT'LERI    ${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 2.1: OrderService /health 200 donuyor
assert_http_status "OrderService /health -> 200" "200" "http://localhost:8080/health"

# Test 2.2: StockService /health 200 donuyor
assert_http_status "StockService /health -> 200" "200" "http://localhost:8081/health"

# Test 2.3: OrderService health response icerigi
HEALTH_BODY=$(curl -s http://localhost:8080/health)
assert_contains "OrderService health body 'healthy' iceriyor" "healthy" "$HEALTH_BODY"

# Test 2.4: StockService health response icerigi
HEALTH_BODY=$(curl -s http://localhost:8081/health)
assert_contains "StockService health body 'Healthy' iceriyor" "Healthy" "$HEALTH_BODY"

# =============================================================================
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}  BOLUM 3: INPUT VALIDATION              ${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 3.1: Bos items -> 400
assert_http_status "Bos items dizisi -> 400" "400" "http://localhost:8080/orders" "POST" \
    '{"customerId":"22222222-2222-2222-2222-222222222222","items":[]}'

# Test 3.2: Bos items hata mesaji
BODY=$(curl -s -X POST http://localhost:8080/orders -H "Content-Type: application/json" \
    -d '{"customerId":"22222222-2222-2222-2222-222222222222","items":[]}')
assert_contains "Bos items hata mesaji dogru" "at least one item" "$BODY"

# Test 3.3: Negatif quantity -> 400
assert_http_status "Negatif quantity -> 400" "400" "http://localhost:8080/orders" "POST" \
    '{"customerId":"22222222-2222-2222-2222-222222222222","items":[{"productId":"f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c","quantity":-1,"price":10.00}]}'

# Test 3.4: Sifir quantity -> 400
assert_http_status "Sifir quantity -> 400" "400" "http://localhost:8080/orders" "POST" \
    '{"customerId":"22222222-2222-2222-2222-222222222222","items":[{"productId":"f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c","quantity":0,"price":10.00}]}'

# Test 3.5: Negatif fiyat -> 400
assert_http_status "Negatif fiyat -> 400" "400" "http://localhost:8080/orders" "POST" \
    '{"customerId":"22222222-2222-2222-2222-222222222222","items":[{"productId":"f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c","quantity":1,"price":-5.00}]}'

# Test 3.6: Sifir fiyat -> 400
assert_http_status "Sifir fiyat -> 400" "400" "http://localhost:8080/orders" "POST" \
    '{"customerId":"22222222-2222-2222-2222-222222222222","items":[{"productId":"f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c","quantity":1,"price":0}]}'

# Test 3.7: Gecersiz customer ID -> 400
assert_http_status "Gecersiz customer UUID -> 400" "400" "http://localhost:8080/orders" "POST" \
    '{"customerId":"not-a-uuid","items":[{"productId":"f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c","quantity":1,"price":10.00}]}'

# Test 3.8: Gecersiz product ID -> 400
assert_http_status "Gecersiz product UUID -> 400" "400" "http://localhost:8080/orders" "POST" \
    '{"customerId":"22222222-2222-2222-2222-222222222222","items":[{"productId":"bad-uuid","quantity":1,"price":10.00}]}'

# Test 3.9: Gecersiz JSON body -> 400
assert_http_status "Gecersiz JSON -> 400" "400" "http://localhost:8080/orders" "POST" \
    'this is not json'

# Test 3.10: Yanlis HTTP method -> 405
TOTAL=$((TOTAL + 1))
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/orders)
if [ "$STATUS" = "405" ]; then
    echo -e "  ${GREEN}PASS${NC} [$TOTAL] GET /orders -> 405 Method Not Allowed"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} [$TOTAL] GET /orders -> 405 (got $STATUS)"
    FAIL=$((FAIL + 1))
fi

# Test 3.11: JSON Content-Type header kontrolu
BODY=$(curl -s -X POST http://localhost:8080/orders -H "Content-Type: application/json" \
    -d '{"customerId":"22222222-2222-2222-2222-222222222222","items":[]}')
CT=$(curl -s -o /dev/null -w "%{content_type}" -X POST http://localhost:8080/orders \
    -H "Content-Type: application/json" \
    -d '{"customerId":"22222222-2222-2222-2222-222222222222","items":[]}')
assert_contains "Error response Content-Type JSON iceriyor" "application/json" "$CT"

# =============================================================================
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}  BOLUM 4: SEED DATA DOGRULAMASI         ${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 4.1: StockService seed data - 2 urun var
PRODUCT_COUNT=$(docker exec stock_db psql -U user -d stock_db -t -c 'SELECT COUNT(*) FROM "Products"' | tr -d ' ')
assert_eq "StockService 2 urun seed edilmis" "2" "$PRODUCT_COUNT"

# Test 4.2: Test Product 1 stok miktari
STOCK1=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT \"StockQuantity\" FROM \"Products\" WHERE \"Name\"='Test Product 1'" | tr -d ' ')
assert_eq "Test Product 1 baslangic stogu 1000000" "1000000" "$STOCK1"

# Test 4.3: Test Product 2 stok miktari
STOCK2=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT \"StockQuantity\" FROM \"Products\" WHERE \"Name\"='Test Product 2'" | tr -d ' ')
assert_eq "Test Product 2 baslangic stogu 1000000" "1000000" "$STOCK2"

# Test 4.4: OrderService seed data - ornek siparis var
ORDER_COUNT=$(docker exec order_db psql -U user -d order_db -t -c 'SELECT COUNT(*) FROM orders' | tr -d ' ')
assert_eq "OrderService 1 ornek siparis seed edilmis" "1" "$ORDER_COUNT"

# Test 4.5: OrderService seed items
ITEM_COUNT=$(docker exec order_db psql -U user -d order_db -t -c 'SELECT COUNT(*) FROM order_items' | tr -d ' ')
assert_eq "OrderService 2 ornek siparis kalemi seed edilmis" "2" "$ITEM_COUNT"

# =============================================================================
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}  BOLUM 5: OUTBOX/INBOX UCTAN UCA AKIS   ${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 5.1: Siparis olusturma -> 201
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:8080/orders \
    -H "Content-Type: application/json" \
    -d '{"customerId":"22222222-2222-2222-2222-222222222222","items":[{"productId":"f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c","quantity":3,"price":10.00},{"productId":"a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d","quantity":2,"price":5.00}]}')
HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -1)
assert_eq "Siparis olusturma -> 201 Created" "201" "$HTTP_STATUS"

# Test 5.2: Response'da orderId var
assert_contains "Response orderId iceriyor" "orderId" "$BODY"

# Test 5.3: Response'da mesaj var
assert_contains "Response Outbox mesaji iceriyor" "Outbox" "$BODY"

# Test 5.4: Order DB'de siparis kaydi olusmus
ORDER_ID=$(echo "$BODY" | grep -o '"orderId":"[^"]*"' | cut -d'"' -f4)
sleep 2
DB_ORDER=$(docker exec order_db psql -U user -d order_db -t -c "SELECT COUNT(*) FROM orders WHERE id='$ORDER_ID'" | tr -d ' ')
assert_eq "Order DB'de siparis kaydi var" "1" "$DB_ORDER"

# Test 5.5: Order items DB'de var (2 kalem)
DB_ITEMS=$(docker exec order_db psql -U user -d order_db -t -c "SELECT COUNT(*) FROM order_items WHERE order_id='$ORDER_ID'" | tr -d ' ')
assert_eq "Order DB'de 2 siparis kalemi var" "2" "$DB_ITEMS"

# Test 5.6: Outbox mesaji olusturulmus
OUTBOX_COUNT=$(docker exec order_db psql -U user -d order_db -t -c "SELECT COUNT(*) FROM outbox_messages WHERE aggregate_id='$ORDER_ID'" | tr -d ' ')
assert_eq "Outbox mesaji olusturulmus" "1" "$OUTBOX_COUNT"

# Outbox relay ve StockService isleme icin bekle
echo -e "\n  ${YELLOW}... Outbox relay + StockService isleme icin 12 saniye bekleniyor ...${NC}\n"
sleep 12

# Test 5.7: Outbox mesaji 'Sent' durumunda
OUTBOX_STATUS=$(docker exec order_db psql -U user -d order_db -t -c "SELECT status FROM outbox_messages WHERE aggregate_id='$ORDER_ID'" | tr -d ' ')
assert_eq "Outbox mesaji 'Sent' durumunda" "Sent" "$OUTBOX_STATUS"

# Test 5.8: Inbox mesaji 'Processed' durumunda
INBOX_STATUS=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT \"Status\" FROM \"InboxMessages\" ORDER BY \"ReceivedOn\" DESC LIMIT 1" | tr -d ' ')
assert_eq "Inbox mesaji 'Processed' durumunda" "Processed" "$INBOX_STATUS"

# Test 5.9: Test Product 1 stogu azalmis (1000000 - 3 = 999997)
STOCK1_AFTER=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT \"StockQuantity\" FROM \"Products\" WHERE \"Name\"='Test Product 1'" | tr -d ' ')
assert_eq "Test Product 1 stogu 999997 (3 adet dusmus)" "999997" "$STOCK1_AFTER"

# Test 5.10: Test Product 2 stogu azalmis (1000000 - 2 = 999998)
STOCK2_AFTER=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT \"StockQuantity\" FROM \"Products\" WHERE \"Name\"='Test Product 2'" | tr -d ' ')
assert_eq "Test Product 2 stogu 999998 (2 adet dusmus)" "999998" "$STOCK2_AFTER"

# =============================================================================
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}  BOLUM 6: COKLU SIPARIS TESTI           ${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 6.1-6.3: 3 ardi ardina siparis
for i in 1 2 3; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/orders \
        -H "Content-Type: application/json" \
        -d "{\"customerId\":\"22222222-2222-2222-2222-222222222222\",\"items\":[{\"productId\":\"f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c\",\"quantity\":1,\"price\":10.00}]}")
    assert_eq "Ardisik siparis #$i -> 201" "201" "$STATUS"
done

echo -e "\n  ${YELLOW}... 3 siparisin islenmesi icin 20 saniye bekleniyor ...${NC}\n"
sleep 20

# Test 6.4: 3 ek siparisin stok etkisi (999997 - 3 = 999994)
STOCK1_MULTI=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT \"StockQuantity\" FROM \"Products\" WHERE \"Name\"='Test Product 1'" | tr -d ' ')
assert_eq "Coklu siparis sonrasi stok 999994 (toplam 6 dusus)" "999994" "$STOCK1_MULTI"

# Test 6.5: Toplam inbox mesaj sayisi (1 onceki + 3 yeni = 4)
INBOX_TOTAL=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT COUNT(*) FROM \"InboxMessages\"" | tr -d ' ')
assert_eq "Toplam 4 inbox mesaji islenmis" "4" "$INBOX_TOTAL"

# Test 6.6: Tum inbox mesajlari Processed
PROCESSED_COUNT=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT COUNT(*) FROM \"InboxMessages\" WHERE \"Status\"='Processed'" | tr -d ' ')
assert_eq "4 inbox mesajinin hepsi Processed" "4" "$PROCESSED_COUNT"

# =============================================================================
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}  BOLUM 7: YETERSIZ STOK (BUSINESS ERR)  ${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 7.1: Yetersiz stok siparisi olustur (2M adet)
curl -s -X POST http://localhost:8080/orders -H "Content-Type: application/json" \
    -d '{"customerId":"22222222-2222-2222-2222-222222222222","items":[{"productId":"f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c","quantity":2000000,"price":10.00}]}' > /dev/null

echo -e "\n  ${YELLOW}... Yetersiz stok siparisinin islenmesi icin 12 saniye bekleniyor ...${NC}\n"
sleep 12

# Test 7.2: Inbox'ta 'Failed' mesaj var
FAILED_COUNT=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT COUNT(*) FROM \"InboxMessages\" WHERE \"Status\"='Failed'" | tr -d ' ')
assert_eq "Yetersiz stok mesaji 'Failed' olarak isaretlenmis" "1" "$FAILED_COUNT"

# Test 7.3: Stok degismemis (hala 999994)
STOCK1_UNCHANGED=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT \"StockQuantity\" FROM \"Products\" WHERE \"Name\"='Test Product 1'" | tr -d ' ')
assert_eq "Yetersiz stok sonrasi stok degismedi (999994)" "999994" "$STOCK1_UNCHANGED"

# =============================================================================
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}  BOLUM 8: GRACEFUL SHUTDOWN              ${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 8.1: OrderService graceful shutdown
docker compose stop order_service > /dev/null 2>&1
SHUTDOWN_LOG=$(docker compose logs order_service --tail 5 2>&1)
assert_contains "Shutdown log 'Shutting down' iceriyor" "Shutting down" "$SHUTDOWN_LOG"

# Test 8.2: Relayer duzgun kapandi
assert_contains "Relayer 'shutting down' iceriyor" "Relayer shutting down" "$SHUTDOWN_LOG"

# Test 8.3: OrderService stopped mesaji
assert_contains "OrderService stopped mesaji" "OrderService stopped" "$SHUTDOWN_LOG"

# Test 8.4: Tekrar baslatma
docker compose start order_service > /dev/null 2>&1
sleep 15
HEALTH_AFTER=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health)
assert_eq "Restart sonrasi health -> 200" "200" "$HEALTH_AFTER"

# =============================================================================
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}  BOLUM 9: DATABASE SCHEMA DOGRULAMASI    ${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 9.1: order_db tablolari
TABLES_ORDER=$(docker exec order_db psql -U user -d order_db -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'" | tr -d ' ')
assert_eq "order_db 3 tablo var (orders, order_items, outbox_messages)" "3" "$TABLES_ORDER"

# Test 9.2: stock_db tablolari
TABLES_STOCK=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'" | tr -d ' ')
assert_eq "stock_db 3 tablo var (Products, InboxMessages, __EFMigrationsHistory)" "3" "$TABLES_STOCK"

# Test 9.3: outbox_messages index (status, occurred_on)
IDX_OUTBOX=$(docker exec order_db psql -U user -d order_db -t -c "SELECT COUNT(*) FROM pg_indexes WHERE tablename='outbox_messages' AND indexname='idx_outbox_status'" | tr -d ' ')
assert_eq "outbox_messages status indexi var" "1" "$IDX_OUTBOX"

# Test 9.4: InboxMessages.Status indexi
IDX_INBOX_STATUS=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT COUNT(*) FROM pg_indexes WHERE tablename='InboxMessages' AND indexname='IX_InboxMessages_Status'" | tr -d ' ')
assert_eq "InboxMessages Status indexi var" "1" "$IDX_INBOX_STATUS"

# Test 9.5: InboxMessages.ReceivedOn indexi
IDX_INBOX_RECEIVED=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT COUNT(*) FROM pg_indexes WHERE tablename='InboxMessages' AND indexname='IX_InboxMessages_ReceivedOn'" | tr -d ' ')
assert_eq "InboxMessages ReceivedOn indexi var" "1" "$IDX_INBOX_RECEIVED"

# Test 9.6: InboxMessages.MessageId unique indexi
IDX_INBOX_MID=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT COUNT(*) FROM pg_indexes WHERE tablename='InboxMessages' AND indexname='IX_InboxMessages_MessageId'" | tr -d ' ')
assert_eq "InboxMessages MessageId unique indexi var" "1" "$IDX_INBOX_MID"

# Test 9.7: EF Migration history dogru
MIG_COUNT=$(docker exec stock_db psql -U user -d stock_db -t -c "SELECT COUNT(*) FROM \"__EFMigrationsHistory\"" | tr -d ' ')
assert_eq "2 EF migration uygulanmis" "2" "$MIG_COUNT"

# =============================================================================
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}  BOLUM 10: STRUCTURED LOGGING            ${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 10.1: OrderService JSON log formati
ORDER_LOG=$(docker compose logs order_service --tail 1 2>&1 | grep -o '{.*}' | head -1)
assert_contains "OrderService JSON log formati" "time" "$ORDER_LOG"

# Test 10.2: OrderService log'da level alani var
assert_contains "OrderService log'da level alani" "level" "$ORDER_LOG"

# Test 10.3: StockService structured logging kullaniliyor
STOCK_LOG=$(docker compose logs stock_service 2>&1 | grep "info:" | head -1)
assert_contains "StockService structured log (info:)" "info:" "$STOCK_LOG"

# =============================================================================
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}  BOLUM 11: DOCKER GUVENLIGI              ${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 11.1: OrderService non-root kullanici
ORDER_USER=$(docker exec order_service whoami 2>&1)
assert_eq "OrderService non-root (appuser)" "appuser" "$ORDER_USER"

# Test 11.2: StockService non-root kullanici
STOCK_USER=$(docker exec stock_service whoami 2>&1)
TOTAL=$((TOTAL + 1))
if [ "$STOCK_USER" != "root" ]; then
    echo -e "  ${GREEN}PASS${NC} [$TOTAL] StockService non-root ($STOCK_USER)"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} [$TOTAL] StockService root olarak calisiyor"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}        SONUC RAPORU                      ${NC}"
echo -e "${YELLOW}========================================${NC}\n"

echo -e "  Toplam: $TOTAL"
echo -e "  ${GREEN}Gecen:${NC}  $PASS"
echo -e "  ${RED}Kalan:${NC}  $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "  ${GREEN}TUM TESTLER BASARILI!${NC}"
    exit 0
else
    echo -e "  ${RED}$FAIL TEST BASARISIZ!${NC}"
    exit 1
fi
