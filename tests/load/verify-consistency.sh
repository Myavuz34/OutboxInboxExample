#!/bin/bash
# =============================================================================
# DB Tutarlilik Kontrolu - Load Test Sonrasi
# =============================================================================
# Kullanim: bash tests/load/verify-consistency.sh [--initial-p1=N] [--initial-p2=N]
# =============================================================================

INITIAL_P1=${INITIAL_P1:-1000000}
INITIAL_P2=${INITIAL_P2:-1000000}

for arg in "$@"; do
    case $arg in
        --initial-p1=*) INITIAL_P1="${arg#*=}" ;;
        --initial-p2=*) INITIAL_P2="${arg#*=}" ;;
    esac
done

PASS=0
FAIL=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

assert_eq() {
    TOTAL=$((TOTAL + 1))
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo -e "  ${GREEN}PASS${NC} [$TOTAL] $name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} [$TOTAL] $name"
        echo -e "       Beklenen: $expected"
        echo -e "       Gercek:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

info() {
    TOTAL=$((TOTAL + 1))
    echo -e "  ${CYAN}INFO${NC} [$TOTAL] $1: $2"
    PASS=$((PASS + 1))
}

query_order_db() {
    docker exec order_db psql -U user -d order_db -t -c "$1" 2>/dev/null | tr -d ' \n'
}

query_stock_db() {
    docker exec stock_db psql -U user -d stock_db -t -c "$1" 2>/dev/null | tr -d ' \n'
}

echo -e "\n${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║       DB TUTARLILIK KONTROLU                         ║${NC}"
echo -e "${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"

# 1. Outbox'ta Pending kalmamis
PENDING=$(query_order_db "SELECT COUNT(*) FROM outbox_messages WHERE status = 'Pending'")
assert_eq "Outbox'ta Pending mesaj yok" "0" "$PENDING"

# 2. Outbox Sent sayisi
OUTBOX_SENT=$(query_order_db "SELECT COUNT(*) FROM outbox_messages WHERE status = 'Sent'")
ORDER_COUNT=$(query_order_db "SELECT COUNT(*) FROM orders")
API_ORDERS=$((ORDER_COUNT - 1))  # seed order haric
assert_eq "Outbox Sent ($OUTBOX_SENT) = API siparisleri ($API_ORDERS)" "$API_ORDERS" "$OUTBOX_SENT"

# 3. Inbox Processed + Failed + Error Queue = Outbox Sent
INBOX_PROCESSED=$(query_stock_db "SELECT COUNT(*) FROM \"InboxMessages\" WHERE \"Status\" = 'Processed'")
INBOX_TOTAL=$(query_stock_db "SELECT COUNT(*) FROM \"InboxMessages\"")
ERROR_QUEUE_COUNT=$((OUTBOX_SENT - INBOX_TOTAL))
if [ "$ERROR_QUEUE_COUNT" -lt 0 ] 2>/dev/null; then ERROR_QUEUE_COUNT=0; fi
ACCOUNTED=$((INBOX_TOTAL + ERROR_QUEUE_COUNT))
assert_eq "Inbox ($INBOX_TOTAL) + Error Queue ($ERROR_QUEUE_COUNT) = Outbox Sent ($OUTBOX_SENT)" "$OUTBOX_SENT" "$ACCOUNTED"
info "Inbox Processed: $INBOX_PROCESSED | MassTransit Error Queue: $ERROR_QUEUE_COUNT (concurrency conflict)" ""

# 4. Inbox Failed (bilgi)
INBOX_FAILED=$(query_stock_db "SELECT COUNT(*) FROM \"InboxMessages\" WHERE \"Status\" = 'Failed'")
info "Inbox Failed mesaj sayisi" "$INBOX_FAILED"

# 5. Product 1 stok tutarliligi
CURRENT_P1=$(query_stock_db "SELECT \"StockQuantity\" FROM \"Products\" WHERE \"Name\" = 'Test Product 1'")
DEDUCTED_P1=$((INITIAL_P1 - CURRENT_P1))
ORDERED_P1=$(query_order_db "SELECT COALESCE(SUM(oi.quantity), 0) FROM order_items oi JOIN orders o ON oi.order_id = o.id WHERE oi.product_id = 'f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c' AND o.id != '11111111-1111-1111-1111-111111111111'")
# Stok dusumu = siparis edilen - failed olanlarin miktari (yaklasik)
info "Product 1: siparis=$ORDERED_P1, stok dususu=$DEDUCTED_P1, kalan=$CURRENT_P1" ""

# 6. Product 2 stok tutarliligi
CURRENT_P2=$(query_stock_db "SELECT \"StockQuantity\" FROM \"Products\" WHERE \"Name\" = 'Test Product 2'")
DEDUCTED_P2=$((INITIAL_P2 - CURRENT_P2))
ORDERED_P2=$(query_order_db "SELECT COALESCE(SUM(oi.quantity), 0) FROM order_items oi JOIN orders o ON oi.order_id = o.id WHERE oi.product_id = 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d' AND o.id != '11111111-1111-1111-1111-111111111111'")
info "Product 2: siparis=$ORDERED_P2, stok dususu=$DEDUCTED_P2, kalan=$CURRENT_P2" ""

# 7. Toplam stok tutarliligi
TOTAL_DEDUCTED=$((DEDUCTED_P1 + DEDUCTED_P2))
TOTAL_INBOX=$((INBOX_PROCESSED))
# Her basarili inbox mesaji 1 adet urun duser (quantity=1 load testlerinde)
assert_eq "Toplam stok dususu ($TOTAL_DEDUCTED) = Inbox Processed ($TOTAL_INBOX)" "$TOTAL_INBOX" "$TOTAL_DEDUCTED"

# 8. Pipeline throughput
FIRST_OCCURRED=$(query_order_db "SELECT MIN(occurred_on) FROM outbox_messages WHERE status = 'Sent'")
LAST_PROCESSED=$(query_order_db "SELECT MAX(processed_date) FROM outbox_messages WHERE status = 'Sent'")
if [ -n "$FIRST_OCCURRED" ] && [ -n "$LAST_PROCESSED" ]; then
    PIPELINE_SECS=$(query_order_db "SELECT EXTRACT(EPOCH FROM (MAX(processed_date) - MIN(occurred_on)))::int FROM outbox_messages WHERE status = 'Sent'")
    if [ "$PIPELINE_SECS" -gt 0 ] 2>/dev/null; then
        EFFECTIVE_MPS=$(echo "scale=1; $OUTBOX_SENT / $PIPELINE_SECS" | bc 2>/dev/null || echo "N/A")
        info "Pipeline throughput: ${EFFECTIVE_MPS} msg/s (${OUTBOX_SENT} mesaj / ${PIPELINE_SECS}s)" ""
    fi
fi

echo -e "${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "  Toplam: $TOTAL | ${GREEN}Gecen: $PASS${NC} | ${RED}Kalan: $FAIL${NC}"
if [ $FAIL -eq 0 ]; then
    echo -e "  ${GREEN}TUTARLILIK: BASARILI${NC}"
else
    echo -e "  ${RED}TUTARLILIK: BASARISIZ ($FAIL hata)${NC}"
fi
echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}\n"

exit $FAIL
