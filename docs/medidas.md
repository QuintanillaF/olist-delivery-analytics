# Medidas del dashboard

Definición de cada indicador, escrita dos veces: en **DAX** para Power BI y como
**campo calculado** para Looker Studio. La definición de negocio es una sola; lo que
cambia es la sintaxis y, en un caso señalado abajo, la técnica.

| Herramienta | Qué lee | Dónde se escriben las medidas |
|---|---|---|
| Power BI | las cinco tablas de la estrella (`data/bi/power_bi/*.parquet`) | medidas DAX sobre `fct_order_items` |
| Looker Studio | la tabla plana (`data/bi/looker_studio/order_items_flat.csv`) | campos calculados en la fuente de datos |

El modelo está explicado en [`modelo_estrella.md`](modelo_estrella.md).

---

## Tres reglas antes de escribir una medida

**1. La tabla tiene una fila por línea de pedido, pero la entrega y la reseña son del
pedido.** Un pedido de tres ítems aparece tres veces con la misma calificación y el
mismo atraso. Estas columnas **nunca se suman ni se promedian directamente**:
`review_score`, `days_late`, `days_vs_estimate`, `days_to_deliver`, `is_delivered`,
`is_on_time`, `is_late`, `is_canceled`.

**2. Los pedidos se cuentan con `order_id` distinto**, nunca contando filas.

**3. Las definiciones de negocio ya vienen resueltas en columnas 0/1.** Qué es "a
tiempo", "tarde" o "cancelado" se decidió en SQL; las medidas sólo agregan.

Las columnas de la línea sí se pueden sumar: `price`, `freight_value`, `item_total`.

---

## Medidas base

Los cinco indicadores se apoyan en estos tres conteos.

**DAX**

```dax
Pedidos =
CALCULATE (
    DISTINCTCOUNT ( fct_order_items[order_id] ),
    fct_order_items[is_canceled] = 0
)

Pedidos entregados =
CALCULATE (
    DISTINCTCOUNT ( fct_order_items[order_id] ),
    fct_order_items[is_delivered] = 1
)

Pedidos a tiempo =
CALCULATE (
    DISTINCTCOUNT ( fct_order_items[order_id] ),
    fct_order_items[is_on_time] = 1
)
```

**Looker Studio**

```
Pedidos             COUNT_DISTINCT(CASE WHEN is_canceled = 0 THEN order_id END)
Pedidos entregados  COUNT_DISTINCT(CASE WHEN is_delivered = 1 THEN order_id END)
Pedidos a tiempo    COUNT_DISTINCT(CASE WHEN is_on_time = 1 THEN order_id END)
```

`Pedidos` excluye los cancelados (`canceled`, `unavailable`): es el denominador del
ticket promedio y tiene que ser la misma población que las ventas.

---

## Los cinco indicadores

### 1. % Entregas a tiempo

**Definición.** De los pedidos entregados, qué proporción llegó el día prometido o
antes. Se comparan días calendario: entregar a cualquier hora del día prometido es
llegar a tiempo.

**DAX**

```dax
% Entregas a tiempo =
DIVIDE ( [Pedidos a tiempo], [Pedidos entregados] )
```

**Looker Studio**

```
COUNT_DISTINCT(CASE WHEN is_on_time = 1 THEN order_id END)
/ COUNT_DISTINCT(CASE WHEN is_delivered = 1 THEN order_id END)
```

**Formato.** Porcentaje, un decimal.

**Por qué así.** El denominador son los entregados, no todos los pedidos: un pedido en
tránsito todavía no cumplió ni incumplió. Se cuentan pedidos distintos porque sumar la
bandera contaría líneas (7.264 líneas tardías contra 6.534 pedidos tardíos).

### 2. Días promedio de atraso

**Definición.** Entre los pedidos que llegaron tarde, cuántos días después de la fecha
prometida llegaron, en promedio.

**DAX**

```dax
Días promedio de atraso =
CALCULATE (
    AVERAGEX (
        SUMMARIZE (
            fct_order_items,
            fct_order_items[order_id],
            fct_order_items[days_late]
        ),
        fct_order_items[days_late]
    ),
    fct_order_items[is_late] = 1
)
```

**Looker Studio**

```
SUM(days_late * order_weight)
/ SUM(CASE WHEN is_late = 1 THEN order_weight ELSE 0 END)
```

**Formato.** Número, un decimal.

**Por qué así.** Sólo los tardíos: el promedio sobre todas las entregas da −11,9 días
(en promedio llegan casi doce días *antes* de lo prometido), un número que esconde el
problema en vez de medirlo. Esa versión con signo existe como medida auxiliar.

`SUMMARIZE` arma una tabla de una fila por pedido con su atraso, y `AVERAGEX` promedia
esas filas: el promedio es por pedido, no por línea. Looker Studio no tiene una función
que itere sobre pedidos, así que llega al mismo resultado con `order_weight`
(`1 / líneas del pedido`): cada pedido aporta en total un peso de 1.

### 3. Calificación promedio

**Definición.** Promedio de la calificación (1 a 5) de los pedidos que tienen reseña.
Un pedido, una calificación.

**DAX**

```dax
Calificación promedio =
CALCULATE (
    AVERAGEX (
        SUMMARIZE (
            fct_order_items,
            fct_order_items[order_id],
            fct_order_items[review_score]
        ),
        fct_order_items[review_score]
    ),
    NOT ISBLANK ( fct_order_items[review_score] )
)
```

**Looker Studio**

```
SUM(review_score * order_weight)
/ SUM(CASE WHEN review_score IS NOT NULL THEN order_weight ELSE 0 END)
```

**Formato.** Número, dos decimales.

**Por qué así.** `AVERAGE(review_score)` sobre las líneas da 4,03; por pedido da 4,10.
Los pedidos de varios ítems pesarían de más, y son los que peor califican.

### 4. Ventas

**Definición.** Lo que pagaron los clientes: precio de los ítems más flete, de los
pedidos que no fueron cancelados.

**DAX**

```dax
Ventas =
CALCULATE (
    SUM ( fct_order_items[item_total] ),
    fct_order_items[is_canceled] = 0
)
```

**Looker Studio**

```
SUM(CASE WHEN is_canceled = 0 THEN item_total ELSE 0 END)
```

**Formato.** Moneda, reales (R$), sin decimales.

**Por qué así.** `item_total` es un hecho de la línea, así que acá sí corresponde un
`SUM` directo. Incluye el flete porque es la definición de ingresos del análisis
(`sql/05_revenue_seasonality.sql`). Los cancelados se excluyen con la bandera en lugar
de borrarlos de la tabla: sumar todo daría R$ 15.843.553, unos R$ 108.000 de más.

### 5. Ticket promedio

**Definición.** Ventas dividido cantidad de pedidos: cuánto paga un cliente por pedido.

**DAX**

```dax
Ticket promedio =
DIVIDE ( [Ventas], [Pedidos] )
```

**Looker Studio**

```
SUM(CASE WHEN is_canceled = 0 THEN item_total ELSE 0 END)
/ COUNT_DISTINCT(CASE WHEN is_canceled = 0 THEN order_id END)
```

**Formato.** Moneda, reales (R$), dos decimales.

**Por qué así.** Es un cociente de dos agregados, no un promedio de filas:
`AVERAGE(item_total)` daría R$ 140,64, que es el valor promedio de un *ítem*, no de un
pedido. Numerador y denominador usan la misma población (no cancelados).

---

## Valores de control

Si una medida está bien escrita, tiene que dar exactamente esto. "Meses completos" es
el filtro por defecto del dashboard (`is_complete_month = 1`, de enero de 2017 a agosto
de 2018).

| Medida | Sin filtros | Meses completos | Año 2017 | Año 2018 |
|---|---:|---:|---:|---:|
| Pedidos | 98.199 | 97.905 | 44.375 | 53.531 |
| Pedidos entregados | 96.470 | 96.203 | 43.426 | 52.777 |
| Pedidos a tiempo | 89.936 | 89.672 | 40.973 | 48.699 |
| **% Entregas a tiempo** | **93,23%** | **93,21%** | **94,35%** | **92,27%** |
| **Días promedio de atraso** | **10,6** | **10,6** | **11,8** | **9,9** |
| **Calificación promedio** | **4,10** | **4,11** | **4,11** | **4,10** |
| **Ventas** | **R$ 15.735.527** | **R$ 15.683.707** | **R$ 7.090.569** | **R$ 8.593.304** |
| **Ticket promedio** | **R$ 160,24** | **R$ 160,19** | **R$ 159,79** | **R$ 160,53** |

Los años se filtran por fecha de compra. Cada valor se calculó en SQL por dos caminos
independientes (la lógica de cada fórmula sobre las tablas exportadas, y una consulta
directa sobre las vistas de staging a nivel pedido) y coinciden en todos los casos. Las
medidas escritas en cada herramienta se validan contra esta tabla al cargar el
dashboard por primera vez.

---

## Medidas auxiliares

Las usan los gráficos de [`dashboard.md`](dashboard.md).

**DAX**

```dax
Pedidos tarde =
CALCULATE (
    DISTINCTCOUNT ( fct_order_items[order_id] ),
    fct_order_items[is_late] = 1
)

% Entregas tarde =
DIVIDE ( [Pedidos tarde], [Pedidos entregados] )

Días promedio de entrega =
CALCULATE (
    AVERAGEX (
        SUMMARIZE (
            fct_order_items,
            fct_order_items[order_id],
            fct_order_items[days_to_deliver]
        ),
        fct_order_items[days_to_deliver]
    ),
    fct_order_items[is_delivered] = 1
)

Días vs. fecha prometida =
CALCULATE (
    AVERAGEX (
        SUMMARIZE (
            fct_order_items,
            fct_order_items[order_id],
            fct_order_items[days_vs_estimate]
        ),
        fct_order_items[days_vs_estimate]
    ),
    fct_order_items[is_delivered] = 1
)

% Despacho tardío =
DIVIDE (
    CALCULATE (
        DISTINCTCOUNT ( fct_order_items[order_id] ),
        fct_order_items[is_shipped_late] = 1
    ),
    CALCULATE (
        DISTINCTCOUNT ( fct_order_items[order_id] ),
        NOT ISBLANK ( fct_order_items[is_shipped_late] )
    )
)

Vendedores =
DISTINCTCOUNT ( fct_order_items[seller_key] )

Clientes =
CALCULATE (
    DISTINCTCOUNT ( dim_customer[customer_unique_id] ),
    FILTER ( fct_order_items, fct_order_items[is_canceled] = 0 )
)
```

**Looker Studio**

```
Pedidos tarde             COUNT_DISTINCT(CASE WHEN is_late = 1 THEN order_id END)

% Entregas tarde          COUNT_DISTINCT(CASE WHEN is_late = 1 THEN order_id END)
                          / COUNT_DISTINCT(CASE WHEN is_delivered = 1 THEN order_id END)

Días promedio de entrega  SUM(days_to_deliver * order_weight)
                          / SUM(CASE WHEN is_delivered = 1 THEN order_weight ELSE 0 END)

Días vs. fecha prometida  SUM(days_vs_estimate * order_weight)
                          / SUM(CASE WHEN is_delivered = 1 THEN order_weight ELSE 0 END)

% Despacho tardío         COUNT_DISTINCT(CASE WHEN is_shipped_late = 1 THEN order_id END)
                          / COUNT_DISTINCT(CASE WHEN is_shipped_late IS NOT NULL THEN order_id END)

Vendedores                COUNT_DISTINCT(seller_code)

Clientes                  COUNT_DISTINCT(CASE WHEN is_canceled = 0 THEN customer_unique_id END)
```

| Medida | Sin filtros | Meses completos |
|---|---:|---:|
| Pedidos tarde | 6.534 | 6.531 |
| % Entregas tarde | 6,77% | 6,79% |
| Días promedio de entrega | 12,5 | 12,5 |
| Días vs. fecha prometida | −11,9 | −11,8 |
| % Despacho tardío | 9,07% | 8,96% |
| Vendedores | 3.095 | 3.068 |
| Clientes | 94.983 | 94.703 |

`Clientes` cuenta personas (`customer_unique_id`), no `customer_id`: Olist genera un
`customer_id` nuevo en cada pedido, así que contarlos daría la cantidad de pedidos. En
DAX el `FILTER` sobre la tabla de hechos limita la dimensión a los clientes que tienen
al menos un pedido no cancelado en el contexto actual.

`% Despacho tardío` usa `NOT ISBLANK` en el denominador, y no una comparación con cero,
porque `is_shipped_late` está vacío cuando el pedido no tiene fecha de despacho y en
DAX un valor en blanco también cumple `= 0`.

---

## Fechas: tres roles (sólo Power BI)

`dim_date` se relaciona tres veces con la tabla de hechos. La relación activa es la de
la fecha de compra: todas las medidas de arriba se ubican en el mes en que se compró.
Para mirar por otra fecha, la relación se activa dentro de la medida:

```dax
Pedidos entregados (por fecha de entrega) =
CALCULATE (
    [Pedidos entregados],
    USERELATIONSHIP ( fct_order_items[delivered_date_key], dim_date[date_key] )
)
```

Control: en agosto de 2018 se *compraron* 6.351 pedidos que terminaron entregados, y
se *entregaron* 8.314.

Con `dim_date` marcada como tabla de fechas, las comparaciones en el tiempo son una
línea:

```dax
Ventas mes anterior =
CALCULATE ( [Ventas], DATEADD ( dim_date[full_date], -1, MONTH ) )

Ventas var. % mensual =
DIVIDE ( [Ventas] - [Ventas mes anterior], [Ventas mes anterior] )
```

Control: noviembre de 2017 vendió R$ 1.172.192 contra R$ 764.756 de octubre: +53,3%.

En Looker Studio no hace falta fórmula: la tabla plana trae las tres fechas como
columnas (`purchase_date`, `delivered_date`, `estimated_delivery_date`), cada gráfico
elige cuál usa como dimensión de período, y la comparación con el período anterior es
una opción del gráfico.

---

## Una diferencia conocida entre las dos herramientas

Los promedios por pedido (`Calificación promedio` y las tres medidas de días) se
calculan con técnicas distintas:

- **DAX** itera sobre los pedidos: exacto en cualquier corte.
- **Looker Studio** pondera con `order_weight`: exacto mientras el corte no parta un
  pedido.

Cortar por fecha, estado del cliente o estado del pedido nunca parte un pedido, y ahí
las dos herramientas dan el mismo número. Cortar por **vendedor, segmento de vendedor
o categoría** sí puede partirlo: un pedido con ítems de dos vendedores cuenta entero
para cada uno en DAX, y repartido entre sus líneas en Looker Studio. Como esos pedidos
compartidos son los peor calificados, el promedio de Looker Studio queda levemente
más alto.

Diferencia medida en la calificación promedio, meses completos:

| Segmento de vendedor | Power BI | Looker Studio |
|---|---:|---:|
| Núcleo | 4,24 | 4,24 |
| En ascenso | 4,41 | 4,42 |
| Estable | 3,99 | 3,99 |
| En riesgo | 3,56 | 3,58 |

Por categoría la diferencia llega a 0,06 y para un vendedor individual a 0,14. Los
conteos y porcentajes (`% Entregas a tiempo`, `% Entregas tarde`, `Pedidos`) usan
pedidos distintos en las dos herramientas y coinciden siempre.

---

## Errores típicos, con el número que delata cada uno

Todos sin filtros.

| Si la medida se escribe así… | …da | Correcto | Qué pasó |
|---|---:|---:|---|
| contar filas como pedidos | 112.650 | 98.666 | se contaron líneas |
| `SUM(is_late)` | 7.264 | 6.534 | líneas tardías, no pedidos tardíos |
| `AVERAGE(review_score)` | 4,03 | 4,10 | promedio por línea |
| `AVERAGE(days_late)` | 10,5 | 10,6 | promedio por línea |
| `SUM(is_on_time) / SUM(is_delivered)` | 93,41% | 93,23% | porcentaje de líneas |
| `SUM(item_total)` sin la bandera | R$ 15.843.553 | R$ 15.735.527 | entraron los cancelados |
| `AVERAGE(item_total)` como ticket | R$ 140,64 | R$ 160,24 | valor por ítem, no por pedido |
| contar `customer_id` como clientes | 98.199 | 94.983 | se contaron pedidos |
