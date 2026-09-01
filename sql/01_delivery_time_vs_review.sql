-- ============================================================================
-- 01_delivery_time_vs_review.sql
--
-- BUSINESS QUESTION
--   Does how long an order takes to arrive predict the review score the
--   customer leaves? How big is the effect, and is it linear or is there a
--   point where satisfaction falls off a cliff?
--
-- WHY IT MATTERS
--   Delivery speed is one of the few post-purchase levers a marketplace
--   actually controls. If satisfaction degrades smoothly, "ship a bit faster
--   everywhere" is the play. If it collapses past a threshold, the money is
--   in killing the tail of very-late orders, not in shaving the average.
--
-- WHAT THIS QUERY RETURNS
--   One row per delivery-time bucket:
--     orders                 - sample size (watch the small tail buckets)
--     mean_review_score      - average of the 1-5 score
--     pct_one_star           - share of 1-star reviews  <- the "collapse" signal
--     pct_five_star          - share of 5-star reviews
--     median_days_in_bucket  - sanity check on the bucket
--   The single-number correlation / slope is in
--   01_delivery_time_vs_review_stats.sql; the "vs the promised date" cut is in
--   01_delivery_time_vs_review_by_lateness.sql.
--
-- DATA-QUALITY DECISIONS (see README > Data quality)
--   * Only is_clean_delivered orders: status = 'delivered', both timestamps
--     present, delivery not before purchase.
--   * Reviews are the de-duplicated stg_order_reviews (one per order).
--   * Orders with no review row are excluded here and analysed separately as
--     a response-bias check (do slow orders review more often?) in the
--     notebook.
-- ============================================================================

WITH delivered AS (
    SELECT
        o.order_id,
        date_diff('day',
                  o.order_purchase_timestamp,
                  o.order_delivered_customer_date) AS delivery_days,
        r.review_score
    FROM stg_orders        AS o
    JOIN stg_order_reviews AS r ON r.order_id = o.order_id
    WHERE o.is_clean_delivered
),

bucketed AS (
    SELECT
        delivery_days,
        review_score,
        CASE
            WHEN delivery_days <=  3 THEN '00-03 days'
            WHEN delivery_days <=  7 THEN '04-07 days'
            WHEN delivery_days <= 11 THEN '08-11 days'
            WHEN delivery_days <= 15 THEN '12-15 days'
            WHEN delivery_days <= 20 THEN '16-20 days'
            WHEN delivery_days <= 30 THEN '21-30 days'
            WHEN delivery_days <= 45 THEN '31-45 days'
            ELSE                         '46+ days'
        END AS delivery_bucket
    FROM delivered
)

SELECT
    delivery_bucket,
    count(*)                                 AS orders,
    round(avg(review_score), 3)              AS mean_review_score,
    round(avg((review_score = 1)::int), 3)   AS pct_one_star,
    round(avg((review_score = 5)::int), 3)   AS pct_five_star,
    round(median(delivery_days), 1)          AS median_days_in_bucket
FROM bucketed
GROUP BY delivery_bucket
ORDER BY delivery_bucket;
