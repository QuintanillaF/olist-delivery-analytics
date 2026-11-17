-- ============================================================================
-- star/06_order_items_flat.sql  —  the star, flattened into one wide table
--
-- WHAT THIS IS
--   A view that joins the fact table to its four dimensions: one row per order
--   line, every attribute a chart could need already on the row ("one big
--   table"). It adds no logic of its own - every column comes from the star.
--
-- WHY IT EXISTS
--   Looker Studio has no data model. It can blend sources, but a blend is
--   capped at five tables, re-joins on every chart and cannot express a
--   role-playing date. So the two tools get the same model in the shape each
--   one is good at:
--       Power BI       -> the five star tables + relationships
--       Looker Studio  -> this single table
--   Both are exported from the same tables in the same run, and a test asserts
--   this view has exactly the rows of the fact: the two dashboards cannot
--   drift apart.
--
-- WHAT TO NOTICE
--   dim_date is joined three times under three aliases. That is the
--   role-playing dimension made explicit in SQL: one physical table, three
--   meanings (purchase / delivered / promised).
--
-- DECISIONS
--   * Only what a dashboard uses. The 32-char product_id, seller_id and
--     customer_id are left out (seller_code replaces seller_id);
--     customer_unique_id stays because "customers" is a distinct count of it.
--   * LEFT JOIN for the delivered date only: orders never delivered have no
--     delivered_date_key. The other joins are INNER on purpose - a missing
--     dimension row would drop lines and fail the row-count test loudly.
-- ============================================================================

CREATE OR REPLACE VIEW order_items_flat AS
SELECT
    -- order line
    f.order_id,
    f.order_item_id,
    f.order_status,

    -- dates (dim_date in its three roles)
    pd.full_date            AS purchase_date,
    pd.is_complete_month,
    dd.full_date            AS delivered_date,
    ed.full_date            AS estimated_delivery_date,

    -- customer
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    c.customer_state_name,
    c.customer_state_iso,
    c.customer_region,
    c.is_repeat_customer,

    -- seller
    s.seller_code,
    s.seller_city,
    s.seller_state,
    s.seller_state_name,
    s.seller_state_iso,
    s.seller_region,
    s.seller_segment,
    s.seller_segment_sort,

    -- product
    p.category,
    p.category_label,

    -- line-level facts
    f.price,
    f.freight_value,
    f.item_total,

    -- order-level facts (see star/05_fct_order_items.sql before aggregating)
    f.order_weight,
    f.is_canceled,
    f.is_delivered,
    f.is_on_time,
    f.is_late,
    f.delivery_bucket,
    f.delivery_bucket_sort,
    f.days_to_deliver,
    f.days_vs_estimate,
    f.days_late,
    f.review_score,
    f.is_shipped_late
FROM fct_order_items AS f
JOIN dim_date        AS pd ON pd.date_key    = f.purchase_date_key
LEFT JOIN dim_date   AS dd ON dd.date_key    = f.delivered_date_key
JOIN dim_date        AS ed ON ed.date_key    = f.estimated_delivery_date_key
JOIN dim_customer    AS c  ON c.customer_key = f.customer_key
JOIN dim_seller      AS s  ON s.seller_key   = f.seller_key
JOIN dim_product     AS p  ON p.product_key  = f.product_key;
