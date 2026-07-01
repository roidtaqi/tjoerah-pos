# Tjoerah POS - Flutter UI/UX & POS Module Architecture

The Frontend is built in Flutter to target Android natively while maintaining a single codebase for future iOS and Web ports. The UX prioritizes "Enterprise Minimalism", ensuring fast cashier workflows with minimal taps, massive touch targets, and robust offline state handling.

## 1. Feature-Based Folder Structure

```
lib/
├── core/
│   ├── theme/          # Inter font, Enterprise Color System
│   ├── network/        # Dio config, interceptors
│   ├── database/       # sqflite setup, Daos
│   └── sync/           # Background sync queues
├── shared/
│   ├── components/     # AppButton, AppBottomSheet, AppMetricCard
│   ├── utils/
│   └── models/
└── features/
    ├── auth/           # Login, PIN Lock
    ├── dashboard/      # Owner metrics
    ├── pos/            # Catalog, Cart, Payment, Table Select
    ├── kds/            # Kanban display
    ├── inventory/      # Stock movements, alerts
    └── customers/      # CRM
```

## 2. Design System & Theme Architecture

**Visual Identity**: Enterprise Minimalism (clean, spacious, large targets).
- **Typography**: `Inter` via Google Fonts. (Headings bold, Body regular, Captions muted).
- **Colors**:
  - `Primary`: `Color(0xFF0F172A)` (Slate 900 - Black/Dark Gray)
  - `Background`: `Color(0xFFF8FAFC)` (Slate 50 - Off white)
  - `Surface`: `Color(0xFFFFFFFF)` (Pure White)
  - `Status`: `Green (Success)`, `Amber (Warning)`, `Red (Danger)`, `Blue (Info)`

**Components**:
- `AppBottomSheet`: Avoids full-page navigation for Modifiers, Payment types, and Customer Additions. Keeps the POS context visible behind the modal.
- `AppMetricCard`: Used in Owner/Area Manager views.
- `AppSearchBar`: Always visible, heavily optimized debounce for local SQLite querying.

## 3. Role-Based Navigation Architecture

Utilize `go_router` combined with a `RoleShellRoute` that dynamically generates the Bottom Navigation Bar based on the authenticated JWT Role.

| Role | Bottom Navigation Tabs | Home Screen (Index 0) |
| :--- | :--- | :--- |
| **Owner** | Dashboard, Operations, Inventory, Analytics, More | Executive Dashboard |
| **Area Manager** | Dashboard, Outlets, Inventory, Reports, More | Outlet Monitoring Dashboard |
| **Outlet Manager** | POS, Operations, Inventory, Reports, More | POS Screen |
| **Cashier** | POS, Orders, Customers, More | POS Screen (No Dashboard) |

## 4. POS Module Architecture & User Flow

The POS screen is the heart of the operational layer. Target completion time for checkout + payment is `< 1 second` UI responsiveness.

### Order Type Entry
`Cashier Login -> Prompt: Dine In / Take Away / Delivery -> POS Screen`

### Layout Strategy
- **Header**: Active Outlet, Cashier Name, Sync Status (Green Dot = Online, Gray = Offline).
- **Left/Top Pane**: Universal Search Bar + Horizontal Category Chips (`Coffee`, `Food`, `Dessert`).
- **Main Area**: Massive Product Grid. Clicking a product with variants/modifiers instantly pulls up an `AppBottomSheet`.
- **Right Pane / Bottom Cart**: 
  - On **Tablet** (Landscape): Persistent right-side Cart.
  - On **Phone**: Persistent Floating Bottom Bar showing Total & Quantity, which expands into a full sheet when tapped.

### State Management
Use `Riverpod` or `Provider` (specifically `NotifierProvider`) for Cart state management.
- `CartNotifier`: Holds `List<OrderItem>`, `Discount`, `TaxRate`, `Customer`.
- Methods: `addItem`, `updateQuantity`, `applyDiscount`, `splitBill`.

## 5. Table Management Flow

For Dine-In, a Visual Floor Plan renders using a draggable `Stack` of `Positioned` table widgets.
- **Statuses**: `Available (Gray)`, `Occupied (Red)`, `Reserved (Amber)`, `Cleaning (Blue)`.
- **Features**: Press and hold to drag a table onto another to `Merge`, or select a table to `Transfer` the bill.

## 6. Payment Architecture

When `Pay` is pressed, open an `AppBottomSheet` displaying massive buttons:
`Cash`, `QRIS`, `Debit`, `Credit Card`, `Split`.

**Split Payment Logic**:
If Total = `125,000`. User selects `Split`.
- Enter `Cash: 50,000`. Remaining = `75,000`.
- Enter `QRIS: 75,000`. Remaining = `0`.
- Confirm Payment -> Generate `OrderCompletedEvent` locally -> Queue Sync -> Trigger Printer -> Route to KDS.

## 7. Responsive & Tablet Layout Strategy

The application employs a `LayoutBuilder` wrapper at the screen level.
- **Phone (< 600dp)**: Navigation on Bottom. Cart hidden in Bottom Sheet.
- **Tablet Portrait (600dp - 900dp)**: Navigation on Bottom. Cart hidden in Bottom Sheet but Product Grid displays 4-5 columns.
- **Tablet Landscape (> 900dp)**: Navigation shifted to `NavigationRail` (Left). Cart permanently pinned to the Right Side (30% width). Product grid occupies the center (70% width). All touch targets remain > `48dp`.
