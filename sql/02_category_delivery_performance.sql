-- ============================================================================
-- 02_category_delivery_performance.sql
--
-- BUSINESS QUESTION
--   Which product categories deliver worst against the date the customer was
--   promised, and what does that lateness cost in review scores?
--
-- WHY IT MATTERS
--   The estimated delivery date is a promise the platform sets. Categories
--   that systematically break it are a targeted fix: renegotiate carrier SLAs,
--   pad the estimate, or restrict which sellers can list in that category.
--   Ranking by "days late vs the promise" (not raw transit time) isolates the
--   broken-promise problem from categories that are just far away.
--
-- WHAT THIS QUERY RETURNS  (one row per category, >= 200 delivered orders,
--   ordered by pct_late DESC - "worst against the promise" first)
--   orders                       - sample size
--   pct_late                     - share delivered after the promised date
--   avg_days_vs_estimate         - mean(actual - promised); negative = early
--   avg_review_score             - overall mean score for the category
--   score_when_on_time / _late   - mean score split by whether the promise held
--   score_gap_late_vs_ontime     - how many review points a late delivery costs
--   score_points_lost_per_order  - pct_late * score_gap  (blended cost per order)
--   score_points_lost_total      - that * orders  (absolute review damage; this
--                                  is where high-volume categories dominate)
--
-- DATA-QUALITY DECISIONS
--   * is_clean_delivered orders only; estimated date must be present.
--   * An order with items from several categories counts once per distinct
--     category (order_category CTE) - delivery is an order-level event, so the
--     same outcome is attributed to each category the basket touched.
--   * Categories with < 200 delivered+reviewed orders are dropped: the
--     on-time/late split gets too noisy below that. Small categories are
--     listed in the README > Limitations.
--   * category is the English name from staging; 'unknown' = missing product
--     row or missing translation.
-- ============================================================================

WITH order_delivery AS (
    SELECT
        o.order_id,
        date_diff('day',
                  o.order_estimated_delivery_date,
                  o.order_delivered_customer_date)                 AS days_vs_estimate,
        (o.order_delivered_customer_date
         > o.order_estimated_delivery_date)                        AS is_late,
        r.review_score
    FROM stg_orders        AS o
    JOIN stg_order_reviews AS r ON r.order_id = o.order_id
    WHERE o.is_clean_delivered
      AND o.order_estimated_delivery_date IS NOT NULL
),

order_category AS (
    SELECT DISTINCT order_id, category
    FROM stg_order_items
),

joined AS (
    SELECT oc.category, od.*
    FROM order_delivery AS od
    JOIN order_category AS oc ON oc.order_id = od.order_id
),

by_category AS (
    SELECT
        category,
        count(*)                                              AS orders,
        round(avg(days_vs_estimate), 2)                       AS avg_days_vs_estimate,
        round(avg(is_late::int), 3)                           AS pct_late,
        round(avg(review_score), 3)                           AS avg_review_score,
        round(avg(review_score) FILTER (WHERE NOT is_late), 3) AS score_when_on_time,
        round(avg(review_score) FILTER (WHERE is_late), 3)     AS score_when_late
    FROM joined
    GROUP BY category
)

SELECT
    category,
    orders,
    pct_late,
    avg_days_vs_estimate,
    avg_review_score,
    score_when_on_time,
    score_when_late,
    round(score_when_on_time - score_when_late, 3)                       AS score_gap_late_vs_ontime,
    round(pct_late * (score_when_on_time - score_when_late), 3)          AS score_points_lost_per_order,
    round(pct_late * (score_when_on_time - score_when_late) * orders, 0) AS score_points_lost_total
FROM by_category
WHERE orders >= 200
ORDER BY pct_late DESC;
