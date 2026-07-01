# Tjoerah POS - Offline Sync Engine Architecture

The Offline Sync Engine guarantees that the POS application can continue full operational flow (taking orders, accepting cash payments, routing to KDS via local network) even if the internet drops entirely. Transactions are strictly preserved and synchronized when connectivity is restored.

## 1. Sync Architecture Diagram

```mermaid
graph TD
    subgraph "Flutter App (Local)"
        POS_UI[POS UI/UX]
        LocalDB[(SQLite Local Storage)]
        LocalQueue[Sync Queue Table]
        Worker[Background Sync Worker]
    end

    subgraph "Laravel Backend (Remote)"
        Gateway[API Gateway]
        SyncCtrl[Sync Controller]
        PG[(PostgreSQL Primary DB)]
    end

    POS_UI -->|1. Write (UUID)| LocalDB
    LocalDB -->|2. Trigger Event| LocalQueue
    Worker -->|3. Read Pending| LocalQueue
    Worker -->|4. Push Payload (Internet Restored)| Gateway
    Gateway --> SyncCtrl
    SyncCtrl -->|5. Upsert & Conflict Res| PG
    SyncCtrl -->|6. ACK Response| Worker
    Worker -->|7. Mark Completed| LocalQueue
```

## 2. Queue Schema (Local SQLite)

The `sync_queue` table acts as a Write-Ahead Log (WAL) on the device.

| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | UUID | Primary key for the queue item itself. |
| `entity_type` | String | e.g., `Order`, `Payment`, `Customer` |
| `entity_id` | UUID | The ID of the actual record being synced. |
| `operation` | String | `CREATE`, `UPDATE`, `DELETE`, `UPSERT` |
| `payload` | JSON | The exact data payload to send to the API. |
| `status` | String | `pending`, `processing`, `completed`, `failed` |
| `retries` | Integer | Count of failed attempts. |
| `created_at` | Timestamp | When the action occurred locally. |
| `synced_at` | Timestamp | When the server successfully processed it. |

## 3. Conflict Resolution Strategy

Conflicts arise when a record is modified both locally and on the server, or when multiple offline terminals attempt to modify the same centralized data.

- **Orders & Payments (Must-Sync 100%)**:
  - *Rule*: **Append Only (No Last Write Wins).** Once an order is created, modifications (like voiding) are recorded as separate events (e.g., `VoidTransactionEvent`). Orders use UUIDs generated on the client, ensuring the server can blindly `UPSERT` without PK collisions.
- **Inventory (Stock Movements)**:
  - *Rule*: **Event Sourcing Reconciliation.** You cannot rely on "Stock = 5" from the client. The client sends a `StockMovement` (e.g., `-2 lattes`). The server processes the movement sequentially against the central `average_cost` and absolute quantity.
- **Recipes & Products (Reference Data)**:
  - *Rule*: **Server Wins (Version Based).** The backend maintains a `version_number` on products. If the client tries to sync a product update but has an outdated version, the server rejects it. In practice, POS devices should act as *readers* for Reference Data, not writers.
- **Customers**:
  - *Rule*: **Latest Timestamp Wins.** If the POS updates a customer's phone offline, and the Owner Dashboard updates it online, the update with the most recent `created_at` timestamp prevails.

## 4. Retry Strategy & Error Handling

If a sync payload fails (500 Server Error or Timeout), the Flutter Sync Worker employs an Exponential Backoff strategy:
1. **Initial Failure**: Retry in 1 minute.
2. **Second Failure**: Retry in 5 minutes.
3. **Third Failure**: Retry in 15 minutes.
4. **Subsequent Failures**: Retry hourly up to 24 hours.

If a payload returns a `422 Unprocessable Entity` (e.g., invalid data format) or a `409 Conflict`, it is marked as `failed` and removed from the active retry queue to prevent queue blocking. It is instead logged to a "Failed Queue" requiring manual Owner intervention on the Dashboard.

## 5. Sync Data Categories

### Category A: Critical (Must Sync)
- **Examples**: `Order`, `OrderItem`, `Payment`, `Refund`, `VoidTransaction`
- **Behavior**: Local Write First. Sync queued immediately. Retries indefinitely.

### Category B: Operational (Sync When Possible)
- **Examples**: `Customer`, `AttendanceLog`, `KitchenTicketStatus`
- **Behavior**: Local Write First. Sync queued immediately. Will drop after 7 days of failure.

### Category C: Reference Data (Periodic Sync)
- **Examples**: `Product`, `Category`, `Modifier`, `Recipe`, `UserRoles`
- **Behavior**: Server-to-Client sync. The POS device polls `GET /sync/reference-data?since_version=X` upon application launch and every 15 minutes in the background, or receives WebSocket invalidation pings.

## 6. Sync Monitoring Dashboard (Owner View)

The Owner Dashboard must include a "Device Health" widget displaying:
- **Status**: Online / Offline
- **Pending Syncs**: Count of records waiting in the `sync_queue` for that device.
- **Failed Syncs**: Count of unresolvable conflicts.
- **Last Seen**: Timestamp of the last successful heartbeat or sync.

## 7. Data Integrity & Idempotency

- **Idempotency Keys**: The `entity_id` (UUID) combined with the `created_at` timestamp serves as an idempotency key on the backend. If the client successfully syncs an Order, but the network drops before it receives the ACK, it will retry. The server sees the same UUID, realizes it already processed it, and simply returns `200 OK` without duplicating the revenue.
- **Encryption**: The `payload` column in the SQLite `sync_queue` may contain sensitive customer data. It should be stored locally using `SQLCipher` (encrypted SQLite) to prevent extraction from stolen hardware.
