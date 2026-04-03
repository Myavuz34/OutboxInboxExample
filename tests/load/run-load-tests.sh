#!/bin/bash
# =============================================================================
# Load Test Orkestrasyon Scripti
# =============================================================================
# Kullanim:
#   bash tests/load/run-load-tests.sh              # E2E + Stress (varsayilan)
#   bash tests/load/run-load-tests.sh --test=e2e    # Sadece E2E pipeline
#   bash tests/load/run-load-tests.sh --test=stress  # Sadece stress
#   bash tests/load/run-load-tests.sh --clean        # Temiz baslangic
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

TEST_TYPE="all"
CLEAN=false
DRAIN_TIMEOUT=180
DRAIN_INTERVAL=5
POST_DRAIN_WAIT=30

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

for arg in "$@"; do
    case $arg in
        --test=*) TEST_TYPE="${arg#*=}" ;;
        --clean) CLEAN=true ;;
    esac
done

log() { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] UYARI:${NC} $1"; }
err() { echo -e "${RED}[$(date +%H:%M:%S)] HATA:${NC} $1"; }

# =============================================================================
# 1. Onkosul kontrolu
# =============================================================================
log "Docker kontrolu..."
if ! docker info > /dev/null 2>&1; then
    err "Docker calismiyir. Docker Desktop'i baslatin."
    exit 1
fi

# =============================================================================
# 2. Temiz baslangic (opsiyonel)
# =============================================================================
if [ "$CLEAN" = true ]; then
    log "Temiz baslangic: docker compose down -v && up --build -d"
    cd "$PROJECT_DIR"
    docker compose down -v > /dev/null 2>&1 || true
    docker compose up --build -d 2>&1 | tail -5
    log "Servislerin hazir olmasi bekleniyor (max 60s)..."
    for i in $(seq 1 60); do
        if curl -sf http://localhost:8080/health > /dev/null 2>&1 && \
           curl -sf http://localhost:8081/health > /dev/null 2>&1; then
            log "Tum servisler hazir."
            break
        fi
        if [ "$i" = "60" ]; then
            err "Servisler 60 saniyede hazir olamadi."
            docker compose ps
            exit 1
        fi
        sleep 1
    done
fi

# =============================================================================
# 3. Servis sagligi kontrolu
# =============================================================================
log "Servis sagligi kontrolu..."
if ! curl -sf http://localhost:8080/health > /dev/null 2>&1; then
    err "OrderService (localhost:8080) ulasılamıyor."
    err "Once 'docker compose up --build -d' calistirin veya --clean ekleyin."
    exit 1
fi
if ! curl -sf http://localhost:8081/health > /dev/null 2>&1; then
    err "StockService (localhost:8081) ulasılamıyor."
    exit 1
fi
log "OrderService ve StockService saglikli."

# =============================================================================
# 4. Pre-test durum kaydi
# =============================================================================
log "Pre-test durum kaydediliyor..."
PRE_STOCK_P1=$(docker exec stock_db psql -U user -d stock_db -t -c \
    "SELECT \"StockQuantity\" FROM \"Products\" WHERE \"Name\" = 'Test Product 1'" | tr -d ' ')
PRE_STOCK_P2=$(docker exec stock_db psql -U user -d stock_db -t -c \
    "SELECT \"StockQuantity\" FROM \"Products\" WHERE \"Name\" = 'Test Product 2'" | tr -d ' ')
PRE_ORDERS=$(docker exec order_db psql -U user -d order_db -t -c \
    "SELECT COUNT(*) FROM orders" | tr -d ' ')
PRE_OUTBOX=$(docker exec order_db psql -U user -d order_db -t -c \
    "SELECT COUNT(*) FROM outbox_messages" | tr -d ' ')
PRE_INBOX=$(docker exec stock_db psql -U user -d stock_db -t -c \
    "SELECT COUNT(*) FROM \"InboxMessages\"" | tr -d ' ')

echo -e "\n${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║       PRE-TEST DURUM                                 ║${NC}"
echo -e "${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "  Product 1 Stok:    $PRE_STOCK_P1"
echo -e "  Product 2 Stok:    $PRE_STOCK_P2"
echo -e "  Mevcut Siparis:    $PRE_ORDERS"
echo -e "  Mevcut Outbox:     $PRE_OUTBOX"
echo -e "  Mevcut Inbox:      $PRE_INBOX"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}\n"

# =============================================================================
# 5. k6 calistirma fonksiyonu
# =============================================================================
run_k6() {
    local script_name="$1"
    local display_name="$2"

    log "k6 calistiriliyor: $display_name"
    log "Script: $script_name"
    echo ""

    MSYS_NO_PATHCONV=1 docker run --rm \
        -e ORDER_SERVICE_URL=http://host.docker.internal:8080 \
        -v "$(cd "$SCRIPT_DIR" && pwd):/scripts:ro" \
        grafana/k6 run "/scripts/$script_name" 2>&1

    echo ""
    log "$display_name tamamlandi."
}

# =============================================================================
# 6. Pipeline drain bekleme
# =============================================================================
wait_for_drain() {
    log "Outbox pipeline drain bekleniyor (max ${DRAIN_TIMEOUT}s)..."
    local elapsed=0
    while [ $elapsed -lt $DRAIN_TIMEOUT ]; do
        PENDING=$(docker exec order_db psql -U user -d order_db -t -c \
            "SELECT COUNT(*) FROM outbox_messages WHERE status = 'Pending'" | tr -d ' ')
        if [ "$PENDING" = "0" ]; then
            log "Outbox tamamen drain oldu (${elapsed}s)."
            break
        fi
        echo -ne "\r  Pending: $PENDING mesaj bekliyor... (${elapsed}s/${DRAIN_TIMEOUT}s)"
        sleep $DRAIN_INTERVAL
        elapsed=$((elapsed + DRAIN_INTERVAL))
    done
    echo ""

    if [ "$PENDING" != "0" ]; then
        warn "Outbox $PENDING mesaj hala Pending (timeout: ${DRAIN_TIMEOUT}s)"
    fi

    # Consumer'in tum mesajlari islemesini bekle
    log "StockService consumer isleme bekleniyor..."
    local consumer_wait=0
    local consumer_max=120
    local target_inbox
    target_inbox=$(docker exec order_db psql -U user -d order_db -t -c \
        "SELECT COUNT(*) FROM outbox_messages WHERE status = 'Sent'" | tr -d ' ')
    while [ $consumer_wait -lt $consumer_max ]; do
        local current_inbox=$(docker exec stock_db psql -U user -d stock_db -t -c \
            "SELECT COUNT(*) FROM \"InboxMessages\"" | tr -d ' ')
        if [ "$current_inbox" -ge "$target_inbox" ] 2>/dev/null; then
            log "Consumer tum mesajlari isledi: $current_inbox/$target_inbox (${consumer_wait}s)"
            break
        fi
        echo -ne "\r  Consumer: $current_inbox/$target_inbox islendi... (${consumer_wait}s/${consumer_max}s)  "
        sleep 5
        consumer_wait=$((consumer_wait + 5))
    done
    echo ""
    log "Pipeline drain tamamlandi."
}

# =============================================================================
# 7. Testleri calistir
# =============================================================================
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}  LOAD TEST BASLIYOR                    ${NC}"
echo -e "${YELLOW}========================================${NC}\n"

if [ "$TEST_TYPE" = "e2e" ] || [ "$TEST_TYPE" = "all" ]; then
    run_k6 "k6-e2e-pipeline.js" "E2E Pipeline Testi (20 RPS x 2dk)"
    wait_for_drain
    bash "$SCRIPT_DIR/verify-consistency.sh" \
        --initial-p1="$PRE_STOCK_P1" --initial-p2="$PRE_STOCK_P2"
fi

if [ "$TEST_TYPE" = "stress" ] || [ "$TEST_TYPE" = "all" ]; then
    # Stress testi oncesi guncel stok kaydet
    if [ "$TEST_TYPE" = "all" ]; then
        PRE_STOCK_P1=$(docker exec stock_db psql -U user -d stock_db -t -c \
            "SELECT \"StockQuantity\" FROM \"Products\" WHERE \"Name\" = 'Test Product 1'" | tr -d ' ')
        PRE_STOCK_P2=$(docker exec stock_db psql -U user -d stock_db -t -c \
            "SELECT \"StockQuantity\" FROM \"Products\" WHERE \"Name\" = 'Test Product 2'" | tr -d ' ')
    fi
    run_k6 "k6-stress.js" "Stress Testi (10->300 RPS)"
    wait_for_drain
    bash "$SCRIPT_DIR/verify-consistency.sh" \
        --initial-p1="$PRE_STOCK_P1" --initial-p2="$PRE_STOCK_P2"
fi

# =============================================================================
# 8. Son rapor
# =============================================================================
POST_STOCK_P1=$(docker exec stock_db psql -U user -d stock_db -t -c \
    "SELECT \"StockQuantity\" FROM \"Products\" WHERE \"Name\" = 'Test Product 1'" | tr -d ' ')
POST_STOCK_P2=$(docker exec stock_db psql -U user -d stock_db -t -c \
    "SELECT \"StockQuantity\" FROM \"Products\" WHERE \"Name\" = 'Test Product 2'" | tr -d ' ')
POST_ORDERS=$(docker exec order_db psql -U user -d order_db -t -c \
    "SELECT COUNT(*) FROM orders" | tr -d ' ')
TOTAL_NEW_ORDERS=$((POST_ORDERS - PRE_ORDERS))
TOTAL_STOCK_DEDUCTED_P1=$((${PRE_STOCK_P1%%[^0-9]*} - ${POST_STOCK_P1%%[^0-9]*}))
TOTAL_STOCK_DEDUCTED_P2=$((${PRE_STOCK_P2%%[^0-9]*} - ${POST_STOCK_P2%%[^0-9]*}))

echo -e "\n${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║       GENEL SONUC RAPORU                             ║${NC}"
echo -e "${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "  Test tipi:         $TEST_TYPE"
echo -e "  Yeni siparis:      $TOTAL_NEW_ORDERS"
echo -e "  P1 stok dususu:    $TOTAL_STOCK_DEDUCTED_P1 ($POST_STOCK_P1 kaldi)"
echo -e "  P2 stok dususu:    $TOTAL_STOCK_DEDUCTED_P2 ($POST_STOCK_P2 kaldi)"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}\n"

log "Tum load testler tamamlandi."
