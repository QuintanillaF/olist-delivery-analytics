-- ============================================================================
-- 05_revenue_daily_anomalies.sql
--
-- Companion to 05_revenue_seasonality.sql. Flags individual days whose order
-- count is a >= 3-sigma outlier from the daily mean, so the monthly trend can be
-- read knowing which spikes are single events (Black Friday) rather than a
-- shift in the run rate.
--
-- WHAT THIS QUERY RETURNS  (one row per anomalous day, biggest first)
--   day, orders, revenue
--   orders_z        - standard deviations above/below the daily mean
--   note            - best-guess label for known Brazilian retail dates
--
-- DATA QUALITY: same status filter as the monthly query. The near-empty 2016
-- pilot days are excluded from the mean/sigma (day >= 2017-01-01) so they do
-- not deflate the baseline.
-- ============================================================================

WITH daily AS (
    SELECT
        o.order_purchase_timestamp::date          AS day,
        count(DISTINCT o.order_id)                 AS orders,
        round(sum(v.order_revenue), 2)            AS revenue
    FROM stg_orders      AS o
    JOIN stg_order_value AS v ON v.order_id = o.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND o.order_purchase_timestamp >= DATE '2017-01-01'
    GROUP BY 1
),

stats AS (SELECT avg(orders) AS mu, stddev_pop(orders) AS sd FROM daily)

SELECT
    d.day,
    d.orders,
    d.revenue,
    round((d.orders - s.mu) / s.sd, 1)            AS orders_z,
    CASE
        WHEN d.day BETWEEN DATE '2017-11-23' AND DATE '2017-11-27' THEN 'Black Friday 2017'
        WHEN month(d.day) = 5  AND day(d.day) BETWEEN 6  AND 12     THEN 'Mothers Day week'
        WHEN month(d.day) = 8  AND day(d.day) BETWEEN 6  AND 12     THEN 'Fathers Day week (BR)'
        ELSE NULL
    END                                          AS note
FROM daily AS d
CROSS JOIN stats AS s
WHERE abs((d.orders - s.mu) / s.sd) >= 3
ORDER BY d.orders DESC;
