-- ============================================================================
-- 04_seller_segmentation.sql
--
-- BUSINESS QUESTION
--   Group the ~3,000 sellers by volume, delivery reliability and review
--   performance. Which segment should the platform invest in, and which is
--   dragging the marketplace down?
--
-- WHY IT MATTERS
--   Seller quality is uneven and the platform can act on it: onboarding
--   support, better placement, or delisting. This needs segments tied to a
--   decision, not a leaderboard.
--
-- SEGMENT RULES  (applied per seller, first match wins)
--   Core - invest         >= 50 orders, <= 10% shipped late, avg review >= 4.0
--   Rising - grow          < 50 orders, <= 10% shipped late, avg review >= 4.0
--   At risk - fix or drop  avg review < 3.5  OR  > 25% shipped late
--   Steady - maintain      everyone else
--
--   "Shipped late" = handed to the carrier after shipping_limit_date. That is
--   the seller's own SLA; carrier transit time is not the seller's fault, so
--   it is deliberately excluded from the reliability score here.
--
-- WHAT THIS QUERY RETURNS  (one row per segment)
--   sellers, orders, gmv, pct_of_gmv,
--   avg_pct_shipped_late, avg_review_score, avg_days_vs_estimate
--
-- DATA-QUALITY DECISIONS
--   * GMV = sum of item price (freight excluded - it is not the seller's revenue).
--   * pct_shipped_late computed only over orders with a carrier date present.
--   * Sellers with 0 reviews keep a NULL review score and fall to "Steady"
--     unless their shipping record is bad enough to flag them.
--   * Per-seller detail (for the scatter plot) is 04_seller_scored.sql, which
--     repeats the metrics CTE so each file reads standalone.
-- ============================================================================

WITH seller_order AS (
    -- collapse items to one row per (seller, order)
    SELECT
        oi.seller_id,
        oi.order_id,
        sum(oi.price)                              AS order_items_value,
        max(oi.shipping_limit_date)               AS shipping_limit_date,
        any_value(o.order_delivered_carrier_date) AS carrier_date,
        any_value(o.order_delivered_customer_date) AS customer_date,
        any_value(o.order_estimated_delivery_date) AS estimated_date,
        any_value(o.is_clean_delivered)           AS is_clean_delivered
    FROM stg_order_items AS oi
    JOIN stg_orders      AS o ON o.order_id = oi.order_id
    GROUP BY oi.seller_id, oi.order_id
),

seller_metrics AS (
    SELECT
        so.seller_id,
        count(*)                                                        AS orders,
        round(sum(so.order_items_value), 2)                             AS gmv,
        avg((so.carrier_date > so.shipping_limit_date)::int)
            FILTER (WHERE so.carrier_date IS NOT NULL)                  AS pct_shipped_late,
        avg(date_diff('day', so.estimated_date, so.customer_date))
            FILTER (WHERE so.is_clean_delivered)                        AS avg_days_vs_estimate,
        avg(r.review_score)                                             AS avg_review_score
    FROM seller_order AS so
    LEFT JOIN stg_order_reviews AS r ON r.order_id = so.order_id
    GROUP BY so.seller_id
),

segmented AS (
    SELECT
        *,
        CASE
            WHEN avg_review_score < 3.5
              OR coalesce(pct_shipped_late, 1) > 0.25          THEN 'At risk - fix or drop'
            WHEN orders >= 50
             AND coalesce(pct_shipped_late, 1) <= 0.10
             AND avg_review_score >= 4.0                        THEN 'Core - invest'
            WHEN orders <  50
             AND coalesce(pct_shipped_late, 1) <= 0.10
             AND avg_review_score >= 4.0                        THEN 'Rising - grow'
            ELSE                                                     'Steady - maintain'
        END AS segment
    FROM seller_metrics
)

SELECT
    segment,
    count(*)                                                   AS sellers,
    sum(orders)                                                AS orders,
    round(sum(gmv), 0)                                         AS gmv,
    round(100.0 * sum(gmv) / sum(sum(gmv)) OVER (), 1)         AS pct_of_gmv,
    round(avg(pct_shipped_late), 3)                            AS avg_pct_shipped_late,
    round(avg(avg_review_score), 2)                            AS avg_review_score,
    round(avg(avg_days_vs_estimate), 2)                        AS avg_days_vs_estimate
FROM segmented
GROUP BY segment
ORDER BY gmv DESC;
