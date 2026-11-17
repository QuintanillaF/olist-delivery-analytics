-- ============================================================================
-- star/01_dim_date.sql  —  date dimension
--
-- GRAIN
--   One row per calendar day, no gaps, whole calendar years.
--
-- WHY A DATE TABLE AT ALL  (instead of letting the BI tool derive year/month)
--   * Time intelligence in Power BI (previous month, year-to-date, same period
--     last year) needs a table of contiguous, unique dates marked as the date
--     table. The built-in auto date/time creates one hidden table per date
--     column instead - bloated, and impossible to share between dates.
--   * It is a ROLE-PLAYING dimension: the fact table points at it three times
--     (purchase, delivery, promised delivery). One table, three meanings, so
--     "March 2018" is the same row whichever date you slice by.
--   * Calendar attributes that are not derivable from the date itself live
--     here once - is_complete_month below is the important one.
--
-- KEY
--   date_key is the integer YYYYMMDD (20180131). This is the one dimension
--   where a "smart" key is the accepted convention: it is readable in the fact
--   table, sorts chronologically, and never needs a lookup to be generated.
--   full_date carries the real DATE type for the BI tool's time functions.
--
-- DECISIONS
--   * Range is derived from the data, then padded to full years (2016-01-01 ..
--     2018-12-31): it covers purchase, delivery and promised-delivery dates,
--     and full years keep year-to-date / previous-year functions well defined.
--   * No "unknown date" row. Orders that were never delivered keep a NULL
--     delivered_date_key in the fact. A dummy row (1900-01-01) would break the
--     no-gaps requirement of a marked date table, which is worth more than
--     avoiding a NULL foreign key.
--   * is_complete_month: Olist's first months are a pilot (2016-09: 4 orders,
--     2016-10: 324, 2016-12: 1) and the last two are truncated (2018-09: 16,
--     2018-10: 4). Charting them draws a fake launch and a fake collapse. The
--     flag is 1 for 2017-01 .. 2018-08 and is meant as the default dashboard
--     filter. Same rule as sql/05_revenue_seasonality.sql (is_partial_month);
--     a reconciliation test asserts both agree.
--   * Month and weekday names are in Spanish because they are display values
--     of a Spanish dashboard; the *_sort / numeric columns exist so the BI tool
--     sorts them chronologically instead of alphabetically.
-- ============================================================================

CREATE OR REPLACE TABLE dim_date AS
WITH bounds AS (
    -- whole calendar years around every date the fact table points at
    SELECT
        make_date(year(min(d))::BIGINT,  1,  1) AS first_day,
        make_date(year(max(d))::BIGINT, 12, 31) AS last_day
    FROM (
        SELECT order_purchase_timestamp      AS d FROM stg_orders
        UNION ALL
        SELECT order_delivered_customer_date AS d FROM stg_orders
        UNION ALL
        SELECT order_estimated_delivery_date AS d FROM stg_orders
    )
),

days AS (
    SELECT unnest(generate_series(first_day::TIMESTAMP,
                                  last_day::TIMESTAMP,
                                  INTERVAL 1 DAY))::DATE AS full_date
    FROM bounds
),

monthly AS (
    -- same population as sql/05_revenue_seasonality.sql
    SELECT
        date_trunc('month', o.order_purchase_timestamp)::DATE AS month_start,
        count(DISTINCT o.order_id)                            AS orders
    FROM stg_orders      AS o
    JOIN stg_order_value AS v ON v.order_id = o.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY 1
),

complete_months AS (
    SELECT month_start
    FROM monthly
    WHERE orders >= 500
      AND month_start <> (SELECT min(month_start) FROM monthly)
      AND month_start <> (SELECT max(month_start) FROM monthly)
)

SELECT
    CAST(strftime(d.full_date, '%Y%m%d') AS INTEGER)            AS date_key,
    d.full_date,

    -- year / quarter
    year(d.full_date)::INTEGER                                  AS year,
    quarter(d.full_date)::INTEGER                               AS quarter,
    year(d.full_date)::VARCHAR || '-T' || quarter(d.full_date)::VARCHAR
                                                                AS year_quarter,

    -- month
    month(d.full_date)::INTEGER                                 AS month,
    (['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
      'septiembre', 'octubre', 'noviembre', 'diciembre'])[month(d.full_date)]
                                                                AS month_name,
    date_trunc('month', d.full_date)::DATE                      AS month_start,
    (year(d.full_date) * 100 + month(d.full_date))::INTEGER     AS year_month_sort,
    (['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago',
      'sep', 'oct', 'nov', 'dic'])[month(d.full_date)]
        || ' ' || year(d.full_date)::VARCHAR                    AS year_month,

    -- week / day
    weekofyear(d.full_date)::INTEGER                            AS iso_week,
    day(d.full_date)::INTEGER                                   AS day_of_month,
    isodow(d.full_date)::INTEGER                                AS day_of_week,   -- 1 = lunes
    (['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado',
      'domingo'])[isodow(d.full_date)]                          AS day_name,
    (isodow(d.full_date) >= 6)::INTEGER                         AS is_weekend,

    -- data coverage
    (cm.month_start IS NOT NULL)::INTEGER                       AS is_complete_month
FROM days AS d
LEFT JOIN complete_months AS cm
       ON cm.month_start = date_trunc('month', d.full_date)::DATE
ORDER BY d.full_date;
