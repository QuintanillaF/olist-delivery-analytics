-- ============================================================================
-- star/00_ref_states.sql  —  reference data: the 27 Brazilian states
--
-- WHAT THIS DOES
--   Olist only carries the two-letter state code (UF). A BI tool needs more:
--     state_name  readable label for axes and slicers
--     state_iso   ISO 3166-2 code ('BR-SP'), which map visuals geocode without
--                 guessing (a bare 'SP' or 'PA' is ambiguous worldwide)
--     region      the five IBGE macro-regions, for a region > state > city
--                 drill-down
--
-- WHY A VIEW AND NOT A DIMENSION
--   This is a build helper, not a table of the star. Its columns are
--   denormalised INTO dim_customer and dim_seller. A shared geography table
--   hanging off two dimensions would turn the star into a snowflake: one more
--   join for the BI user, and nothing gained at 27 rows.
-- ============================================================================

CREATE OR REPLACE VIEW ref_br_states AS
SELECT *
FROM (VALUES
    ('AC', 'Acre',                'Norte'),
    ('AP', 'Amapá',               'Norte'),
    ('AM', 'Amazonas',            'Norte'),
    ('PA', 'Pará',                'Norte'),
    ('RO', 'Rondônia',            'Norte'),
    ('RR', 'Roraima',             'Norte'),
    ('TO', 'Tocantins',           'Norte'),
    ('AL', 'Alagoas',             'Nordeste'),
    ('BA', 'Bahia',               'Nordeste'),
    ('CE', 'Ceará',               'Nordeste'),
    ('MA', 'Maranhão',            'Nordeste'),
    ('PB', 'Paraíba',             'Nordeste'),
    ('PE', 'Pernambuco',          'Nordeste'),
    ('PI', 'Piauí',               'Nordeste'),
    ('RN', 'Rio Grande do Norte', 'Nordeste'),
    ('SE', 'Sergipe',             'Nordeste'),
    ('DF', 'Distrito Federal',    'Centro-Oeste'),
    ('GO', 'Goiás',               'Centro-Oeste'),
    ('MT', 'Mato Grosso',         'Centro-Oeste'),
    ('MS', 'Mato Grosso do Sul',  'Centro-Oeste'),
    ('ES', 'Espírito Santo',      'Sudeste'),
    ('MG', 'Minas Gerais',        'Sudeste'),
    ('RJ', 'Rio de Janeiro',      'Sudeste'),
    ('SP', 'São Paulo',           'Sudeste'),
    ('PR', 'Paraná',              'Sul'),
    ('RS', 'Rio Grande do Sul',   'Sul'),
    ('SC', 'Santa Catarina',      'Sul')
) AS t (state, state_name, region);
