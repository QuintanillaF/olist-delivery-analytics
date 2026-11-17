-- ============================================================================
-- star/03_dim_seller.sql  —  seller dimension
--
-- GRAIN
--   One row per seller_id (3,095 rows).
--
-- KEY
--   seller_key: integer surrogate key. seller_id (32-char hash) is kept as an
--   attribute. seller_code ('V0001') is a short display label: sellers are
--   anonymised in the dataset, and a 32-char hash is unreadable in a table
--   visual.
--
-- DECISIONS
--   * seller_segment is the segmentation of sql/04_seller_segmentation.sql,
--     stored as a dimension attribute so the dashboard can slice any measure
--     by it. Same rules, first match wins:
--         En riesgo    avg review < 3.5  OR  > 25% of orders shipped late
--         Núcleo       >= 50 orders, <= 10% shipped late, avg review >= 4.0
--         En ascenso    < 50 orders, <= 10% shipped late, avg review >= 4.0
--         Estable      everyone else
--     "Shipped late" = handed to the carrier after shipping_limit_date: the
--     seller's own SLA, not the carrier's transit time.
--     A reconciliation test asserts sellers and GMV per segment match the
--     analysis query.
--   * The lifetime_* columns are the inputs of that rule, kept so the segment
--     can be explained seller by seller. They are computed over the whole
--     dataset and do NOT react to dashboard filters - hence the prefix. For
--     anything that must follow a date filter, use a measure on the fact.
--   * A segment computed from facts and stored on a dimension is a deliberate
--     trade-off: it is a snapshot of behaviour (stable label, cheap to filter)
--     rather than a live calculation (correct for any period, expensive and
--     confusing when a seller changes segment as the date slicer moves).
--   * State attributes are denormalised from ref_br_states.
-- ============================================================================

CREATE OR REPLACE TABLE dim_seller AS
WITH seller_order AS (
    -- collapse items to one row per (seller, order)
    SELECT
        oi.seller_id,
        oi.order_id,
        sum(oi.price)                             AS order_items_value,
        max(oi.shipping_limit_date)               AS shipping_limit_date,
        any_value(o.order_delivered_carrier_date) AS carrier_date
    FROM stg_order_items AS oi
    JOIN stg_orders      AS o ON o.order_id = oi.order_id
    GROUP BY oi.seller_id, oi.order_id
),

seller_metrics AS (
    SELECT
        so.seller_id,
        count(*)                                           AS orders,
        round(sum(so.order_items_value), 2)                AS gmv,
        avg((so.carrier_date > so.shipping_limit_date)::INT)
            FILTER (WHERE so.carrier_date IS NOT NULL)     AS pct_shipped_late,
        avg(r.review_score)                                AS avg_review_score
    FROM seller_order AS so
    LEFT JOIN stg_order_reviews AS r ON r.order_id = so.order_id
    GROUP BY so.seller_id
),

segmented AS (
    SELECT
        *,
        CASE
            WHEN avg_review_score < 3.5
              OR coalesce(pct_shipped_late, 1) > 0.25   THEN 'En riesgo'
            WHEN orders >= 50
             AND coalesce(pct_shipped_late, 1) <= 0.10
             AND avg_review_score >= 4.0                THEN 'Núcleo'
            WHEN orders <  50
             AND coalesce(pct_shipped_late, 1) <= 0.10
             AND avg_review_score >= 4.0                THEN 'En ascenso'
            ELSE                                             'Estable'
        END AS seller_segment
    FROM seller_metrics
),

keyed AS (
    SELECT
        row_number() OVER (ORDER BY seller_id)::INTEGER AS seller_key,
        *
    FROM stg_sellers
)

SELECT
    k.seller_key,
    k.seller_id,
    'V' || lpad(k.seller_key::VARCHAR, 4, '0')       AS seller_code,
    k.seller_city,
    k.seller_state,
    s.state_name                                     AS seller_state_name,
    'BR-' || k.seller_state                          AS seller_state_iso,
    s.region                                         AS seller_region,
    k.zip_prefix                                     AS seller_zip_prefix,
    m.seller_segment,
    CASE m.seller_segment
        WHEN 'Núcleo'     THEN 1
        WHEN 'En ascenso' THEN 2
        WHEN 'Estable'    THEN 3
        WHEN 'En riesgo'  THEN 4
    END::INTEGER                                     AS seller_segment_sort,
    m.orders::INTEGER                                AS lifetime_orders,
    m.gmv                                            AS lifetime_gmv,
    round(m.pct_shipped_late, 4)                     AS lifetime_pct_shipped_late,
    round(m.avg_review_score, 3)                     AS lifetime_avg_review_score
FROM keyed              AS k
LEFT JOIN ref_br_states AS s ON s.state = k.seller_state
LEFT JOIN segmented     AS m ON m.seller_id = k.seller_id
ORDER BY k.seller_key;
