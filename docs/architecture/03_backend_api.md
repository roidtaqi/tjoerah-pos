# Tjoerah POS - Backend REST API Architecture

This document outlines the API Architecture built using Laravel 12. It employs Domain-Driven Design (DDD), robust queuing for heavy operations, and WebSockets for real-time KDS and reporting updates.

## 1. Domain-Driven Project Structure

Avoid standard Laravel MVC fat controllers. Structure the `app/` folder by domain:

```
app/
├── Domains/
│   ├── POS/
│   │   ├── Controllers/
│   │   ├── Services/       # Business logic (e.g., CreateOrderService)
│   │   ├── Repositories/   # DB interactions
│   │   ├── DTOs/           # Data Transfer Objects for validation
│   │   └── Events/         # e.g., OrderCompleted
│   ├── Inventory/
│   ├── Recipe/
│   ├── KDS/
│   ├── CRM/
│   └── Reporting/
├── Http/
│   ├── Middleware/
│   └── Requests/           # Standard FormRequests for payload validation
└── Console/
    └── Commands/
```

## 2. API Route Structure

All endpoints are prefixed with `/api/v1/`.

### Authentication & Authorization
- `POST /auth/login` (JWT Generation)
- `POST /auth/pin/login` (Cashier fast login via device token)
- `POST /auth/device/register` (Register a POS terminal)

### POS & Transactions
*The POS sync engine primarily hits the POST endpoints here using bulk upserts.*
- `GET /products` (Supports `?updated_since=` for delta syncs)
- `POST /sync/orders` (Bulk upload of offline orders. Accepts UUIDs.)
- `POST /orders/{id}/hold` (Suspend transaction)
- `POST /orders/{id}/void` (Void transaction with Reason required)
- `POST /orders/{id}/refund` (Process full/partial refund)

### Inventory
- `GET /inventory` (Current stock snapshot)
- `POST /inventory/adjustments` (Manual stock correct. Audit trail generated.)
- `POST /inventory/movements` (Transfer stock between warehouses)
- `POST /inventory/opname` (Submit stock counting results)

### Recipe & Costing
- `GET /recipes`
- `POST /recipes/version` (Create a new recipe version rather than mutating live ones)
- `GET /recipes/costing` (Trigger dynamic cost recalculation based on current supplier prices)

### CRM & Loyalty
- `GET /customers/search?q=` (Fast trigram search)
- `POST /customers`
- `POST /loyalty/earn` (Add points based on Order total)

### Reporting
- `GET /reports/sales?period=today&outlet_id=all`
- `GET /reports/inventory/low-stock`
- `GET /reports/profitability` (Aggregates COGS vs Revenue)

## 3. Event-Driven Architecture

Controllers must be thin. When an order syncs successfully, it fires an event. Listeners handle the cascading effects.

**Example Event Flow:**
1. `POSController@sync` receives offline orders.
2. Saves Order to DB.
3. Fires `OrderCompleted` event.

**Listeners attached to `OrderCompleted`:**
- `DeductInventoryListener`: Looks up Recipe, calculates raw materials used, and creates a `stock_movements` record (Queued).
- `CreateKDSTicketListener`: Reads order items, checks station routing, and broadcasts to WebSocket (Sync).
- `AwardLoyaltyPointsListener`: Updates CRM database (Queued).

## 4. Queue Architecture

Operations that would block the API response must be dispatched to Laravel Queues (Redis/Beanstalkd).

**Queued Jobs:**
- `RecalculateRecipeCostsJob`: Runs nightly or when a supplier invoice is received.
- `GenerateDailyReportJob`: Pre-aggregates daily sales into a materialized view for fast dashboard loading.
- `ProcessOfflineOrderSyncJob`: If a POS syncs 1,000 orders at once, the initial request is acknowledged (202 Accepted), and the payload is processed in the background.

## 5. Security Architecture

### Middleware
- `auth:api`: Validates the JWT.
- `tenant.scope`: Automatically detects the user's `outlet_id` or `company_id` from the JWT and applies a Laravel Global Scope to all Eloquent models, preventing cross-tenant data leaks.
- `role:manager`: Enforces RBAC permissions on sensitive routes (e.g., Reports, Inventory Adjustments).

### Rate Limiting & Auditing
- API Gateway rate limits applied per device.
- All mutating endpoints (POST, PUT, DELETE) pass through an `AuditTrailMiddleware` that logs the request payload and user ID for forensic tracing of voids and refunds.
