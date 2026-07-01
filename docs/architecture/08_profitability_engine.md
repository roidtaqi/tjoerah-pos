# Tjoerah POS - Profitability Engine Architecture

The Profitability Engine is the central intelligence layer of Tjoerah POS. Its primary goal is not to track sales, but to uncover the true net profit by linking the POS directly to the supply chain and costing engines.

## 1. Financial Data Model & Profitability Flow

Every transaction cascades through this engine:

`Supplier Invoice` -> `Inventory Valuation` -> `Recipe COGS` -> `Selling Price` -> `Gross Sales` -> `Discounts/Voids` -> `Net Sales` -> `Gross Profit` -> `Waste & Spoilage` -> `Net Profit (Operating)`.

- **Revenue Engine**: Tracks Gross Sales, Taxes, Service Charges, Discounts, and Voids.
- **Cost Engine**: Captures COGS per item, Waste/Spoilage cost, and Inventory valuations based on Weighted Average Cost.

## 2. Product & Category Profitability

For every single menu item sold, the system calculates and logs the exact profit metrics at the time of sale.

**Calculations**:
- `COGS` = Sum of all `recipe_items` cost based on current inventory valuation.
- `Gross Profit` = `Selling Price` - `COGS`.
- `Gross Margin %` = `(Gross Profit / Selling Price) * 100`.

**Rankings**: 
The Dashboard provides actionable lists:
- *Highest Revenue vs. Most Profitable* (A product might sell 1,000 units but yield 5% margin, while another sells 100 units but yields 80% margin. The engine surfaces the latter as the true money maker).

## 3. Waste Impact Analysis Engine

Waste is treated as a severe financial leak, not just an operational reality.
- Whenever stock is manually adjusted downwards (e.g., dropped milk, expired beans), it is logged as `Waste`.
- The engine calculates the `Waste Cost` by multiplying the lost quantity by the current `average_cost`.
- **Alert**: If a specific outlet logs waste exceeding 3% of daily revenue, an instant WebSocket alert is sent to the Area Manager.

## 4. Price Recommendation Engine

To protect margins from fluctuating supplier costs, the system auto-calculates recommended prices.

- **Target Margin Setup**: A category (e.g., "Coffee") is assigned a global target margin of 70%.
- **Trigger**: A new Supplier Invoice is received, raising the price of Coffee Beans by 15%.
- **Calculation**: The engine recalculates the COGS of a Latte. It detects that the margin has dropped to 62%.
- **Action**: The system generates a `Price Proposal` recommending the Selling Price of the Latte be raised from Rp 35.000 to Rp 38.000 to restore the 70% target.

### Price Approval Workflow
- Recommended prices sit in a "Draft" state.
- The Owner logs into the Dashboard, reviews the `Price Proposals`, and clicks "Approve & Publish".
- The new prices sync seamlessly down to the SQLite databases on all POS terminals at the selected Effective Date.

## 5. Scenario Simulation (What-If Analysis)

The system provides a Sandbox for the owner to test financial shocks:
- *What if Milk goes up 15%?*
- The engine creates a temporary fork of the database in memory (or using a temporary table), recalculates all recipes containing Milk, and projects the resulting drop in Gross Profit based on the last 30 days of sales volume.

## 6. Executive Dashboard Design

The Executive Dashboard (built in Flutter for Web/Tablet) avoids generic sales charts, focusing instead on action-oriented insights.

**Key Widgets**:
1. **The Profit Funnel**: `Revenue -> COGS -> Waste -> Net Operating Profit`.
2. **Margin Watchlist**: Products whose margins have slipped below threshold in the last 7 days.
3. **Outlet Comparison**: A scatter plot comparing Outlets by *Sales Volume* vs. *Waste Percentage*.
4. **Supplier Alerts**: Notifications of price hikes in recent Goods Receipts.

## 7. Multi-Outlet & Security

- **Multi-Outlet**: All reports can be viewed globally (Company Level), regionally (Brand Level), or individually (Outlet Level). 
- **Security**: Profitability data is strictly locked down. 
  - Cashiers and Outlet Managers **cannot** see COGS or Profit Margins.
  - Only Area Managers and Owners possess the RBAC permissions to view the Profitability Module and approve Price changes.
