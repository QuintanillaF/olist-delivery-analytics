-- ============================================================================
-- star/99_tests.sql  —  data tests for the star schema
--
-- WHAT THIS RETURNS
--   One row per test: (n, test, failures). A test passes when failures = 0.
--   src/star.py runs this file after building the star and refuses to export
--   anything if a single test fails - a BI tool must never be handed a table
--   that has not been checked.
--
-- WHAT IS TESTED, AND WHY THOSE THINGS
--   1. Keys and grain        every table has the grain it claims
--   2. Referential integrity every fact row finds its dimension rows
--   3. Reconciliation        the star adds up to the source, to the cent
--   4. Order-level facts     the devices that prevent double counting hold
--   5. Flattened view        the Looker Studio table is the same data
--   6. Lateness assumption   the promised date is a day, with no time of day
--
--   The join fan-out test (fact rows = source rows) is the one that matters
--   most: a duplicated dimension key silently multiplies revenue, and no chart
--   will ever show it.
--
-- NOT HERE
--   Agreement with the analysis queries (sql/01..06) is checked in
--   src/star.py, because it has to execute those files to compare.
-- ============================================================================

WITH order_level AS (
    -- per order: how many different values each order-level column takes
    -- (must be exactly 1) and what the weights add up to (must be exactly 1)
    SELECT
        order_id,
        sum(order_weight)                                    AS weight_sum,
        count(DISTINCT order_status)                         AS n_status,
        count(DISTINCT customer_key)                         AS n_customer,
        count(DISTINCT purchase_date_key)                    AS n_purchase,
        count(DISTINCT coalesce(review_score, -1))           AS n_review,
        count(DISTINCT coalesce(days_vs_estimate, -99999))   AS n_days,
        count(DISTINCT delivery_bucket)                      AS n_bucket,
        count(DISTINCT is_delivered)                         AS n_delivered
    FROM fct_order_items
    GROUP BY order_id
),

t AS (
    -- 1. keys and grain ------------------------------------------------------
    SELECT 1 AS n, 'dim_date: date_key is unique' AS test,
           (count(*) - count(DISTINCT date_key))::BIGINT AS failures
    FROM dim_date
    UNION ALL
    SELECT 2, 'dim_date: no gaps between the first and the last day',
           ((date_diff('day', min(full_date), max(full_date)) + 1) - count(*))::BIGINT
    FROM dim_date
    UNION ALL
    SELECT 3, 'dim_date: covers whole calendar years',
           ((strftime(min(full_date), '%m%d') <> '0101')::INT
          + (strftime(max(full_date), '%m%d') <> '1231')::INT)::BIGINT
    FROM dim_date
    UNION ALL
    SELECT 4, 'dim_customer: customer_key is unique',
           (count(*) - count(DISTINCT customer_key))::BIGINT
    FROM dim_customer
    UNION ALL
    SELECT 5, 'dim_customer: exactly one row per source customer_id',
           ((count(*) - count(DISTINCT customer_id))
            + abs(count(*) - (SELECT count(*) FROM olist_customers_dataset)))::BIGINT
    FROM dim_customer
    UNION ALL
    SELECT 6, 'dim_seller: seller_key is unique',
           (count(*) - count(DISTINCT seller_key))::BIGINT
    FROM dim_seller
    UNION ALL
    SELECT 7, 'dim_seller: exactly one row per source seller_id',
           ((count(*) - count(DISTINCT seller_id))
            + abs(count(*) - (SELECT count(*) FROM olist_sellers_dataset)))::BIGINT
    FROM dim_seller
    UNION ALL
    SELECT 8, 'dim_product: product_key is unique',
           (count(*) - count(DISTINCT product_key))::BIGINT
    FROM dim_product
    UNION ALL
    SELECT 9, 'dim_product: exactly one row per source product_id',
           ((count(*) - count(DISTINCT product_id))
            + abs(count(*) - (SELECT count(*) FROM olist_products_dataset)))::BIGINT
    FROM dim_product
    UNION ALL
    SELECT 10, 'fct_order_items: (order_id, order_item_id) is unique',
           (count(*) - count(DISTINCT (order_id, order_item_id)))::BIGINT
    FROM fct_order_items
    UNION ALL
    SELECT 11, 'fct_order_items: same row count as the source (no join fan-out, no lost lines)',
           abs(count(*) - (SELECT count(*) FROM olist_order_items_dataset))::BIGINT
    FROM fct_order_items

    -- 2. referential integrity ----------------------------------------------
    UNION ALL
    SELECT 12, 'fct_order_items: no NULL in the mandatory keys',
           count(*) FILTER (WHERE customer_key IS NULL
                               OR seller_key IS NULL
                               OR product_key IS NULL
                               OR purchase_date_key IS NULL
                               OR estimated_delivery_date_key IS NULL)::BIGINT
    FROM fct_order_items
    UNION ALL
    SELECT 13, 'fct_order_items: every customer_key exists in dim_customer',
           count(*)::BIGINT
    FROM fct_order_items AS f
    WHERE NOT EXISTS (SELECT 1 FROM dim_customer AS d WHERE d.customer_key = f.customer_key)
    UNION ALL
    SELECT 14, 'fct_order_items: every seller_key exists in dim_seller',
           count(*)::BIGINT
    FROM fct_order_items AS f
    WHERE NOT EXISTS (SELECT 1 FROM dim_seller AS d WHERE d.seller_key = f.seller_key)
    UNION ALL
    SELECT 15, 'fct_order_items: every product_key exists in dim_product',
           count(*)::BIGINT
    FROM fct_order_items AS f
    WHERE NOT EXISTS (SELECT 1 FROM dim_product AS d WHERE d.product_key = f.product_key)
    UNION ALL
    SELECT 16, 'fct_order_items: every date key (3 roles) exists in dim_date',
           count(*)::BIGINT
    FROM (
        SELECT purchase_date_key AS k FROM fct_order_items
        UNION ALL
        SELECT delivered_date_key FROM fct_order_items WHERE delivered_date_key IS NOT NULL
        UNION ALL
        SELECT estimated_delivery_date_key FROM fct_order_items
    ) AS f
    WHERE NOT EXISTS (SELECT 1 FROM dim_date AS d WHERE d.date_key = f.k)
    UNION ALL
    SELECT 17, 'dim_customer: every state has a name, an ISO code and a region',
           count(*) FILTER (WHERE customer_state_name IS NULL
                               OR customer_state_iso IS NULL
                               OR customer_region IS NULL)::BIGINT
    FROM dim_customer
    UNION ALL
    SELECT 18, 'dim_seller: every seller has a state name, a region and a segment',
           count(*) FILTER (WHERE seller_state_name IS NULL
                               OR seller_region IS NULL
                               OR seller_segment IS NULL
                               OR seller_segment_sort IS NULL)::BIGINT
    FROM dim_seller

    -- 3. reconciliation with the source ---------------------------------------
    UNION ALL
    SELECT 19, 'fct_order_items: sum(price) equals the source, to the cent',
           (abs(sum(price) - (SELECT sum(price) FROM olist_order_items_dataset)) > 0.005)::BIGINT
    FROM fct_order_items
    UNION ALL
    SELECT 20, 'fct_order_items: sum(freight_value) equals the source, to the cent',
           (abs(sum(freight_value) - (SELECT sum(freight_value) FROM olist_order_items_dataset)) > 0.005)::BIGINT
    FROM fct_order_items
    UNION ALL
    SELECT 21, 'fct_order_items: orders = source orders that have at least one item',
           abs(count(DISTINCT order_id)
               - (SELECT count(DISTINCT order_id) FROM olist_order_items_dataset))::BIGINT
    FROM fct_order_items
    UNION ALL
    SELECT 22, 'fct_order_items: delivered orders = clean delivered orders in staging',
           abs(count(DISTINCT order_id) FILTER (WHERE is_delivered = 1)
               - (SELECT count(*) FROM stg_orders WHERE is_clean_delivered))::BIGINT
    FROM fct_order_items
    UNION ALL
    SELECT 23, 'fct_order_items: reviewed orders = staging reviews of orders with items',
           abs(count(DISTINCT order_id) FILTER (WHERE review_score IS NOT NULL)
               - (SELECT count(*)
                  FROM stg_order_reviews AS r
                  WHERE EXISTS (SELECT 1 FROM olist_order_items_dataset AS i
                                WHERE i.order_id = r.order_id)))::BIGINT
    FROM fct_order_items
    UNION ALL
    SELECT 24, 'fct_order_items: category through dim_product = category in staging',
           count(*)::BIGINT
    FROM fct_order_items AS f
    JOIN dim_product     AS p ON p.product_key = f.product_key
    JOIN stg_order_items AS s ON s.order_id = f.order_id AND s.order_item_id = f.order_item_id
    WHERE p.category IS DISTINCT FROM s.category

    -- 4. order-level facts on a line-grain table ------------------------------
    UNION ALL
    SELECT 25, 'fct_order_items: order_weight adds up to exactly 1 per order',
           count(*) FILTER (WHERE abs(weight_sum - 1) > 1e-9)::BIGINT
    FROM order_level
    UNION ALL
    SELECT 26, 'fct_order_items: order-level columns are constant within an order',
           count(*) FILTER (WHERE n_status <> 1 OR n_customer <> 1 OR n_purchase <> 1
                               OR n_review <> 1 OR n_days <> 1 OR n_bucket <> 1
                               OR n_delivered <> 1)::BIGINT
    FROM order_level
    UNION ALL
    SELECT 27, 'fct_order_items: flags are 0/1 and never NULL',
           count(*) FILTER (WHERE is_canceled  NOT IN (0, 1) OR is_canceled  IS NULL
                               OR is_delivered NOT IN (0, 1) OR is_delivered IS NULL
                               OR is_on_time   NOT IN (0, 1) OR is_on_time   IS NULL
                               OR is_late      NOT IN (0, 1) OR is_late      IS NULL)::BIGINT
    FROM fct_order_items
    UNION ALL
    SELECT 28, 'fct_order_items: delivered = on time + late (every delivery is classified)',
           count(*) FILTER (WHERE is_on_time + is_late <> is_delivered)::BIGINT
    FROM fct_order_items
    UNION ALL
    SELECT 29, 'fct_order_items: days_late is filled exactly for late orders, and is positive',
           count(*) FILTER (WHERE (is_late = 1) <> (days_late IS NOT NULL)
                               OR days_late <= 0
                               OR days_late <> days_vs_estimate)::BIGINT
    FROM fct_order_items
    UNION ALL
    SELECT 30, 'fct_order_items: delivery_bucket agrees with the flags',
           count(*) FILTER (WHERE (delivery_bucket_sort = 7) <> (is_delivered = 0)
                               OR (delivery_bucket_sort BETWEEN 4 AND 6) <> (is_late = 1)
                               OR (delivery_bucket_sort BETWEEN 1 AND 3) <> (is_on_time = 1))::BIGINT
    FROM fct_order_items
    UNION ALL
    SELECT 31, 'fct_order_items: item_total = price + freight_value',
           count(*) FILTER (WHERE abs(item_total - (price + freight_value)) > 0.005)::BIGINT
    FROM fct_order_items
    UNION ALL
    SELECT 32, 'fct_order_items: review_score is NULL or between 1 and 5',
           count(*) FILTER (WHERE review_score NOT BETWEEN 1 AND 5)::BIGINT
    FROM fct_order_items

    -- 5. flattened view -------------------------------------------------------
    UNION ALL
    SELECT 33, 'order_items_flat: exactly the rows of the fact table',
           abs(count(*) - (SELECT count(*) FROM fct_order_items))::BIGINT
    FROM order_items_flat
    UNION ALL
    SELECT 34, 'order_items_flat: sum(item_total) equals the fact table',
           (abs(sum(item_total) - (SELECT sum(item_total) FROM fct_order_items)) > 0.005)::BIGINT
    FROM order_items_flat

    -- 6. the assumption the lateness rule rests on ------------------------------
    -- "Delivered on the promised day = on time" is right because the promise is
    -- a day. If a refresh ever brings promised dates with a time of day, an
    -- order delivered after that time would be late and the rule in
    -- stg_orders.is_late has to be revisited - this test makes that loud.
    UNION ALL
    SELECT 35, 'stg_orders: the promised date never carries a time of day',
           count(*) FILTER (WHERE order_estimated_delivery_date
                                  <> date_trunc('day', order_estimated_delivery_date))::BIGINT
    FROM stg_orders
)

SELECT n, test, failures
FROM t
ORDER BY n;
