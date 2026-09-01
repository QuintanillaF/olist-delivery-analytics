-- ============================================================================
-- 06_geo_delay_by_state.sql
--
-- Question 6 broken out by the customer's state. Brazil's regional inequality
-- shows up hard in logistics: the South/Southeast (where Olist's sellers
-- cluster) vs the North/Northeast.
--
-- WHAT THIS QUERY RETURNS  (one row per customer_state)
--   orders, avg_distance_km
--   avg_delivery_days, avg_days_vs_estimate, pct_late
--   avg_seller_handover_days
--   avg_estimate_window_days  - promised window the customer was shown
--                               (purchase -> estimated date). Does Olist widen
--                               the promise for far states, and by enough?
--
-- Same geo build / filters as 06_geo_distance_vs_delay.sql. States with
-- < 100 delivered orders are kept but are noise - flagged low_sample.
-- ============================================================================

WITH order_seller_geo AS (
    SELECT
        o.order_id,
        cust.customer_state,
        date_diff('day', o.order_purchase_timestamp,
                         o.order_delivered_customer_date)        AS delivery_days,
        date_diff('day', o.order_estimated_delivery_date,
                         o.order_delivered_customer_date)        AS days_vs_estimate,
        date_diff('day', o.order_purchase_timestamp,
                         o.order_estimated_delivery_date)        AS estimate_window_days,
        date_diff('hour', o.order_purchase_timestamp,
                          o.order_delivered_carrier_date) / 24.0 AS seller_handover_days,
        (o.order_delivered_customer_date
         > o.order_estimated_delivery_date)                      AS is_late,
        2 * 6371 * asin(sqrt(
            pow(sin(radians(cg.lat - sg.lat) / 2), 2)
          + cos(radians(sg.lat)) * cos(radians(cg.lat))
              * pow(sin(radians(cg.lng - sg.lng) / 2), 2)
        ))                                                       AS distance_km
    FROM stg_orders      AS o
    JOIN stg_customers   AS cust ON cust.customer_id = o.customer_id
    JOIN stg_geolocation AS cg   ON cg.zip_prefix = cust.zip_prefix
    JOIN stg_order_items AS oi   ON oi.order_id = o.order_id
    JOIN stg_sellers     AS sel  ON sel.seller_id = oi.seller_id
    JOIN stg_geolocation AS sg   ON sg.zip_prefix = sel.zip_prefix
    WHERE o.is_clean_delivered
),

per_order AS (
    SELECT
        order_id,
        any_value(customer_state)       AS customer_state,
        max(distance_km)                AS distance_km,
        any_value(delivery_days)        AS delivery_days,
        any_value(days_vs_estimate)     AS days_vs_estimate,
        any_value(estimate_window_days) AS estimate_window_days,
        any_value(seller_handover_days) AS seller_handover_days,
        any_value(is_late)              AS is_late
    FROM order_seller_geo
    GROUP BY order_id
)

SELECT
    customer_state,
    count(*)                              AS orders,
    round(avg(distance_km), 0)            AS avg_distance_km,
    round(avg(delivery_days), 1)          AS avg_delivery_days,
    round(avg(estimate_window_days), 1)   AS avg_estimate_window_days,
    round(avg(days_vs_estimate), 1)       AS avg_days_vs_estimate,
    round(avg(is_late::int), 3)           AS pct_late,
    round(avg(seller_handover_days), 1)   AS avg_seller_handover_days,
    (count(*) < 100)                      AS low_sample
FROM per_order
GROUP BY customer_state
ORDER BY avg_days_vs_estimate DESC;
