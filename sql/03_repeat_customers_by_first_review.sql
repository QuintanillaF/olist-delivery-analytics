-- ============================================================================
-- 03_repeat_customers_by_first_review.sql
--
-- BUSINESS QUESTION
--   Does a bad first experience predict never coming back? Split the return
--   rate by the review score the customer left on their first order.
--
-- WHY IT MATTERS
--   If 1-star first-timers return at half the rate of 5-star first-timers,
--   then a botched first delivery is not just one bad review - it is a lost
--   customer, and the delivery investment pays for itself through retention.
--   If the return rate is flat across scores, retention is driven by something
--   else and delivery should be justified on reviews / word-of-mouth alone.
--
-- WHAT THIS QUERY RETURNS  (one row per first-order review score, plus NULL)
--   first_review_score   - 1..5, or NULL = first order never reviewed
--   customers            - how many people started here
--   pct_returned         - fraction that placed a 2nd order within the window
--   pct_returned_120d    - fraction whose 2nd order came within 120 days
--
-- DATA-QUALITY DECISIONS
--   * customer_unique_id = the person. First order = earliest
--     order_purchase_timestamp (order_id as a deterministic tie-break).
--   * order_status = 'canceled' excluded.
--   * Censoring fix: only first orders placed on/before (max purchase date in
--     the data - 120 days) are counted, so every customer in the denominator
--     had at least a 120-day chance to return.
--   * Reviews are the de-duplicated stg_order_reviews.
-- ============================================================================

WITH cutoff AS (
    SELECT (max(order_purchase_timestamp) - INTERVAL 120 DAY) AS last_fair_date
    FROM stg_orders
    WHERE order_status <> 'canceled'
),

customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        row_number() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp, o.order_id
        ) AS order_seq
    FROM stg_orders    AS o
    JOIN stg_customers AS c ON c.customer_id = o.customer_id
    WHERE o.order_status <> 'canceled'
),

first_orders AS (
    SELECT customer_unique_id, order_id, order_purchase_timestamp AS first_ts
    FROM customer_orders
    WHERE order_seq = 1
),

second_orders AS (
    SELECT customer_unique_id, order_purchase_timestamp AS second_ts
    FROM customer_orders
    WHERE order_seq = 2
),

labelled AS (
    SELECT
        f.customer_unique_id,
        r.review_score                             AS first_review_score,
        (s.customer_unique_id IS NOT NULL)         AS returned,
        (s.second_ts IS NOT NULL
         AND s.second_ts <= f.first_ts + INTERVAL 120 DAY) AS returned_120d
    FROM first_orders           AS f
    CROSS JOIN cutoff           AS cut
    LEFT JOIN stg_order_reviews AS r ON r.order_id = f.order_id
    LEFT JOIN second_orders     AS s ON s.customer_unique_id = f.customer_unique_id
    WHERE f.first_ts <= cut.last_fair_date
)

SELECT
    first_review_score,
    count(*)                              AS customers,
    round(avg(returned::int), 4)          AS pct_returned,
    round(avg(returned_120d::int), 4)     AS pct_returned_120d
FROM labelled
GROUP BY first_review_score
ORDER BY first_review_score NULLS FIRST;
