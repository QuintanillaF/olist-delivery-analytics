-- ============================================================================
-- 04_seller_scored.sql
--
-- Per-seller metrics + segment label. Feeds the seller scatter plot
-- (volume vs reliability, sized by GMV, coloured by segment) in the notebook
-- and README.
--
-- Same segment rules and same metrics CTE as 04_seller_segmentation.sql - the
-- CTE is repeated on purpose so this file reads on its own. See that file's
-- header for the rule definitions and data-quality notes.
-- ============================================================================

WITH seller_order AS (
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
        round(avg((so.carrier_date > so.shipping_limit_date)::int)
              FILTER (WHERE so.carrier_date IS NOT NULL), 3)            AS pct_shipped_late,
        round(avg(date_diff('day', so.estimated_date, so.customer_date))
              FILTER (WHERE so.is_clean_delivered), 2)                  AS avg_days_vs_estimate,
        round(avg(r.review_score), 3)                                   AS avg_review_score,
        count(r.review_score)                                           AS n_reviews
    FROM seller_order AS so
    LEFT JOIN stg_order_reviews AS r ON r.order_id = so.order_id
    GROUP BY so.seller_id
)

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
ORDER BY gmv DESC;
