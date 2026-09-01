-- ============================================================================
-- 01_delivery_time_vs_review_stats.sql
--
-- Companion to 01_delivery_time_vs_review.sql. Collapses the whole
-- relationship to a few numbers so the README can state the effect size.
--
--   n_orders                clean delivered orders with a review
--   pearson_r               correlation of review_score with delivery_days
--                           (negative = slower delivery, lower score)
--   score_lost_per_week     OLS slope * 7  -> review points lost per extra
--                           week in transit, holding nothing else constant
--   intercept               modelled score at 0 days (context only)
--   mean_score              baseline average score
--
-- This is a descriptive association, not a causal estimate. Late deliveries
-- correlate with damaged goods, remote regions, unreliable sellers, etc.
-- Treated honestly as such in the README > Limitations.
-- ============================================================================

WITH delivered AS (
    SELECT
        date_diff('day',
                  o.order_purchase_timestamp,
                  o.order_delivered_customer_date) AS delivery_days,
        r.review_score
    FROM stg_orders        AS o
    JOIN stg_order_reviews AS r ON r.order_id = o.order_id
    WHERE o.is_clean_delivered
)

SELECT
    count(*)                                               AS n_orders,
    round(corr(review_score, delivery_days), 3)            AS pearson_r,
    round(regr_slope(review_score, delivery_days) * 7, 3)  AS score_lost_per_week,
    round(regr_intercept(review_score, delivery_days), 3)  AS intercept,
    round(avg(review_score), 3)                            AS mean_score
FROM delivered;
