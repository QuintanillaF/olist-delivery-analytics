# Guía del proyecto, desde cero

Esta guía explica **todo el proyecto suponiendo que no sabés nada** de SQL, bases de
datos ni análisis de datos. Al final hay una sección sobre cómo contarlo en una
entrevista.

---

## 1. ¿De qué va el proyecto?

**Olist** es una empresa brasileña que conecta tiendas chicas con los grandes
marketplaces (como Mercado Libre pero en Brasil). Cuando alguien compra, el pedido pasa
por Olist, lo despacha un vendedor, lo lleva un correo, y al final el cliente **deja una
reseña de 1 a 5 estrellas**.

Olist publicó en Kaggle (una web de datasets públicos) una foto de su operación: ~100.000
pedidos entre 2016 y 2018, con toda la información asociada — quién compró, qué, a qué
vendedor, cuánto tardó, qué reseña dejó.

**La pregunta del proyecto:** ¿qué hace que un cliente ponga 5 estrellas o 1 estrella?
¿Cuánto le cuesta a Olist cuando la cosa sale mal? ¿Qué debería cambiar?

No es un ejercicio de "mostrar gráficos lindos". Cada análisis termina en **una decisión
concreta** que un gerente de Olist podría tomar el lunes.

---

## 2. ¿Qué son "los datos"?

Son **9 archivos CSV** (archivos de texto con filas y columnas, como un Excel). Cada uno
es una **tabla**:

| Archivo | Qué guarda | Filas |
|---|---|---|
| `olist_orders_dataset` | un pedido por fila: fechas de compra, aprobación, despacho, entrega, y la fecha **estimada** de entrega | 99.441 |
| `olist_order_items_dataset` | un ítem por fila: qué producto, qué vendedor, precio, flete | 112.650 |
| `olist_order_reviews_dataset` | la reseña de cada pedido (nota 1–5, comentario, fechas) | 99.224 |
| `olist_order_payments_dataset` | cómo se pagó cada pedido | 103.886 |
| `olist_customers_dataset` | los clientes (y un ID que identifica a la **persona real**) | 99.441 |
| `olist_sellers_dataset` | los vendedores | 3.095 |
| `olist_products_dataset` | los productos (categoría, peso, dimensiones) | 32.951 |
| `olist_geolocation_dataset` | coordenadas (lat/long) por prefijo de código postal | 1.000.163 |
| `product_category_name_translation` | traducción de las categorías de portugués a inglés | 71 |

Se llama **base de datos relacional** porque las tablas se **relacionan** entre sí por
columnas compartidas. Ejemplo: `olist_orders_dataset` tiene una columna `customer_id`, y
`olist_customers_dataset` tiene la misma columna — así podés "pegar" (hacer un **JOIN**)
la info del pedido con la info del cliente.

```
orders (pedido)  --- customer_id --->  customers (cliente)
       \--- order_id --->  reviews (reseña)
       \--- order_id --->  order_items (ítems)  --- seller_id --->  sellers (vendedor)
                                                \--- product_id --->  products (producto)
```

---

## 3. El stack (las herramientas), explicado

### ¿Qué es SQL?

**SQL** ("Structured Query Language") es el idioma para hacerle preguntas a una base de
datos. Una pregunta se llama **consulta** o **query**. Se lee casi como inglés:

```sql
SELECT customer_state, count(*) AS pedidos
FROM olist_orders_dataset AS o
JOIN olist_customers_dataset AS c ON c.customer_id = o.customer_id
WHERE order_status = 'delivered'
GROUP BY customer_state
ORDER BY pedidos DESC;
```

Traducción: "traeme el estado del cliente y la cantidad de pedidos, tomando la tabla de
pedidos y pegándole la de clientes por `customer_id`, quedándote sólo con los entregados,
agrupando por estado, y ordenando de mayor a menor". El resultado es una tabla nueva.

SQL es **la habilidad central** que este proyecto demuestra. Por eso las consultas están
en archivos `.sql` que se pueden leer, y no escondidas dentro de código Python.

### ¿Qué es DuckDB?

Una **base de datos** normal (PostgreSQL, MySQL) es un programa servidor que corre todo
el tiempo. **DuckDB** es una base de datos que vive **dentro de un solo archivo**
(`data/olist.duckdb`) y no necesita servidor. Es ideal para análisis: cargás unos CSV,
le tirás SQL, y es rapidísima. Piensa en ella como "SQLite para análisis" o "pandas pero
con SQL de verdad".

### ¿Por qué SQL en archivos y no adentro de Python?

Se podría hacer todo con la librería pandas de Python. Pero entonces un reclutador que
mira el proyecto no ve SQL — ve código Python. **El objetivo es demostrar SQL**, así que
las consultas viven en `sql/` donde se leen solas, y Python sólo:
1. carga los CSV a DuckDB (`src/db.py`),
2. lee un archivo `.sql`, lo ejecuta, y devuelve el resultado como tabla (`src/queries.py`),
3. dibuja los gráficos (`src/plots.py`).

### ¿Qué es un notebook?

`notebooks/olist_analysis.ipynb` es un **cuaderno de Jupyter**: un documento que mezcla
texto explicativo, código que se puede ejecutar, y los resultados (tablas y gráficos)
justo debajo. Es la forma estándar de contar un análisis como una historia: pregunta →
consulta → resultado → qué significa. Se abre con Jupyter, VS Code, o se ve directo en
GitHub.

### ¿Qué hace cada carpeta?

```
sql/          Las consultas. 00_staging.sql primero (limpieza), después 01..06 (los análisis).
src/          El código Python de apoyo:
              - config.py   rutas de archivos + la paleta de colores de los gráficos
              - db.py       carga los 9 CSV a DuckDB y corre la limpieza
              - queries.py  "ejecutá este .sql y devolveme una tabla"
              - plots.py    una función de gráfico por pregunta, con un estilo común
notebooks/    El cuaderno narrativo.
scripts/      download_data.py: baja los CSV de Kaggle (o te dice cómo hacerlo a mano).
figures/      Los 7 gráficos .png que genera el proyecto (van incrustados en el README).
data/         Los CSV crudos (en data/raw/) y la base .duckdb. NO se sube a git (pesan mucho).
run_all.py    Un comando que hace TODO: CSV → base → consultas → gráficos → notebook.
```

---

## 4. ¿Cómo funciona todo junto? (el "pipeline")

```
   9 CSV crudos
        │   src/db.py  →  read_csv_auto()
        ▼
   9 tablas en DuckDB
        │   sql/00_staging.sql
        ▼
   vistas "stg_*" ya limpias   ← acá se aplican TODAS las decisiones de limpieza
        │   sql/01..06  (vía src/queries.py)
        ▼
   13 tablas de resultados
        │   src/plots.py
        ▼
   7 gráficos .png  +  el notebook ejecutado
```

Una **vista** (`VIEW`) es una consulta guardada con nombre que se comporta como si fuera
una tabla. `stg_orders`, `stg_order_reviews`, etc. son versiones "limpias" de las tablas
crudas. Los análisis 01–06 nunca tocan los CSV crudos directamente: siempre parten de las
vistas `stg_*`. Así la limpieza está en **un solo lugar** y no repetida en cada consulta.

---

## 5. La limpieza de datos ("data quality")

Los datos reales son un desastre y hay que decidir qué hacer con cada problema — **y
documentarlo**, porque cada decisión puede cambiar los resultados. Lo que se encontró en
Olist:

- **Reseñas duplicadas.** 547 pedidos tienen 2 filas de reseña. Decisión: quedarse con la
  más reciente. (Si no hacés nada, esos pedidos pesan doble en los promedios.)
- **Pedidos "entregados" sin fecha de entrega.** 8 casos. Se excluyen del análisis de
  tiempos con un flag llamado `is_clean_delivered`.
- **Categorías en portugués.** Hay una tabla de traducción, pero le faltan 2 categorías y
  610 productos no tienen categoría. Lo que no matchea se marca como `unknown`.
- **Coordenadas basura.** La tabla de geolocalización tiene varios puntos GPS por código
  postal, y algunos caen fuera de Brasil (error de carga). Se colapsa a **la mediana** de
  lat/long por prefijo postal, filtrando lo que está fuera del recuadro de Brasil.
- **2016 es un piloto.** Septiembre 2016 tiene 2 pedidos, diciembre 1. No es "el negocio
  arrancando", es una prueba. Se marca y se excluye de la tendencia.

Todo esto está en `sql/00_staging.sql` (con comentarios) y resumido en el README y el
notebook.

---

## 6. Las seis preguntas, en criollo

Antes, tres conceptos que aparecen todo el tiempo:

- **Correlación / "Pearson r".** Un número entre −1 y +1 que mide si dos cosas se mueven
  juntas. +1 = cuando una sube la otra sube siempre. −1 = cuando una sube la otra baja
  siempre. 0 = no tienen relación. −0,33 = hay una relación negativa moderada.
- **Mediana vs promedio.** El promedio se distorsiona con valores extremos; la mediana
  (el valor del medio) no. Si 9 entregas tardan 5 días y una tarda 300, el promedio es 34
  pero la mediana es 5.
- **Correlación ≠ causalidad.** Que dos cosas se muevan juntas no prueba que una cause la
  otra. Las entregas tardías coinciden con productos frágiles, zonas remotas y vendedores
  malos — cualquiera de esos podría ser el verdadero culpable de la mala reseña.

### Q1 — ¿El tiempo de entrega predice la nota? ([`sql/01_*`](sql/))

**Qué se preguntó.** ¿A más demora, peor reseña? ¿Es una bajada gradual o hay un punto
donde se desploma?

**Cómo se midió.** Para cada pedido entregado: días de entrega = fecha de entrega −
fecha de compra. Se agrupan los pedidos en tramos (0–3 días, 4–7, …, 46+) y se calcula la
nota promedio y el % de reseñas de 1 estrella en cada tramo. Después se repite pero
midiendo contra la **fecha prometida** (días de entrega − fecha estimada).

**Qué dio.** La nota se mantiene ~4,2 hasta unos 20 días y después **cae a pique**: 3,6 a
los 21–30 días, 2,3 a los 31–45, 1,8 más allá. Y contra la promesa el precipicio es más
filoso todavía: en fecha ≈ 4,0; **1–5 días tarde → 2,99**; **6–10 tarde → 1,77** (68% de
1 estrella).

**Qué significa.** El cliente no juzga "¿tardó mucho?" sino "¿cumplieron lo que me
prometieron?". Un solo día de atraso sobre la fecha prometida cuesta casi una estrella
entera.

**Decisión.** Detectar los pedidos que van a incumplir **antes** de que pase la fecha, y
avisar / compensar de forma preventiva. No sirve acelerar los que ya llegan bien.

### Q2 — ¿Qué categorías entregan peor y cuánto cuesta? ([`sql/02_*`](sql/02_category_delivery_performance.sql))

**Qué se preguntó.** ¿Qué tipos de producto incumplen más seguido su fecha prometida, y
cuántos puntos de reseña se pierden por eso?

**Cómo se midió.** Por categoría: % de pedidos entregados después de la fecha prometida,
y la diferencia de nota entre los que llegaron en fecha y los que llegaron tarde. Ese
"gap" multiplicado por el % de atrasos y por el volumen de la categoría = daño total en
reseñas.

**Qué dio.** Todas las categorías, en promedio, **le ganan** a su estimación (por 10–15
días). O sea: el problema no es el promedio, es la **cola** de pedidos que sí llegan
tarde (4–13% según la categoría). `audio` es la que más incumple (12,8%). Pero el mayor
daño *total* está en las categorías de volumen (salud/belleza, cama/baño): misma tasa de
atraso que el promedio, pero sobre 6.000–9.000 pedidos.

**Decisión.** Dos cosas distintas: arreglar las rutas de `audio`/`electronics`
específicamente, y atacar la *tasa* de atraso en las categorías grandes (ahí un 1% de
mejora vale más que arreglar una categoría chica entera).

### Q3 — ¿Cuántos vuelven a comprar? ([`sql/03_*`](sql/))

**Qué se preguntó.** ¿Qué fracción hace un segundo pedido? ¿Los que tuvieron una mala
primera experiencia dejan de volver?

**Cómo se midió.** Usando el ID de la **persona real** (`customer_unique_id`, no el
`customer_id` que Olist genera nuevo por pedido). Se cuenta cuántos pedidos hizo cada
persona. Para la segunda parte: se identifica el primer pedido de cada uno, se mira la
nota que dejó, y se calcula qué % volvió, cortado por esa nota. Sólo se cuentan primeros
pedidos con al menos 120 días de ventana para volver (si no, penalizás injustamente a
quien compró en septiembre 2018).

**Qué dio.** **3,1% recompra alguna vez.** Y la tasa de recompra según la primera reseña
es **plana**: 1 estrella → 3,4%, 5 estrellas → 3,9%.

**Qué significa.** Olist, en este período, es un negocio de **una sola compra**. Una mala
primera experiencia no "cuesta un cliente futuro" porque casi no hay clientes futuros.

**Decisión.** El argumento para invertir en calidad de entrega tiene que basarse en la
economía del primer pedido (reseñas, reputación, ranking) y no en valor de vida del
cliente. No armar un programa de fidelización: no tendría con qué trabajar.

### Q4 — Segmentación de vendedores ([`sql/04_*`](sql/04_seller_segmentation.sql))

**Qué se preguntó.** Agrupar los ~3.000 vendedores por volumen, fiabilidad y reseñas.
¿En quién invertir, a quién soltar?

**Cómo se midió.** Por vendedor: cantidad de pedidos, facturación, % de pedidos que
despachó tarde (fecha de entrega al correo vs `shipping_limit_date` — esto es lo que el
vendedor **controla**; la demora del correo no es su culpa), y nota promedio. Después una
regla los clasifica en 4 grupos.

**Qué dio.**

| Segmento | Vendedores | % facturación | Despacha tarde | Reseña prom. |
|---|--:|--:|--:|--:|
| Núcleo — invertir | 233 | 37% | 3% | 4,27 |
| Estable — mantener | 627 | 33% | 11% | 3,97 |
| En ascenso — hacer crecer | 1.411 | 17% | **1%** | **4,57** |
| **En riesgo — arreglar o dar de baja** | **824** | **13%** | **39%** | **2,96** |

**Qué significa.** Los 824 "en riesgo" son un cuarto del padrón y sólo el 13% de la
facturación, pero incumplen su plazo de despacho el 39% de las veces y promedian 2,96
estrellas. Hacen mucho más daño reputacional del que aportan. Y los "en ascenso"
(vendedores chicos) despachan **mejor** que el núcleo.

**Decisión.** Poner a los 824 en probación (plazo de despacho obligatorio, límite de
publicaciones) y dar de baja a los que no mejoran. Darles lugar en el buscador y soporte
de onboarding a los "en ascenso", no exprimir a los 233 del núcleo.

### Q5 — Estacionalidad y crecimiento ([`sql/05_*`](sql/05_revenue_seasonality.sql))

**Qué se preguntó.** ¿Cómo evolucionaron los ingresos y los pedidos mes a mes? ¿Hay
tendencia de crecimiento? ¿Anomalías?

**Cómo se midió.** Ingresos por mes = suma de (precio + flete) de todos los pedidos de
ese mes. Se calcula el crecimiento mes contra mes y contra enero 2017 (= base 100). Para
anomalías: días cuyo número de pedidos se aleja más de 3 desvíos estándar del promedio
diario (un **z-score** de 3 significa "muy raro").

**Qué dio.** El historial útil es enero 2017 – agosto 2018. Creció **~8×** durante 2017 y
después **quedó plano todo 2018** (incluso bajando en el segundo semestre). El ticket
promedio nunca se movió (~R$160): todo el crecimiento fue por volumen, no por carritos
más grandes. La única anomalía real: **Black Friday 2017** (24 de noviembre: 1.166
pedidos en un día, +11 desvíos, R$178k en 24 horas).

**Qué significa.** El titular no es "estacionalidad", es que **el crecimiento se
frenó**. Combinado con la Q3 (nadie recompra), adquisición plana = negocio plano.

**Decisión.** El freno de crecimiento de 2018 necesita su propia investigación (¿por qué
dejó de entrar gente nueva?). Black Friday se captura como evento de un día pero no deja
clientes.

### Q6 — ¿La distancia explica los retrasos? ([`sql/06_*`](sql/))

**Qué se preguntó.** ¿Los pedidos llegan tarde porque el vendedor está lejos del
cliente, o hay otra cosa?

**Cómo se midió.** Distancia = fórmula de **haversine** (distancia sobre la esfera
terrestre) entre las coordenadas del vendedor y las del cliente. Después se comparan dos
correlaciones: distancia vs **tiempo de tránsito**, y distancia vs **atraso contra la
promesa**. Y se mira el desglose por estado.

**Qué dio.** La distancia predice fuerte el **tiempo de tránsito** (r = 0,39; ~6 días por
cada 1.000 km) pero **no el atraso contra la promesa** (r = −0,08, básicamente cero).
¿Por qué? Porque la fecha estimada de Olist **ya incorpora la distancia**: la ventana
prometida va de ~20 días para São Paulo a 40–47 para los estados del Amazonas, y esos
clientes lejanos le ganan a la estimación por 17–20 días. El **tiempo de despacho del
vendedor** predice el atraso ~2,5× mejor que la distancia. Los estados con más retrasos
reales no son los lejanos: son los de la **costa nordeste a distancia media** (Alagoas
24% tarde), donde la ventana quedó muy ajustada.

**Qué significa.** La distancia manda cuánto *tarda*, pero no cuán *tarde* llega respecto
de lo prometido. Construir depósitos regionales para el norte lejano sería gastar en
clientes que ya están contentos.

**Decisión.** Dos palancas reales: hacer cumplir los plazos de despacho de los
vendedores, y ampliar la ventana prometida para los estados de la costa nordeste (AL,
MA, PI, CE, SE) unos 5–7 días, o arreglar esas rutas de transporte puntuales.

---

## 7. Cómo correrlo, paso a paso

1. **Instalar Python 3.10 o más nuevo** (python.org). Tildar "Add to PATH" al instalar.
2. Abrir PowerShell en la carpeta del proyecto y crear un entorno aislado:
   ```powershell
   python -m venv .venv
   .venv\Scripts\Activate.ps1
   ```
   (Un "entorno virtual" es una carpeta con una copia de Python y sus librerías, para no
   ensuciar el Python del sistema.)
3. Instalar las librerías:
   ```powershell
   pip install -r requirements.txt
   ```
4. Conseguir los datos: descargar el ZIP de
   https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce (pide login gratis) y
   descomprimir los 9 CSV en `data/raw/`. O, si tenés credenciales de Kaggle configuradas:
   `python scripts/download_data.py`.
5. Correr todo:
   ```powershell
   python run_all.py
   ```
   Esto reconstruye la base, ejecuta las 13 consultas, regenera los 7 gráficos, y ejecuta
   el notebook. Tarda ~1–2 minutos.

Para explorar a mano: abrir `notebooks/olist_analysis.ipynb` en VS Code (con la extensión
de Jupyter) o corriendo `jupyter notebook`.

---

## 8. Cómo contar esto en una entrevista

**El pitch de 30 segundos:**

> "Analicé el dataset público de Olist, un marketplace brasileño con 100.000 pedidos.
> Todo el trabajo de datos es SQL sobre DuckDB, en archivos versionados; Python sólo
> orquesta y grafica. Respondí seis preguntas de negocio, cada una terminando en una
> recomendación. El hallazgo principal: la satisfacción del cliente no baja gradual con
> la demora, se desploma en el momento exacto en que se incumple la fecha prometida — un
> día de atraso cuesta casi una estrella. Eso cambia la recomendación operativa: no
> optimizar el promedio, sino detectar e intervenir los incumplimientos antes de que
> pase la fecha."

**Preguntas que te van a hacer y cómo responderlas:**

- *"¿Por qué DuckDB y no pandas / un data warehouse?"* — DuckDB da SQL real sin montar
  infraestructura; el dataset entra en memoria. Para un análisis reproducible de una sola
  máquina es la herramienta correcta. Si esto fuera producción con datos en la nube, sería
  BigQuery o Snowflake, mismo SQL.

- *"¿Cómo sabés que la demora causa la mala reseña y no al revés / o una tercera causa?"*
  — No lo sé, y está escrito en Limitaciones. Es una correlación de −0,33. La demora
  coincide con productos dañados y zonas remotas. Lo que sí es robusto es el **umbral**:
  el quiebre exacto en la fecha prometida es difícil de explicar por una tercera variable.

- *"El 3% de recompra, ¿no es porque los datos terminan en 2018?"* — En parte sí, por eso
  la Q3 usa una ventana de 120 días para dar una oportunidad justa de volver a cada
  cliente. Aun así 3% es muy bajo; y Olist vende a través de muchas tiendas, así que el
  cliente puede no percibir la marca "Olist".

- *"¿Por qué agrupaste los vendedores con esas reglas y no con un clustering?"* — Porque
  la pregunta es una decisión (invertir/soltar), no un ejercicio de modelado. Reglas
  explícitas basadas en umbrales de negocio (50 pedidos, 10% de atraso, 4,0 de nota) son
  defendibles ante un gerente; un k-means no.

- *"¿Qué harías distinto con más tiempo?"* — Modelar el efecto de la demora controlando
  por categoría, región y valor del pedido (una regresión), para separar la asociación
  cruda del efecto ajustado. Y traer datos post-2018 para ver si la meseta de crecimiento
  se revirtió.

**Lo que este proyecto demuestra:** SQL (joins, CTEs, window functions, agregaciones
condicionales), pensamiento analítico (cada análisis va a una decisión), manejo de datos
sucios reales (y documentarlo), honestidad sobre limitaciones, y código ordenado y
reproducible.
