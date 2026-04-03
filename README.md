# Outbox/Inbox Pattern - Microservice Demo

Transactional Outbox (OrderService - Go) ve Inbox (StockService - .NET 9) pattern'lerini gosteren, Docker uzerinde uctan uca calistirilan bir microservice demo projesidir.

---

## Mimari

```
  Kullanici (curl / Postman)
          |
          | POST /orders
          v
  +-------------------+          +-------------------+          +-------------------+
  |  OrderService     |          |     RabbitMQ      |          |  StockService     |
  |  (Go)             |          |                   |          |  (.NET 9)         |
  |                   |          |   order_events    |          |                   |
  |  1. Order + Outbox|  ------> |   (topic exchange)|  ------> |  4. Inbox kontrol |
  |     ayni TX'de    |  Outbox  |                   |  consume |  5. Stok dusur    |
  |     DB'ye yaz     |  Relayer |                   |          |  6. Inbox guncelle|
  |                   |          |                   |          |                   |
  |  2. Outbox poll   |          |                   |          |                   |
  |  3. RabbitMQ'ya   |          |                   |          |                   |
  |     yayinla       |          |                   |          |                   |
  +--------+----------+          +-------------------+          +--------+----------+
           |                                                             |
           v                                                             v
  +-------------------+                                         +-------------------+
  |    order_db       |                                         |    stock_db       |
  |   (PostgreSQL)    |                                         |   (PostgreSQL)    |
  |                   |                                         |                   |
  |  - orders         |                                         |  - Products       |
  |  - order_items    |                                         |  - InboxMessages  |
  |  - outbox_messages|                                         |                   |
  +-------------------+                                         +-------------------+
```

### Akis Ozeti

1. Kullanici `POST /orders` ile siparis olusturur
2. OrderService, **order + outbox mesajini ayni database transaction'inda** kaydeder (atomik)
3. Outbox Relayer her 5 saniyede bekleyen mesajlari `SELECT FOR UPDATE SKIP LOCKED` ile alir
4. Mesajlar RabbitMQ `order_events` topic exchange'ine yayinlanir
5. StockService MassTransit consumer ile mesaji alir
6. **Inbox pattern** ile idempotency saglanir (ayni mesaj 2 kez islenmez)
7. Stok dusurulur, inbox mesaji "Processed" olarak isaretlenir

---

## Onkocullar

| Arac | Aciklama |
|------|----------|
| **Docker Desktop** | Docker Engine + Docker Compose V2 iceriyor |
| **curl** | Terminal'den API test icin (Windows'ta Git Bash ile gelir) |
| **Git Bash** | Windows'ta test scripti calistirmak icin (opsiyonel) |

> **Not:** Go, .NET SDK veya PostgreSQL kurmaniza gerek yok. Her sey Docker icinde calisir.

---

## Hizli Baslangic (3 Adim)

### Adim 1: Projeyi Klonla ve Klasore Gir

```bash
git clone <repo-url>
cd OutboxInboxExample
```

### Adim 2: Tum Servisleri Baslat

```bash
docker compose up --build -d
```

Bu komut:
- 2 PostgreSQL veritabani olusturur (order_db, stock_db)
- RabbitMQ mesaj broker'i baslatir
- OrderService (Go) build edip baslatir
- StockService (.NET 9) build edip baslatir
- Migration'lari otomatik uygular
- Seed data'lari yukler

> Ilk calistirmada image'lar indirilecegi icin **2-3 dakika** surebilir.

### Adim 3: Servislerin Hazir Oldugunu Dogrula

```bash
# Tum container'larin "healthy" oldugunu kontrol et
docker compose ps
```

Beklenen cikti (hepsi "healthy" olmali):
```
NAME            STATUS
order_db        Up (healthy)
stock_db        Up (healthy)
rabbitmq        Up (healthy)
order_service   Up (healthy)
stock_service   Up (healthy)
```

> **Onemli:** StockService'in "healthy" olmasi ~30 saniye surebilir (`start_period`). Bekleyin.

Health check endpoint'lerini test edin:
```bash
curl http://localhost:8080/health    # OrderService  -> {"status":"healthy"}
curl http://localhost:8081/health    # StockService  -> Healthy
```

---

## Demo Senaryolari

### Senaryo 1: Basarili Siparis Akisi

**Amac:** Outbox -> RabbitMQ -> Inbox -> Stok dusumu akisini gostermek.

```bash
# 1. Stok durumunu kontrol et (baslangic: 1.000.000)
docker exec stock_db psql -U user -d stock_db -c \
  'SELECT "Name", "StockQuantity" FROM "Products"'

# 2. Siparis olustur (2 adet Product 1, 1 adet Product 2)
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "22222222-2222-2222-2222-222222222222",
    "items": [
      {"productId": "f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c", "quantity": 2, "price": 10.00},
      {"productId": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d", "quantity": 1, "price": 5.00}
    ]
  }'

# Beklenen cikti:
# {"message":"Order created and event saved to Outbox.","orderId":"<uuid>"}

# 3. 10 saniye bekle (outbox relay + mesaj isleme)
sleep 10

# 4. Stok durumunu tekrar kontrol et (Product 1: 999998, Product 2: 999999)
docker exec stock_db psql -U user -d stock_db -c \
  'SELECT "Name", "StockQuantity" FROM "Products"'

# 5. Outbox mesajinin durumunu kontrol et (Sent olmali)
docker exec order_db psql -U user -d order_db -c \
  'SELECT id, type, status FROM outbox_messages ORDER BY occurred_on DESC LIMIT 1'

# 6. Inbox mesajinin durumunu kontrol et (Processed olmali)
docker exec stock_db psql -U user -d stock_db -c \
  'SELECT "MessageId", "Type", "Status" FROM "InboxMessages" ORDER BY "ReceivedOn" DESC LIMIT 1'
```

### Senaryo 2: Yetersiz Stok (Business Error)

**Amac:** Business hatalarin nasil yonetildigini gostermek.

```bash
# 2 milyon adet siparis ver (stok 1M, yetmez)
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "22222222-2222-2222-2222-222222222222",
    "items": [
      {"productId": "f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c", "quantity": 2000000, "price": 10.00}
    ]
  }'

sleep 10

# Inbox mesaji "Failed" olarak isaretlenmis olmali
docker exec stock_db psql -U user -d stock_db -c \
  'SELECT "Type", "Status", "ProcessedDate" FROM "InboxMessages" ORDER BY "ReceivedOn" DESC LIMIT 1'

# Stok degismemis olmali
docker exec stock_db psql -U user -d stock_db -c \
  'SELECT "Name", "StockQuantity" FROM "Products"'

# StockService loglarinda hata mesaji gorunur
docker compose logs stock_service --tail 10
```

### Senaryo 3: Input Validation

**Amac:** API validasyonlarinin calistigini gostermek.

```bash
# Bos siparis -> 400
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{"customerId": "22222222-2222-2222-2222-222222222222", "items": []}'
# -> {"error":"Order must contain at least one item"}

# Negatif miktar -> 400
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{"customerId": "22222222-2222-2222-2222-222222222222", "items": [{"productId": "f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c", "quantity": -1, "price": 10.00}]}'
# -> {"error":"Quantity must be positive at index 0"}

# Gecersiz UUID -> 400
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{"customerId": "gecersiz-uuid", "items": [{"productId": "f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c", "quantity": 1, "price": 10.00}]}'
# -> {"error":"Invalid customer ID format"}
```

### Senaryo 4: Graceful Shutdown

**Amac:** OrderService'in temiz kapandigini gostermek.

```bash
# Servisi durdur
docker compose stop order_service

# Loglarda temiz kapanis mesajlari gorunur
docker compose logs order_service --tail 5
# -> "Shutting down OrderService..."
# -> "Outbox Relayer shutting down"
# -> "OrderService stopped"

# Tekrar baslat
docker compose start order_service
```

### Senaryo 5: RabbitMQ Management UI

**Amac:** Mesaj akisini gorsel olarak izlemek.

1. Tarayicida ac: **http://localhost:15672**
2. Giris: `guest` / `guest`
3. **Exchanges** sekmesinde `order_events` topic exchange'ini gor
4. **Queues** sekmesinde `order_created_queue` kuyrugunu gor
5. Siparis olustur ve mesajin kuyruktan gecisini izle

---

## Otomatik Test Suite

60 test iceren kapsamli E2E test scripti dahildir.

### Testleri Calistirma

```bash
# Once servislerin ayakta ve hazir oldugunu dogrula
docker compose ps  # Hepsi "healthy" olmali

# Test scriptini calistir
bash tests/e2e_tests.sh
```

### Test Kapsami

| Bolum | Test | Aciklama |
|-------|------|----------|
| 1. Container Saglik | 6 test | 5 container calisiyor + hepsi healthy |
| 2. Health Endpoint | 4 test | /health 200 donuyor + response body |
| 3. Input Validation | 11 test | Bos items, negatif degerler, gecersiz UUID, yanlis method |
| 4. Seed Data | 5 test | 2 urun + 1 ornek siparis seed edilmis |
| 5. Outbox/Inbox Akis | 10 test | Siparis -> outbox -> RabbitMQ -> inbox -> stok dusumu |
| 6. Coklu Siparis | 6 test | 3 ardisik siparis, kumulatif stok etkisi |
| 7. Yetersiz Stok | 2 test | Business error -> inbox Failed, stok degismez |
| 8. Graceful Shutdown | 4 test | Temiz kapanis loglari + restart |
| 9. DB Schema | 7 test | Tablolar, index'ler, migration'lar |
| 10. Structured Logging | 3 test | JSON log formati (Go), structured log (.NET) |
| 11. Docker Guvenlik | 2 test | Non-root container'lar |

Beklenen cikti:
```
  Toplam: 60
  Gecen:  60
  Kalan:  0

  TUM TESTLER BASARILI!
```

---

## Servis Endpoint'leri ve Port'lar

| Servis | Port | URL | Aciklama |
|--------|------|-----|----------|
| OrderService | 8080 | http://localhost:8080/orders | POST - Siparis olustur |
| OrderService | 8080 | http://localhost:8080/health | GET - Saglik kontrolu |
| StockService | 8081 | http://localhost:8081/health | GET - Saglik kontrolu |
| RabbitMQ UI | 15672 | http://localhost:15672 | Web arayuzu (guest/guest) |
| order_db | 5434 | localhost:5434 | PostgreSQL (user/password) |
| stock_db | 5433 | localhost:5433 | PostgreSQL (user/password) |

### API Referansi

**POST /orders** - Siparis Olustur

Request:
```json
{
  "customerId": "22222222-2222-2222-2222-222222222222",
  "items": [
    {
      "productId": "f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c",
      "quantity": 2,
      "price": 10.00
    }
  ]
}
```

Basarili Response (201):
```json
{
  "orderId": "5f72d8de-c6f1-4bc2-a0dd-a86631683bde",
  "message": "Order created and event saved to Outbox."
}
```

Hata Response (400):
```json
{
  "error": "Order must contain at least one item"
}
```

### Kullanilabilir Urun ID'leri (Seed Data)

| Urun | Product ID | Fiyat | Baslangic Stok |
|------|-----------|-------|----------------|
| Test Product 1 | `f0e5b7c8-d1a2-3e4f-5b6c-7d8e9f0a1b2c` | $10.00 | 1.000.000 |
| Test Product 2 | `a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d` | $5.00 | 1.000.000 |

---

## Veritabani Sorgulari (Debug/Demo)

```bash
# Order DB - Siparisler
docker exec order_db psql -U user -d order_db -c 'SELECT id, customer_id, status, total_amount FROM orders'

# Order DB - Siparis kalemleri
docker exec order_db psql -U user -d order_db -c 'SELECT order_id, product_id, quantity, price FROM order_items'

# Order DB - Outbox mesajlari
docker exec order_db psql -U user -d order_db -c 'SELECT id, type, status, occurred_on FROM outbox_messages ORDER BY occurred_on DESC'

# Stock DB - Urun stoklari
docker exec stock_db psql -U user -d stock_db -c 'SELECT "Name", "StockQuantity", "Price" FROM "Products"'

# Stock DB - Inbox mesajlari
docker exec stock_db psql -U user -d stock_db -c 'SELECT "MessageId", "Type", "Status", "ReceivedOn" FROM "InboxMessages" ORDER BY "ReceivedOn"'
```

---

## Log Izleme

```bash
# Tum servislerin loglari (canli)
docker compose logs -f

# Sadece OrderService (JSON formatinda)
docker compose logs -f order_service

# Sadece StockService
docker compose logs -f stock_service

# Son 20 satir
docker compose logs --tail 20 order_service
```

OrderService JSON log ornegi:
```json
{"time":"2026-04-03T10:10:03Z","level":"INFO","msg":"Order created","order_id":"5f72d8de-..."}
{"time":"2026-04-03T10:10:05Z","level":"INFO","msg":"Outbox Relayer message sent","message_id":"4967493c-...","type":"OrderCreated"}
```

---

## Yeniden Baslatma ve Temizlik

```bash
# Servisleri durdur (veri korunur)
docker compose down

# Servisleri durdur + tum verileri sil (temiz baslangic)
docker compose down -v

# Sadece bir servisi yeniden baslat
docker compose restart order_service

# Image'lari yeniden build et ve baslat
docker compose up --build -d
```

---

## Sorun Giderme

### Servis baslamiyor / restart dongusu

```bash
# Loglari kontrol et
docker compose logs stock_service --tail 50

# Tum container durumlarini gor
docker compose ps -a
```

### Port cakismasi

Eger 8080, 8081, 5672, 15672, 5433 veya 5434 portlarindan biri kullaniliyorsa:

```bash
# Hangi islem portu kullaniyor?
# Windows:
netstat -ano | findstr :8080
# Linux/Mac:
lsof -i :8080
```

Cozum: Cakisan uygulamayi kapatin veya `docker-compose.yml`'deki port mapping'i degistirin.

### Temiz baslangic

```bash
docker compose down -v
docker compose up --build -d
```

### StockService "unhealthy"

StockService'in baslamasi ~30 saniye surebilir. 40 saniye bekleyin, hala "unhealthy" ise loglari kontrol edin:

```bash
docker compose logs stock_service --tail 30
```

---

## Proje Yapisi

```
OutboxInboxExample/
├── OrderService/                   # Go - Transactional Outbox Pattern
│   ├── main.go                     # Uygulama baslangic noktasi, graceful shutdown
│   ├── config/config.go            # Ortam degiskeni yonetimi
│   ├── Dockerfile                  # Multi-stage build, non-root, ca-certs
│   ├── .dockerignore
│   ├── internal/
│   │   ├── api/handlers.go         # HTTP handler (POST /orders, GET /health)
│   │   ├── application/
│   │   │   ├── order_service.go    # Siparis olusturma (atomic TX)
│   │   │   ├── outbox_relayer.go   # Polling + publish (FOR UPDATE SKIP LOCKED)
│   │   │   └── ports/              # Repository & publisher interface'leri
│   │   ├── domain/                 # Order, Event, OutboxMessage, status constants
│   │   └── infrastructure/
│   │       ├── postgres/           # OrderRepository, OutboxRepository, DB connection
│   │       └── rabbitmq/           # EventPublisher, channel factory
│   └── db/migrations/
│       ├── 001_init.sql            # Schema: orders, order_items, outbox_messages
│       └── 002_seed_data.sql       # Ornek siparis verisi
│
├── StockService/                   # .NET 9 - Inbox Pattern
│   ├── Program.cs                  # WebApplication, migration, seed, health check
│   ├── StockService.csproj         # Dependency'ler
│   ├── Dockerfile                  # Multi-stage build, non-root, curl icin apt
│   ├── appsettings.json            # DB + RabbitMQ konfigurasyonu
│   ├── Application/
│   │   └── Interfaces/             # IInboxService, IStockDeductionService
│   ├── Domain/
│   │   ├── Product.cs              # Urun entity (RowVersion ile optimistic concurrency)
│   │   ├── InboxMessage.cs         # Inbox entity
│   │   └── InboxStatus.cs          # Status constant'lari
│   ├── Events/
│   │   └── OrderCreatedEvent.cs    # Integration event (record type)
│   ├── Infrastructure/
│   │   ├── Data/StockDbContext.cs   # EF Core context + index konfigurasyonu
│   │   ├── MassTransit/
│   │   │   ├── RabbitMqConfigurator.cs      # MassTransit + RabbitMQ DI setup
│   │   │   └── Consumers/
│   │   │       └── OrderCreatedConsumer.cs  # Inbox + stok dusumu orkestrasyonu
│   │   └── Services/
│   │       ├── InboxService.cs              # IInboxService implementasyonu
│   │       └── StockDeductionService.cs     # IStockDeductionService implementasyonu
│   └── Migrations/                 # EF Core migration'lar (InitialCreate + AddIndexes)
│
├── tests/
│   └── e2e_tests.sh               # 60 test senaryo (bash)
│
├── docker-compose.yml              # 5 servis orkestrasyonu
├── docker-compose.override.yml     # Local dev override (Development mode)
├── .env                            # Ortam degiskenleri (git'e commit edilmez)
├── .gitignore
├── .dockerignore
└── README.md                       # Bu dosya
```
