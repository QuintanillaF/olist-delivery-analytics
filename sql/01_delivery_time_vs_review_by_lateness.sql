-- ============================================================================
-- 01_delivery_time_vs_review_by_lateness.sql
--
-- Re-frames question 1 the way the customer actually experiences it: not
-- "how many days did it take" but "how did it land against the delivery date
-- I was promised at checkout".
--
-- order_estimated_delivery_date is shown to the customer before they buy, so
-- days_late = actual - estimate is the expectation gap. This is usually where
-- the threshold shows up: customers forgive a slow-but-on-time delivery and
-- punish a broken promise.
--
-- RETURNS one row per expectation-gap band:
--   orders, mean_review_score, pct_one_star
--
-- DATA QUALITY: same is_clean_delivered filter as 01_..., plus estimated date
-- must be present (it always is in practice).
-- ============================================================================

WITH d AS (
    SELECT
        date_diff('day',
                  o.order_estimated_delivery_date,
                  o.order_delivered_customer_date) AS days_late,
        r.review_score
    FROM stg_orders        AS o
    JOIN stg_order_reviews AS r ON r.order_id = o.order_id
    WHERE o.is_clean_delivered
      AND o.order_estimated_delivery_date IS NOT NULL
)

SELECT
    CASE
        WHEN days_late <= -10 THEN 'a) 10+ days early'
        WHEN days_late <    0 THEN 'b) 1-9 days early'
        WHEN days_late =    0 THEN 'c) on the promised day'
        WHEN days_late <=   5 THEN 'd) 1-5 days late'
        WHEN days_late <=  10 THEN 'e) 6-10 days late'
        ELSE                       'f) 11+ days late'
    END                                      AS vs_promised_date,
    count(*)                                 AS orders,
    round(avg(review_score), 3)              AS mean_review_score,
    round(avg((review_score = 1)::int), 3)   AS pct_one_star
FROM d
GROUP BY vs_promised_date
ORDER BY vs_promised_date;
