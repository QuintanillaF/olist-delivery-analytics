-- ============================================================================
-- 06_geo_distance_correlation.sql
--
-- The one-number version of question 6. Two correlations decide the story:
--
--   corr(distance, delivery_days)     - does it take longer to ship far? (expect yes)
--   corr(distance, days_vs_estimate)  - is it LATER vs the promise when far?
--
-- If the first is strong and the second is near zero, Olist's estimated
-- delivery date already absorbs distance, and lateness is coming from
-- somewhere else (seller handover, carrier reliability) - so the correlation
-- of handover time with lateness is reported alongside for comparison.
--
-- RETURNS one row:
--   n_orders
--   r_distance_delivery, r_distance_vs_estimate
--   r_handover_vs_estimate       - corr(seller_handover_days, days_vs_estimate)
--   slope_days_per_1000km        - OLS: extra transit days per 1,000 km
--
-- Same geo build and filters as 06_geo_distance_vs_delay.sql.
-- ============================================================================

WITH order_seller_geo AS (
    SELECT
        o.order_id,
        date_diff('day', o.order_purchase_timestamp,
                         o.order_delivered_customer_date)        AS delivery_days,
        date_diff('day', o.order_estimated_delivery_date,
                         o.order_delivered_customer_date)        AS days_vs_estimate,
        date_diff('hour', o.order_purchase_timestamp,
                          o.order_delivered_carrier_date) / 24.0 AS seller_handover_days,
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
        max(distance_km)                AS distance_km,
        any_value(delivery_days)        AS delivery_days,
        any_value(days_vs_estimate)     AS days_vs_estimate,
        any_value(seller_handover_days) AS seller_handover_days
    FROM order_seller_geo
    GROUP BY order_id
)

SELECT
    count(*)                                                        AS n_orders,
    round(corr(delivery_days, distance_km), 3)                      AS r_distance_delivery,
    round(corr(days_vs_estimate, distance_km), 3)                   AS r_distance_vs_estimate,
    round(corr(days_vs_estimate, seller_handover_days), 3)          AS r_handover_vs_estimate,
    round(regr_slope(delivery_days, distance_km) * 1000, 2)         AS slope_days_per_1000km
FROM per_order
WHERE seller_handover_days IS NOT NULL;
