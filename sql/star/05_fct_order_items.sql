-- ============================================================================
-- star/05_fct_order_items.sql  —  the fact table
--
-- GRAIN
--   One row per order line: (order_id, order_item_id). 112,650 rows - exactly
--   the rows of the source order_items table, which a test asserts.
--
-- WHY THE LINE AND NOT THE ORDER
--   Product and seller belong to the LINE: 3,236 orders mix several products
--   and 1,278 mix several sellers. At order grain those orders would need
--   either a bridge table or an arbitrary "main" product/seller, and revenue
--   by category or by seller would be wrong for them. The line is the atomic
--   grain: it can always be rolled up to the order, never the other way round.
--
-- THE COST OF THAT CHOICE, AND HOW IT IS PAID
--   Delivery and review are facts of the ORDER, so here they repeat on every
--   line of the order. Summing or averaging them directly double-counts
--   multi-line orders (average review: 4.03 by line vs 4.10 by order - lines
--   of big orders are over-represented, and big orders rate worse).
--   Two devices make order-level measures safe on this table:
--     * counts and percentages use COUNT(DISTINCT order_id);
--     * averages are taken per order. DAX does it by iterating over the
--       distinct orders. Tools that can only SUM (Looker Studio) use
--       order_weight = 1 / lines in the order: every order adds up to a weight
--       of exactly 1, so a weighted average is an average per order. This is
--       the allocation Kimball prescribes for header facts on a line-grain
--       table.
--       Its limit: it is exact for any slice that keeps orders whole (date,
--       customer state, status). Sliced by seller or category, a shared order
--       is split across its lines, and since shared orders are the worst
--       rated the weighted average reads slightly high (up to 0.02 stars per
--       seller segment). Measured in docs/medidas.md.
--
-- KEYS
--   Three surrogate keys (customer, seller, product) and three date keys - the
--   same dim_date playing three roles (purchase, delivered, promised).
--   order_id / order_item_id are degenerate dimensions: identifiers with no
--   table of their own, needed to count orders and to trace a row back.
--
-- BUSINESS DEFINITIONS FROZEN HERE  (so no tool has to re-implement them)
--   * is_delivered  = stg_orders.is_clean_delivered: status 'delivered' with a
--     delivery date that is not before the purchase (96,470 of the 96,478
--     'delivered' orders; the other 8 have no delivery date).
--   * on time / late come from stg_orders.is_late, the single place where
--     lateness is defined: delivered on or before the promised CALENDAR DAY =
--     on time. The promised date is stored at 00:00:00, so a timestamp
--     comparison would call "delivered at 3 pm on the promised day" late;
--     1,292 orders are in that situation and their reviews (4.03) look like
--     on-time orders, not like late ones (2.99 for 1-5 days late). The tests
--     check that the delivery bands and days_late agree with that flag.
--   * days_late is NULL unless the order is late, so that its average is
--     "how late are the late ones" and is not diluted by early deliveries.
--     days_vs_estimate is the signed version (negative = early) for everyone.
--   * is_canceled = status 'canceled' or 'unavailable'. Rows are flagged, not
--     dropped: sales measures exclude them, a cancellation rate needs them.
--   * item_total = price + freight_value: what the customer paid for the line.
--     Same revenue definition as sql/05_revenue_seasonality.sql.
--   * is_shipped_late = handed to the carrier after the seller's shipping
--     limit (latest limit of that seller within the order, as in
--     sql/04_seller_segmentation.sql). NULL when there is no carrier date.
--   * Flags are 0/1 integers, not booleans: identical behaviour in DAX, in
--     Looker Studio and in a CSV, and they can be multiplied by order_weight.
--
-- WHAT IS NOT IN THIS TABLE
--   * 775 orders with no items (603 'unavailable', 164 'canceled', 8 other).
--     No line, so no row: they have no product, seller or amount. Their
--     reviews are therefore outside the model (average review 4.09 over all
--     orders vs 4.10 over orders with items).
--   * Payments. One order can have several payment rows (type, instalments) -
--     a different grain, so a different fact table, not extra columns here.
-- ============================================================================

CREATE OR REPLACE TABLE fct_order_items AS
WITH order_facts AS (
    -- one row per order: everything that is measured on the order as a whole
    SELECT
        o.order_id,
        o.customer_id,
        o.order_status,
        o.order_purchase_timestamp::DATE      AS purchase_date,
        o.order_delivered_customer_date::DATE AS delivered_date,
        o.order_estimated_delivery_date::DATE AS estimated_delivery_date,
        o.order_delivered_carrier_date        AS carrier_ts,
        o.is_clean_delivered,
        o.is_late,
        CASE WHEN o.is_clean_delivered
             THEN date_diff('day', o.order_purchase_timestamp,
                                   o.order_delivered_customer_date)
        END                                   AS days_to_deliver,
        CASE WHEN o.is_clean_delivered
             THEN date_diff('day', o.order_estimated_delivery_date,
                                   o.order_delivered_customer_date)
        END                                   AS days_vs_estimate,
        r.review_score
    FROM stg_orders             AS o
    LEFT JOIN stg_order_reviews AS r ON r.order_id = o.order_id   -- 1 row per order
),

lines AS (
    SELECT
        i.order_id,
        i.order_item_id,
        i.product_id,
        i.seller_id,
        i.price,
        i.freight_value,
        count(*) OVER (PARTITION BY i.order_id)                  AS lines_in_order,
        max(i.shipping_limit_date)
            OVER (PARTITION BY i.order_id, i.seller_id)          AS seller_shipping_limit
    FROM stg_order_items AS i
)

SELECT
    -- degenerate dimensions --------------------------------------------------
    l.order_id,
    l.order_item_id::INTEGER                                     AS order_item_id,

    -- dimension keys ---------------------------------------------------------
    CAST(strftime(f.purchase_date,           '%Y%m%d') AS INTEGER) AS purchase_date_key,
    CAST(strftime(f.delivered_date,          '%Y%m%d') AS INTEGER) AS delivered_date_key,
    CAST(strftime(f.estimated_delivery_date, '%Y%m%d') AS INTEGER) AS estimated_delivery_date_key,
    dc.customer_key,
    ds.seller_key,
    dp.product_key,

    -- order attributes -------------------------------------------------------
    f.order_status,
    CASE
        WHEN NOT f.is_clean_delivered  THEN 'No entregado'
        WHEN f.days_vs_estimate <= -10 THEN '10+ días antes'
        WHEN f.days_vs_estimate <    0 THEN '1 a 9 días antes'
        WHEN f.days_vs_estimate =    0 THEN 'El día prometido'
        WHEN f.days_vs_estimate <=   5 THEN '1 a 5 días tarde'
        WHEN f.days_vs_estimate <=  10 THEN '6 a 10 días tarde'
        ELSE                                '11+ días tarde'
    END                                                          AS delivery_bucket,
    CASE
        WHEN NOT f.is_clean_delivered  THEN 7
        WHEN f.days_vs_estimate <= -10 THEN 1
        WHEN f.days_vs_estimate <    0 THEN 2
        WHEN f.days_vs_estimate =    0 THEN 3
        WHEN f.days_vs_estimate <=   5 THEN 4
        WHEN f.days_vs_estimate <=  10 THEN 5
        ELSE                                6
    END::INTEGER                                                 AS delivery_bucket_sort,

    -- line-level facts (additive: safe to SUM) --------------------------------
    l.price,
    l.freight_value,
    round(l.price + l.freight_value, 2)                          AS item_total,

    -- order-level facts repeated on every line (never SUM/AVG these directly) -
    1.0 / l.lines_in_order                                       AS order_weight,
    (f.order_status IN ('canceled', 'unavailable'))::INTEGER     AS is_canceled,
    f.is_clean_delivered::INTEGER                                AS is_delivered,
    (f.is_clean_delivered AND NOT f.is_late)::INTEGER            AS is_on_time,
    (f.is_clean_delivered AND f.is_late)::INTEGER                AS is_late,
    f.days_to_deliver::INTEGER                                   AS days_to_deliver,
    f.days_vs_estimate::INTEGER                                  AS days_vs_estimate,
    CASE WHEN f.days_vs_estimate > 0
         THEN f.days_vs_estimate END::INTEGER                    AS days_late,
    f.review_score::INTEGER                                      AS review_score,

    -- shipment-level fact (seller x order) -----------------------------------
    (f.carrier_ts > l.seller_shipping_limit)::INTEGER            AS is_shipped_late
FROM lines             AS l
JOIN order_facts       AS f  ON f.order_id     = l.order_id
LEFT JOIN dim_customer AS dc ON dc.customer_id = f.customer_id
LEFT JOIN dim_seller   AS ds ON ds.seller_id   = l.seller_id
LEFT JOIN dim_product  AS dp ON dp.product_id  = l.product_id
ORDER BY l.order_id, l.order_item_id;
