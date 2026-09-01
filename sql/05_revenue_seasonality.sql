-- ============================================================================
-- 05_revenue_seasonality.sql
--
-- BUSINESS QUESTION
--   What do revenue and order volume look like month over month - the growth
--   trend, the seasonal shape, and any anomalies that distort the picture?
--
-- WHY IT MATTERS
--   Every downstream number (repeat rate, category mix, seller cohorts) is read
--   against this baseline. Anyone quoting "GMP grew X%" needs to know which
--   months are real and which are data artefacts.
--
-- WHAT THIS QUERY RETURNS  (one row per calendar month)
--   orders, revenue, avg_order_value
--   revenue_mom_pct              - month-over-month growth
--   revenue_index_vs_2017_01     - revenue relative to Jan 2017 = 100
--   is_partial_month             - flagged coverage problem (see below)
--
-- DATA-QUALITY DECISIONS  (full write-up in README > Data quality)
--   * Revenue = sum(item price + freight) from stg_order_value, by
--     order_purchase_timestamp month.
--   * order_status IN ('canceled','unavailable') excluded.
--   * Coverage: Olist's data effectively starts 2017-01 (2016-09..12 hold only
--     a few hundred orders - a pilot) and the last month is truncated. Both
--     ends are flagged is_partial_month so charts can grey them out rather than
--     drawing a fake collapse.
-- ============================================================================

WITH monthly AS (
    SELECT
        date_trunc('month', o.order_purchase_timestamp)::date AS month,
        count(DISTINCT o.order_id)                            AS orders,
        round(sum(v.order_revenue), 2)                        AS revenue
    FROM stg_orders      AS o
    JOIN stg_order_value AS v ON v.order_id = o.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY 1
),

bounds AS (SELECT min(month) AS first_m, max(month) AS last_m FROM monthly),

ref AS (SELECT revenue AS jan_2017 FROM monthly WHERE month = DATE '2017-01-01')

SELECT
    m.month,
    m.orders,
    m.revenue,
    round(m.revenue / m.orders, 2)                                        AS avg_order_value,
    round(100.0 * (m.revenue - lag(m.revenue) OVER (ORDER BY m.month))
          / lag(m.revenue) OVER (ORDER BY m.month), 1)                    AS revenue_mom_pct,
    round(100.0 * m.revenue / nullif((SELECT jan_2017 FROM ref), 0), 0)   AS revenue_index_vs_2017_01,
    (m.orders < 500
     OR m.month = (SELECT first_m FROM bounds)
     OR m.month = (SELECT last_m  FROM bounds))                           AS is_partial_month
FROM monthly AS m
ORDER BY m.month;
