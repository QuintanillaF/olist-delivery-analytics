-- ============================================================================
-- 06_geo_distance_vs_delay.sql
--
-- BUSINESS QUESTION
--   Does the physical distance between seller and customer explain slow / late
--   deliveries, or is something else driving them?
--
-- WHY IT MATTERS
--   If distance is the driver, the fix is logistics network design (regional
--   warehouses, closer sellers for far customers). If distance is already
--   priced into the estimate and orders are still late, the fix is upstream:
--   seller handover time or carrier performance. Same symptom, opposite
--   response - see also 06_geo_distance_correlation.sql.
--
-- WHAT THIS QUERY RETURNS  (one row per distance band)
--   orders, avg_distance_km
--   avg_delivery_days         - purchase -> customer
--   avg_days_vs_estimate      - actual - promised (does the promise scale
--                               with distance the way transit time does?)
--   avg_seller_handover_days  - purchase -> carrier pickup (seller-controlled)
--   pct_late
--
-- METHOD / DATA-QUALITY DECISIONS
--   * Distance = haversine between the median lat/lng of the customer's zip
--     prefix and the seller's zip prefix (stg_geolocation).
--   * INNER joins on geolocation: orders whose customer or seller zip prefix
--     is absent from the geolocation table are dropped (~2-3%). Counted in the
--     README > Data quality.
--   * Multi-seller orders: one row per order, taking the farthest seller - that
--     leg sets the delivery date.
--   * is_clean_delivered orders only.
-- ============================================================================

WITH order_seller_geo AS (
    SELECT
        o.order_id,
        cust.customer_state,
        date_diff('day', o.order_purchase_timestamp,
                         o.order_delivered_customer_date)              AS delivery_days,
        date_diff('day', o.order_estimated_delivery_date,
                         o.order_delivered_customer_date)              AS days_vs_estimate,
        date_diff('hour', o.order_purchase_timestamp,
                          o.order_delivered_carrier_date) / 24.0       AS seller_handover_days,
        (o.order_delivered_customer_date
         > o.order_estimated_delivery_date)                            AS is_late,
        2 * 6371 * asin(sqrt(
            pow(sin(radians(cg.lat - sg.lat) / 2), 2)
          + cos(radians(sg.lat)) * cos(radians(cg.lat))
              * pow(sin(radians(cg.lng - sg.lng) / 2), 2)
        ))                                                             AS distance_km
    FROM stg_orders       AS o
    JOIN stg_customers    AS cust ON cust.customer_id = o.customer_id
    JOIN stg_geolocation  AS cg   ON cg.zip_prefix = cust.zip_prefix
    JOIN stg_order_items  AS oi   ON oi.order_id = o.order_id
    JOIN stg_sellers      AS sel  ON sel.seller_id = oi.seller_id
    JOIN stg_geolocation  AS sg   ON sg.zip_prefix = sel.zip_prefix
    WHERE o.is_clean_delivered
),

per_order AS (
    SELECT
        order_id,
        any_value(customer_state)      AS customer_state,
        max(distance_km)               AS distance_km,
        any_value(delivery_days)       AS delivery_days,
        any_value(days_vs_estimate)    AS days_vs_estimate,
        any_value(seller_handover_days) AS seller_handover_days,
        any_value(is_late)             AS is_late
    FROM order_seller_geo
    GROUP BY order_id
)

SELECT
    CASE
        WHEN distance_km <  100 THEN 'a) 0-100 km'
        WHEN distance_km <  300 THEN 'b) 100-300 km'
        WHEN distance_km <  700 THEN 'c) 300-700 km'
        WHEN distance_km < 1500 THEN 'd) 700-1500 km'
        WHEN distance_km < 2500 THEN 'e) 1500-2500 km'
        ELSE                        'f) 2500+ km'
    END                                        AS distance_band,
    count(*)                                   AS orders,
    round(avg(distance_km), 0)                 AS avg_distance_km,
    round(avg(delivery_days), 1)               AS avg_delivery_days,
    round(avg(days_vs_estimate), 1)            AS avg_days_vs_estimate,
    round(avg(seller_handover_days), 1)        AS avg_seller_handover_days,
    round(avg(is_late::int), 3)                AS pct_late
FROM per_order
GROUP BY distance_band
ORDER BY distance_band;
