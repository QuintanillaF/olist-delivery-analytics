-- ============================================================================
-- star/02_dim_customer.sql  —  customer dimension
--
-- GRAIN
--   One row per Olist customer_id (99,441 rows).
--
-- THE TRAP IN THIS TABLE: customer_id IS NOT A PERSON
--   Olist mints a fresh customer_id for every order. It is a snapshot of the
--   buyer at the moment of that purchase - delivery address included. The
--   person is customer_unique_id (96,096 of them).
--
--   So the grain here is "the customer as of one order", and that is on
--   purpose: it behaves like a Type 2 slowly changing dimension that the
--   source already versioned for us. 250 people ordered from more than one
--   zip prefix (39 from more than one state); with one row per person and
--   their latest address (Type 1) those orders would be reported in the wrong
--   state - and "late deliveries by customer state" is exactly the kind of
--   chart this model exists for.
--
--   customer_unique_id stays as an attribute. Count customers with
--   DISTINCTCOUNT(customer_unique_id), never by counting rows or customer_id.
--
-- KEY
--   customer_key: integer surrogate key. The natural key (customer_id, a
--   32-char hash) is kept as an attribute for traceability back to the source,
--   but the fact table joins on the integer.
--
-- DECISIONS
--   * Every customer_id of the source is here, including the 775 whose order
--     has no items and therefore no row in the fact table. A dimension
--     describes the entity, not the facts that happen to reference it.
--   * State attributes (name, ISO code, region) are denormalised from
--     ref_br_states - see star/00_ref_states.sql for why not a separate table.
--   * customer_lifetime_orders / is_repeat_customer are attributes of the
--     PERSON, repeated on each of their rows. Same rule as
--     sql/03_repeat_customers.sql (orders with status <> 'canceled'), and a
--     reconciliation test asserts the 3.1% repeat rate comes out identical.
--     They are lifetime values: they do not react to a date filter.
--   * customer_city is the raw source value (lowercase, no accents, some
--     misspellings). It is not cleaned because no measure depends on it.
-- ============================================================================

CREATE OR REPLACE TABLE dim_customer AS
WITH person_orders AS (
    SELECT
        c.customer_unique_id,
        count(*) AS lifetime_orders
    FROM stg_orders    AS o
    JOIN stg_customers AS c ON c.customer_id = o.customer_id
    WHERE o.order_status <> 'canceled'
    GROUP BY c.customer_unique_id
)

SELECT
    row_number() OVER (ORDER BY c.customer_id)::INTEGER    AS customer_key,
    c.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    s.state_name                                           AS customer_state_name,
    'BR-' || c.customer_state                              AS customer_state_iso,
    s.region                                               AS customer_region,
    c.zip_prefix                                           AS customer_zip_prefix,
    coalesce(p.lifetime_orders, 0)::INTEGER                AS customer_lifetime_orders,
    (coalesce(p.lifetime_orders, 0) >= 2)::INTEGER         AS is_repeat_customer
FROM stg_customers      AS c
LEFT JOIN ref_br_states AS s ON s.state = c.customer_state
LEFT JOIN person_orders AS p ON p.customer_unique_id = c.customer_unique_id
ORDER BY customer_key;
