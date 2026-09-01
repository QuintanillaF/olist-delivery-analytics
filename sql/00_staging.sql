-- ============================================================================
-- 00_staging.sql  —  cleaned views that every analysis query builds on
--
-- WHAT THIS DOES
--   Run once (src.db.build_staging) right after the 9 raw Kaggle CSVs are
--   loaded. It creates a set of stg_* views that centralise every
--   data-quality decision, so the analysis files (01..06) stay about
--   business logic instead of repeating the same cleaning CTEs.
--
-- RAW TABLES (loaded verbatim from the Kaggle CSVs)
--   olist_orders_dataset            olist_order_items_dataset
--   olist_order_reviews_dataset     olist_order_payments_dataset
--   olist_customers_dataset         olist_sellers_dataset
--   olist_products_dataset          olist_geolocation_dataset
--   product_category_name_translation
--
-- DATA-QUALITY ISSUES HANDLED HERE (full write-up in README > Data quality)
--   * order_reviews has ~550 order_ids with more than one review row, and
--     review_id is not unique either -> de-duplicated to one row per order.
--   * Some delivered orders have order_delivered_customer_date < purchase
--     timestamp (timestamp corruption) -> flagged, not dropped, so each
--     analysis can decide.
--   * Some order_status = 'delivered' rows have a NULL delivery date -> flagged.
--   * geolocation has many GPS points per zip prefix, a few off-continent
--     -> collapsed to one robust (median) point per prefix, Brazil bbox only.
--   * product category names are Portuguese -> joined to the English
--     translation table; unmatched / NULL categories become 'unknown'.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Orders. No rows dropped here. Timestamps kept as-is; two quality flags added.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW stg_orders AS
SELECT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date,

    -- delivered, and we have both ends of the clock, and time runs forwards
    (order_status = 'delivered'
     AND order_delivered_customer_date IS NOT NULL
     AND order_purchase_timestamp     IS NOT NULL
     AND order_delivered_customer_date >= order_purchase_timestamp) AS is_clean_delivered,

    (order_delivered_customer_date IS NOT NULL
     AND order_delivered_customer_date < order_purchase_timestamp)  AS f_delivered_before_purchase,

    (order_status = 'delivered'
     AND order_delivered_customer_date IS NULL)                     AS f_delivered_status_no_date
FROM olist_orders_dataset;

-- ----------------------------------------------------------------------------
-- Reviews. De-duplicate to exactly one row per order_id: keep the most recent
-- answer (then most recent creation date as a tie-break).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW stg_order_reviews AS
SELECT * EXCLUDE (rn)
FROM (
    SELECT
        r.*,
        row_number() OVER (
            PARTITION BY order_id
            ORDER BY review_answer_timestamp DESC NULLS LAST,
                     review_creation_date     DESC NULLS LAST
        ) AS rn
    FROM olist_order_reviews_dataset AS r
)
WHERE rn = 1;

-- ----------------------------------------------------------------------------
-- Order items. One row per (order_id, order_item_id). Attach the English
-- category name; fall back to the Portuguese name, then to 'unknown'.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW stg_order_items AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    oi.shipping_limit_date,
    oi.price,
    oi.freight_value,
    p.product_category_name                          AS category_pt,
    coalesce(t.product_category_name_english,
             p.product_category_name,
             'unknown')                              AS category
FROM olist_order_items_dataset AS oi
LEFT JOIN olist_products_dataset AS p
       ON p.product_id = oi.product_id
LEFT JOIN product_category_name_translation AS t
       ON t.product_category_name = p.product_category_name;

-- ----------------------------------------------------------------------------
-- Order-level revenue roll-up (items + freight), so revenue questions don't
-- have to re-aggregate items every time.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW stg_order_value AS
SELECT
    order_id,
    count(*)                       AS n_items,
    count(DISTINCT seller_id)      AS n_sellers,
    sum(price)                     AS items_value,
    sum(freight_value)             AS freight_value,
    sum(price + freight_value)     AS order_revenue
FROM stg_order_items
GROUP BY order_id;

-- ----------------------------------------------------------------------------
-- Geolocation. Collapse to one point per zip prefix. Median is robust to the
-- handful of clearly wrong coordinates; Brazil bounding box filters the rest.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW stg_geolocation AS
SELECT
    geolocation_zip_code_prefix        AS zip_prefix,
    median(geolocation_lat)            AS lat,
    median(geolocation_lng)            AS lng
FROM olist_geolocation_dataset
WHERE geolocation_lat BETWEEN -34.0 AND  6.0
  AND geolocation_lng BETWEEN -74.0 AND -34.0
GROUP BY geolocation_zip_code_prefix;

-- ----------------------------------------------------------------------------
-- Customers / sellers. Passthrough, shorter column names.
-- customer_id      = one per order (join key to orders)
-- customer_unique_id = the actual person (join key for repeat-purchase work)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW stg_customers AS
SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix AS zip_prefix,
    customer_city,
    customer_state
FROM olist_customers_dataset;

CREATE OR REPLACE VIEW stg_sellers AS
SELECT
    seller_id,
    seller_zip_code_prefix AS zip_prefix,
    seller_city,
    seller_state
FROM olist_sellers_dataset;
