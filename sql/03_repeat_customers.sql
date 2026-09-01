-- ============================================================================
-- 03_repeat_customers.sql
--
-- BUSINESS QUESTION
--   What fraction of customers ever place a second order? What does the
--   marketplace's retention actually look like?
--
-- WHY IT MATTERS
--   Acquisition cost only pays back if customers come back. If repeat rate is
--   near zero the business is a one-shot acquisition machine and the whole
--   growth model (and the value of fixing delivery) has to be argued on first
--   orders alone, not lifetime value.
--
-- WHAT THIS QUERY RETURNS  (one row)
--   customers                 - distinct real people (customer_unique_id)
--   pct_ordering_2plus        - fraction with >= 2 non-cancelled orders
--   pct_ordering_3plus        - fraction with >= 3
--   mean_orders_per_customer
--   max_orders                - the single most active customer
--
-- DATA-QUALITY DECISIONS
--   * customer_unique_id, not customer_id: Olist mints a fresh customer_id per
--     order, so counting customer_id would show a 0% repeat rate by
--     construction. customer_unique_id is the person.
--   * order_status = 'canceled' excluded - a cancelled order is not a purchase.
--   * Censoring: the data ends 2018-10. Customers who bought in the last weeks
--     had almost no window to return, so this is a slight under-count. The
--     "by first-review" cut (03_repeat_customers_by_first_review.sql) restricts
--     to first orders old enough to have a fair 120-day window.
-- ============================================================================

WITH customer_order_counts AS (
    SELECT
        c.customer_unique_id,
        count(*) AS lifetime_orders
    FROM stg_orders    AS o
    JOIN stg_customers AS c ON c.customer_id = o.customer_id
    WHERE o.order_status <> 'canceled'
    GROUP BY c.customer_unique_id
)

SELECT
    count(*)                                        AS customers,
    round(avg((lifetime_orders >= 2)::int), 4)      AS pct_ordering_2plus,
    round(avg((lifetime_orders >= 3)::int), 4)      AS pct_ordering_3plus,
    round(avg(lifetime_orders), 4)                  AS mean_orders_per_customer,
    max(lifetime_orders)                            AS max_orders
FROM customer_order_counts;
