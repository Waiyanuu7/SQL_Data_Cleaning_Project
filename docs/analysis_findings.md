# Business Analysis: Findings

**Script:** [`sql/analysis/01_business_analysis.sql`](../sql/analysis/01_business_analysis.sql)
All results come from the **clean** tables.

**Revenue definition:** orders with status *Delivered* or *Shipped*, using the order total **recalculated from valid line items** (plus shipping). Cancelled, Returned, Pending and Unknown orders are excluded. Product and category revenue uses line totals, so it excludes shipping.

---

## Q0. Why the cleaning mattered

| Revenue source | Completed-order revenue |
|---|---|
| Raw `order_total` column | £113.81M |
| **Clean, recalculated total** | **£32.34M** |

Reporting straight from the raw data would have **overstated revenue by about 3.5×**, almost entirely because of a few orders with a quantity of 999.

## Q1. Headline numbers (Jan 2021 – Sep 2026)

| Metric | Value |
|---|---|
| Completed orders | 115,786 |
| Customers who bought | 24,695 |
| Revenue | **£32.34M** |
| Average order value | **£279.28** |

## Q2. Revenue by year

2026 only contains January–September, so it's also compared on a like-for-like Jan–Sep basis.

| Year | Revenue | YoY growth | Jan–Sep revenue | YoY (Jan–Sep) |
|---|---|---|---|---|
| 2021 | £5.33M | | £3.95M | |
| 2022 | £5.32M | -0.3% | £3.98M | +0.7% |
| 2023 | £5.45M | +2.5% | £4.10M | +3.0% |
| 2024 | £5.46M | +0.3% | £4.10M | 0.0% |
| 2025 | £5.40M | -1.2% | £4.01M | -2.2% |
| 2026 | £3.92M | (partial year) | £3.92M | **-2.3%** |

**Insight:** revenue has been flat for five years (around £5.3–5.5M a year). The full-year 2026 figure looks like a 27% drop, but that's only because the year isn't finished. Like-for-like, 2026 is down 2.3%, the second small decline in a row. Comparing incomplete periods is a common reporting mistake.

## Q3. Monthly trend

Monthly revenue holds steady at between £402k and £491k, with no strong seasonality. The full table, with a 3-month moving average, is in the script output.

## Q4. Revenue by category

| Category | Units sold | Revenue | Share |
|---|---|---|---|
| Electronics | 67,321 | £12.34M | **38.7%** |
| Home & Kitchen | 70,949 | £4.18M | 13.1% |
| Clothing | 73,162 | £4.18M | 13.1% |
| Beauty | 66,971 | £3.93M | 12.3% |
| Sports | 70,911 | £3.80M | 11.9% |
| Books | 66,086 | £3.43M | 10.7% |
| Not in catalogue | 2,098 | £0.05M | 0.2% |

**Insight:** every category sells a similar number of units, but **Electronics brings in almost 3× the revenue of any other category** because of its higher prices. It's the business's key category.

## Q5. Top 10 products

All ten are **Electronics**, led by Classic Smartwatch (£211.5k), Classic Speaker (£211.3k) and Eco Webcam (£208.7k). Speakers take 5 of the 10 spots.

## Q6. Revenue by customer country

| Country | Orders | Revenue | Avg order value |
|---|---|---|---|
| United Kingdom | 56,451 | £15.75M | £279.07 |
| United States | 22,783 | £6.38M | £280.13 |
| Germany | 11,194 | £3.12M | £279.05 |
| France | 8,893 | £2.49M | £280.45 |
| Ireland | 7,648 | £2.14M | £279.36 |
| Spain | 5,882 | £1.62M | £275.48 |
| Unknown customer | 2,935 | £0.83M | £281.62 |

**Insight:** the UK provides **49%** of revenue. Average order value is almost identical everywhere, so the differences between countries come from the number of customers, not how much each customer spends per order.

## Q7. Revenue by channel

| Channel | Orders | Revenue | Avg order value |
|---|---|---|---|
| Mobile App | 52,646 | £14.66M | £278.43 |
| Web | 31,559 | £8.87M | £280.95 |
| Unknown | 10,667 | £2.98M | £279.62 |
| In-store | 10,530 | £2.96M | £281.43 |
| Phone | 10,384 | £2.87M | £276.00 |

**Insight:** the **mobile app is the biggest channel (45% of revenue)**. About 9% of revenue has no recorded channel, which is a tracking gap worth fixing.

## Q8. Repeat customers

| Metric | Value |
|---|---|
| Customers with a completed order | 24,695 |
| Repeat customers (2+ orders) | 23,292 |
| **Repeat rate** | **94.3%** |
| Average orders per customer | 4.57 |
| Average lifetime spend | £1,275.99 |

## Q9. Return and cancellation rates by category

Return rates sit between **6.4% and 6.7%**, and cancellation rates between **10.2% and 10.4%**, for every category. No category stands out. Cancellations (about 10%) are a bigger revenue leak than returns.

## Q10. Promo codes

| Promo | Share of orders | Avg order value |
|---|---|---|
| No promo | 44.4% | £279.14 |
| WELCOME | 22.3% | £281.79 |
| SUMMER10 | 22.2% | £278.27 |
| BF2025 | 11.1% | £276.86 |

**Insight:** **56% of completed orders use a promo code**, but orders with a code are no larger than orders without one. The promos don't appear to raise basket size, so their value should be judged on whether they win extra orders.

## Q11. Shipping time

Average time from order to shipping is **3.5 days** for every channel. Orders flagged as shipped before ordered are excluded.

---

## Note on the data

This is a synthetic dataset built to practise cleaning. Business patterns, such as the even spread across categories and the flat trend, are much smoother than real data would be. The focus of this project is the cleaning process, and the analysis shows the clean tables answering real business questions correctly.
