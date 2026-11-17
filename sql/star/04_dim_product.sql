-- ============================================================================
-- star/04_dim_product.sql  —  product dimension
--
-- GRAIN
--   One row per product_id (32,951 rows).
--
-- KEY
--   product_key: integer surrogate key. product_id (32-char hash) is kept as
--   an attribute.
--
-- DECISIONS
--   * category follows the exact rule of stg_order_items (00_staging.sql):
--     English translation, else the Portuguese name, else 'unknown'. A test
--     asserts that every fact row reaches the same category through this
--     dimension as it has in staging, so the dashboard and the analysis
--     queries can never disagree on what a category is.
--       - 610 products have no category at all        -> 'unknown'
--       - 2 Portuguese categories have no translation -> Portuguese name kept
--   * category_label is the same value made presentable ('bed_bath_table' ->
--     'Bed bath table'). Presentation logic is done once here rather than in
--     every chart of every tool.
--   * Products are anonymous in Olist (no name, no brand, no price list), so
--     this dimension is thin by nature: the category is the only attribute a
--     business user would slice by. Weight, volume and photo count are kept
--     because they are true attributes of the product and cost nothing.
--   * No hierarchy above category. 74 values (73 categories + 'unknown') is
--     too many for a legend, but a hand-made "department" grouping would be an
--     invented attribute; the dashboard uses Top-N filters instead.
-- ============================================================================

CREATE OR REPLACE TABLE dim_product AS
WITH categorised AS (
    SELECT
        p.*,
        coalesce(t.product_category_name_english,
                 p.product_category_name,
                 'unknown') AS category
    FROM olist_products_dataset                 AS p
    LEFT JOIN product_category_name_translation AS t
           ON t.product_category_name = p.product_category_name
)

SELECT
    row_number() OVER (ORDER BY product_id)::INTEGER              AS product_key,
    product_id,
    category,
    upper(left(category, 1)) || replace(substr(category, 2), '_', ' ')
                                                                  AS category_label,
    product_category_name                                         AS category_pt,
    product_weight_g::INTEGER                                     AS product_weight_g,
    (product_length_cm * product_height_cm * product_width_cm)::INTEGER
                                                                  AS product_volume_cm3,
    product_photos_qty::INTEGER                                   AS product_photos_qty
FROM categorised
ORDER BY product_key;
