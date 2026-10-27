# Reporting definitions

All figures are aggregated by the database from recorded transactions. Nothing is estimated, sampled or
hard-coded. An empty business reports zeros.

**Business day.** Days are calendar days in the business's configured time zone (default `Africa/Kampala`). A sale at
23:30 Kampala time belongs to that day, even though it is 20:30 UTC.

| Figure | Definition |
|---|---|
| Gross sales | Sum of line amounts (unit price × quantity) **before** discounts, for sales created in the period |
| Discounts | Line discounts plus order discounts on those sales |
| Refunds | Refunds issued in the period, dated by **refund date** (a refund today for last month's sale reduces today's net sales) |
| Net sales | Gross sales − discounts − refunds |
| Tax included | Tax extracted from tax-inclusive totals at the business's rate: `total × rate / (100 + rate)` |
| COGS | Σ (cost price captured at the moment of sale × quantity) − cost of returned items that were put back in stock |
| Gross profit | Net sales − COGS |
| `cost_data_complete` | `false` when any item sold in the period had a cost price of 0. Gross profit is then overstated and the app labels it as an estimate |
| Expenses | Operating expenses whose expense date falls in the period (deleted expenses excluded) |
| Net profit (estimate) | Gross profit − expenses. An operational indicator, **not** an accounting statement |
| Average sale | (Gross sales − discounts) ÷ number of sales |
| Inventory valuation | Σ positive on-hand quantity × current weighted-average cost (only shown to roles that may see costs) |
| Payment methods | Net money per method: payments received minus refunds paid out, by payment date |

**Cost method:** moving weighted-average cost, updated whenever stock is received with a unit cost.

**Offline sales** are dated by the device time when it is plausible (no more than 72 hours old and not in the
future, with 5 minutes' allowance for clock skew). Otherwise they are dated by the server time. The device time
is always kept in `client_created_at`.

**Dashboard comparisons:** today vs yesterday; last 7 or 30 days vs the previous 7 or 30; month-to-date vs the
same number of days last month. When the earlier period has no sales, no percentage is shown.
