# Dashboard: diseño de las dos páginas y cómo armarlas

Dos páginas, cada una con una pregunta y un lector:

| Página | Pregunta que responde | Para quién |
|---|---|---|
| **1. Ventas** | ¿Cuánto vendemos, cómo viene la tendencia y de dónde sale? | quien mira el negocio |
| **2. Entregas y satisfacción** | ¿Cumplimos la fecha prometida, qué pasa cuando no, y dónde está el problema? | quien opera el marketplace |

La segunda es la tesis del repositorio llevada a un tablero: la fecha prometida es un
precipicio para la calificación. La primera da el contexto para leerla.

Las medidas que se nombran acá están definidas en [`medidas.md`](medidas.md) y el
modelo en [`modelo_estrella.md`](modelo_estrella.md).

---

## Qué herramienta usar

| | Power BI Desktop | Looker Studio |
|---|---|---|
| Qué muestra del trabajo | el modelo estrella con relaciones y las medidas DAX | el mismo tablero sobre una tabla plana |
| Datos | `data/bi/power_bi/*.parquet` (5 tablas) | `data/bi/looker_studio/order_items_flat.csv` |
| Cómo se comparte | el archivo `.pbix` y capturas. Publicar en la web exige una cuenta laboral o educativa; con un correo personal (Gmail, Outlook) no se puede | un enlace público, gratis |

No compiten: Power BI es donde se ve el modelado; Looker Studio es lo que alguien puede
abrir con un clic.

---

## Reglas de diseño, comunes a las dos páginas

1. **El mismo esqueleto en ambas.** Filtros arriba, una fila de cinco indicadores, un
   gráfico principal con dos tendencias chicas al lado, y dos desgloses abajo. Quien
   entendió una página ya sabe leer la otra.
2. **Se lee de arriba hacia abajo, de lo general a lo particular:** el número, su
   evolución, su desglose.
3. **Los filtros van en una sola fila arriba y afectan a todo.** Ningún gráfico tiene
   un filtro propio escondido, salvo los dos que se indican.
4. **Un solo eje por gráfico.** Ventas y pedidos tienen escalas distintas: en un
   gráfico de doble eje, dónde se cruzan las líneas depende de cómo se acomoden las
   escalas y sugiere una relación que no está en los datos. Van en gráficos separados
   que comparten el eje del tiempo.
5. **Sin tortas ni anillos.** Para comparar partes, barras horizontales ordenadas de
   mayor a menor: las longitudes sobre una misma base se comparan mejor que los ángulos.
6. **El color tiene un trabajo.** Un solo azul (`#2a78d6`) para todo lo que es una
   serie única. Azul contra rojo (`#e34948`) sólo donde hay polaridad: a tiempo contra
   tarde. Gris (`#c3c2b7`) para lo que es contexto. Son los colores de los gráficos del
   README (`src/config.py`).
7. **Filtro por defecto: meses completos** (enero de 2017 a agosto de 2018). Los meses
   del piloto y los dos truncados del final dibujan un despegue y un derrumbe falsos.

Lienzo de 1280 × 720 px (16:9), márgenes de 24 px, 12 px entre elementos.

**Filtros (los mismos en las dos páginas):** período · estado del cliente · categoría ·
segmento del vendedor.

Al filtrar por categoría o por segmento, los indicadores de entrega pasan a leerse
como "de los pedidos que incluyen esa categoría (o un vendedor de ese segmento)".

---

## Página 1 — Ventas

```
┌───────────────────────────────────────────────────────────────────────────────────────────┐
│ Ventas                              [Período] [Estado cliente] [Categoría] [Segmento]     │
├─────────────────┬─────────────────┬─────────────────┬─────────────────┬───────────────────┤
│ ① Ventas        │ ② Pedidos       │ ③ Ticket        │ ④ % Entregas    │ ⑤ Calificación    │
│   R$ 15,7 M     │   97.905        │   promedio      │   a tiempo      │   promedio        │
│                 │                 │   R$ 160,19     │   93,2 %        │   4,11            │
├─────────────────┴─────────────────┴────────────────┬┴─────────────────┴───────────────────┤
│ ⑥ Ventas por mes                                   │ ⑦ Pedidos por mes                    │
│   (línea)                                          │   (línea)                            │
│                                                    ├──────────────────────────────────────┤
│                                                    │ ⑧ Ticket promedio por mes            │
│                                                    │   (línea)                            │
├────────────────────────────────────────────────────┼──────────────────────────────────────┤
│ ⑨ Ventas por categoría — las 10 mayores            │ ⑩ Ventas por estado del cliente —    │
│   (barras horizontales)                            │   los 10 mayores (barras horiz.)     │
└────────────────────────────────────────────────────┴──────────────────────────────────────┘
```

| # | Gráfico | Campos | Por qué está y por qué ahí |
|---|---|---|---|
| ①②③ | Tarjetas | `Ventas`, `Pedidos`, `Ticket promedio` | Los tres números que definen la página, arriba a la izquierda, donde se empieza a leer. Van juntos porque están atados: ventas = pedidos × ticket. |
| ④⑤ | Tarjetas | `% Entregas a tiempo`, `Calificación promedio` | Dos indicadores de salud a la derecha de la fila. Avisan que hay una segunda página y evitan leer las ventas sin saber si la operación las sostiene. |
| ⑥ | Línea | eje: mes de compra · valor: `Ventas` | La pregunta que sigue a "cuánto" es "cómo viene". Es el gráfico más grande porque es el de la conclusión: las ventas se multiplican por ocho durante 2017 y quedan planas en 2018. Línea y no columnas: lo que importa es la forma de la serie. |
| ⑦⑧ | Dos líneas chicas | eje: mes · valores: `Pedidos` y `Ticket promedio` | Descomponen ⑥. Los pedidos copian la curva de las ventas; el ticket queda entre R$ 147 y R$ 174 todo el período. El crecimiento fue de volumen, no de precio. Apiladas y con el mismo eje de tiempo que ⑥ para compararlas con la vista. |
| ⑨ | Barras horizontales | eje: `category_label` · valor: `Ventas` · las 10 mayores | De dónde sale la venta, por producto. Horizontales para que entren los nombres. Diez y no las 74: las diez primeras concentran el 62% y el resto es cola. |
| ⑩ | Barras horizontales | eje: `customer_state_name` · valor: `Ventas` · los 10 mayores | De dónde sale la venta, por geografía. São Paulo solo es el 37%. Barras y no mapa: en un mapa São Paulo ocupa menos superficie que Amazonas, que vende casi nada. |

Qué tiene que verse (meses completos):

- ⑥ sube de R$ 136.943 (enero de 2017) a un pico de R$ 1.172.192 (noviembre de 2017,
  Black Friday) y oscila entre R$ 980.000 y R$ 1.160.000 en 2018.
- ⑦ va de 787 a 7.421 pedidos (noviembre de 2017).
- ⑨ Health beauty R$ 1.432.213 · Watches gifts R$ 1.294.824 · Bed bath table
  R$ 1.239.780 · Sports leisure R$ 1.144.754 · Computers accessories R$ 1.049.201.
- ⑩ São Paulo R$ 5.863.233 · Rio de Janeiro R$ 2.105.550 · Minas Gerais R$ 1.837.646.

---

## Página 2 — Entregas y satisfacción

```
┌───────────────────────────────────────────────────────────────────────────────────────────┐
│ Entregas y satisfacción             [Período] [Estado cliente] [Categoría] [Segmento]     │
├─────────────────┬─────────────────┬─────────────────┬─────────────────┬───────────────────┤
│ ① % Entregas    │ ② Pedidos       │ ③ Días promedio │ ④ Días promedio │ ⑤ Calificación    │
│   a tiempo      │   tarde         │   de atraso     │   de entrega    │   promedio        │
│   93,2 %        │   6.531         │   10,6          │   12,5          │   4,11            │
├─────────────────┴─────────────────┴────────────────┬┴─────────────────┴───────────────────┤
│ ⑥ Calificación promedio según cuándo llegó         │ ⑦ % Entregas a tiempo por mes        │
│   respecto de la fecha prometida                   │   (línea + línea de referencia)      │
│   (6 columnas: azul = a tiempo, rojo = tarde)      ├──────────────────────────────────────┤
│                                                    │ ⑧ Calificación promedio por mes      │
│                                                    │   (línea)                            │
├────────────────────────────────────────────────────┼──────────────────────────────────────┤
│ ⑨ % Entregas tarde por estado del cliente —        │ ⑩ Segmentos de vendedores            │
│   los 10 peores (barras; Nordeste resaltado)       │   (tabla)                            │
└────────────────────────────────────────────────────┴──────────────────────────────────────┘
```

| # | Gráfico | Campos | Por qué está y por qué ahí |
|---|---|---|---|
| ① | Tarjeta | `% Entregas a tiempo` | El indicador de la página, primero. |
| ②③ | Tarjetas | `Pedidos tarde`, `Días promedio de atraso` | El 6,8% que falla, en cantidad y en gravedad: cuántos son y por cuánto se pasan. Un porcentaje solo no dice ninguna de las dos cosas. |
| ④ | Tarjeta | `Días promedio de entrega` | Contexto: cuánto tarda una entrega normal. Separa "tardar" de "llegar tarde". |
| ⑤ | Tarjeta | `Calificación promedio` | El resultado que la entrega mueve. Cierra la fila porque es la consecuencia. |
| ⑥ | Columnas | eje: `delivery_bucket` (ordenado por `delivery_bucket_sort`) · valor: `Calificación promedio` · sólo entregados | El hallazgo central, en el lugar más grande. La calificación se mantiene por encima de 4 mientras el pedido llega en fecha y cae a 2,99 en cuanto se pasa. Columnas porque son categorías ordenadas; dos colores porque hay un umbral y el color lo marca. |
| ⑦⑧ | Dos líneas chicas | eje: mes · valores: `% Entregas a tiempo` y `Calificación promedio` | La misma relación, en el tiempo. Los tres meses en que la puntualidad se hunde (noviembre de 2017, febrero y marzo de 2018) son los tres en que cae la calificación. Apiladas para que los pozos queden alineados. ⑦ lleva una línea de referencia en el promedio del período. |
| ⑨ | Barras horizontales | eje: `customer_state_name` · valor: `% Entregas tarde` · los 10 peores con al menos 300 entregas | Dónde falla. Siete de los diez son del Nordeste, y se resaltan en azul sobre gris: la conclusión se ve sin leer las etiquetas. El piso de 300 entregas evita que encabece un estado con 40 pedidos. |
| ⑩ | Tabla | filas: `seller_segment` · columnas: `Vendedores`, `Ventas` (como % del total), `% Despacho tardío`, `% Entregas a tiempo`, `Calificación promedio` | Quién falla. Tabla y no gráfico porque son cuatro filas con cinco medidas de escalas distintas: se leen como números. La fila "En riesgo" es la conclusión: el 13% de las ventas, despacho fuera de plazo una de cada tres veces. |

Qué tiene que verse (meses completos):

- ⑥ 10+ días antes **4,32** · 1 a 9 días antes **4,23** · El día prometido **4,03** ·
  1 a 5 días tarde **2,99** · 6 a 10 días tarde **1,77** · 11+ días tarde **1,71**.
- ⑦ mínimos de 87,6% (noviembre de 2017), 85,9% (febrero de 2018) y 81,0% (marzo de
  2018); máximo de 98,8% (junio de 2018).
- ⑧ baja a 3,94, 3,84 y 3,76 en esos mismos tres meses.
- ⑨ Alagoas 21,5% · Maranhão 17,5% · Sergipe 15,4% · Piauí 13,9% · Ceará 13,8% ·
  Bahia 12,2% · Rio de Janeiro 12,1% · Pará 11,3% · Espírito Santo 10,7% · Paraíba 10,5%.
- ⑩

| Segmento | Vendedores | % de las ventas | % Despacho tardío | % Entregas a tiempo | Calificación promedio |
|---|---:|---:|---:|---:|---:|
| Núcleo | 233 | 36,9% | 3,5% | 94,4% | 4,24 |
| En ascenso | 1.401 | 16,5% | 2,1% | 96,1% | 4,41 |
| Estable | 627 | 33,4% | 10,5% | 92,4% | 3,99 |
| En riesgo | 807 | 13,2% | 33,0% | 88,0% | 3,56 |

En Looker Studio la última columna da 4,24 · 4,42 · 3,99 · 3,58: ver "Una diferencia
conocida entre las dos herramientas" en [`medidas.md`](medidas.md).

---

## Posiciones en el lienzo (1280 × 720)

| Elemento | X | Y | Ancho | Alto |
|---|---:|---:|---:|---:|
| Título | 24 | 12 | 480 | 40 |
| Filtros (4) | 516 · 704 · 892 · 1080 | 12 | 176 | 40 |
| Tarjetas ① a ⑤ | 24 · 272 · 520 · 768 · 1016 | 64 | 236 | 96 |
| ⑥ gráfico principal | 24 | 172 | 732 | 264 |
| ⑦ tendencia de arriba | 768 | 172 | 484 | 126 |
| ⑧ tendencia de abajo | 768 | 310 | 484 | 126 |
| ⑨ desglose izquierdo | 24 | 448 | 732 | 256 |
| ⑩ desglose derecho | 768 | 448 | 484 | 256 |

En Power BI se cargan en *Formato → General → Propiedades*. En Looker Studio sirven de
referencia para acomodar los elementos con la grilla y las guías de alineación.

---

## Paso a paso en Power BI Desktop

Los nombres de menú corresponden a la interfaz en español y pueden variar apenas entre
versiones.

### A. Preparar el archivo

1. Generar los datos: `python -m src.star`. Tiene que terminar con todas las líneas en
   `ok` y los archivos en `data/bi/power_bi/`.
2. Abrir Power BI Desktop con un informe en blanco y guardarlo como
   `dashboard/olist.pbix`.
3. **Desactivar la fecha y hora automáticas:** *Archivo → Opciones y configuración →
   Opciones → Archivo actual → Carga de datos → Inteligencia de tiempo*, desmarcar
   *Fecha y hora automáticas*. Si queda activa, Power BI crea una tabla de fechas
   oculta por cada columna de fecha y `dim_date` deja de ser la única fuente.

### B. Cargar las cinco tablas

4. *Inicio → Obtener datos → Más… → Archivo → Parquet*. Pegar la ruta completa de
   `dim_date.parquet` y elegir *Cargar*. Repetir con `dim_customer`, `dim_seller`,
   `dim_product` y `fct_order_items`.
5. En la *Vista de tabla*, comprobar la cantidad de filas: 1.096, 99.441, 3.095,
   32.951 y 112.650.

Se usa Parquet y no CSV porque trae los tipos resueltos. Con CSV, en una PC con coma
decimal Power BI puede leer `129.90` como 12.990 y quitarle el cero inicial a los
prefijos postales.

### C. Armar el modelo

6. Ir a la *Vista de modelo*. Power BI suele detectar solo las tres relaciones cuyas
   columnas se llaman igual (`customer_key`, `seller_key`, `product_key`). Revisar cada
   una con doble clic: cardinalidad *Varios a uno (\*:1)* y dirección del filtro
   cruzado *Única*. Si falta alguna, se crea arrastrando la columna de la tabla de
   hechos sobre la de la dimensión.
7. Crear las tres relaciones de fecha, arrastrando desde `fct_order_items` hacia
   `dim_date[date_key]`, **en este orden**:
   1. `purchase_date_key` — queda activa (línea continua).
   2. `delivered_date_key` — queda inactiva (línea punteada).
   3. `estimated_delivery_date_key` — queda inactiva.

   Sólo puede haber una relación activa entre dos tablas. La activa es la fecha de
   compra; las otras se usan desde una medida con `USERELATIONSHIP`.
8. Seleccionar `dim_date` y elegir *Herramientas de tablas → Marcar como tabla de
   fechas*, con la columna `full_date`.
9. Definir el orden de las columnas de texto (*Herramientas de columnas → Ordenar por
   columna*). Sin esto los meses salen en orden alfabético.

   | Columna | Ordenar por |
   |---|---|
   | `dim_date[month_name]` | `month` |
   | `dim_date[year_month]` | `year_month_sort` |
   | `dim_date[day_name]` | `day_of_week` |
   | `fct_order_items[delivery_bucket]` | `delivery_bucket_sort` |
   | `dim_seller[seller_segment]` | `seller_segment_sort` |

10. Quitar el resumen automático de las columnas numéricas que no son cantidades
    (*Herramientas de columnas → Resumen → No resumir*): en `dim_date`, `year`,
    `quarter`, `month`, `iso_week`, `day_of_month` y `day_of_week`.
11. **Ocultar lo que nadie debe arrastrar a un gráfico** (clic derecho → *Ocultar en la
    vista de informe*):
    - todas las columnas `*_key` y las `*_sort`;
    - en `fct_order_items`, todo salvo `order_status` y `delivery_bucket`.

    Es lo que hace cumplir la regla de `medidas.md`: si `review_score` no se ve, nadie
    puede promediarlo por línea. Los números entran al informe sólo por las medidas.

### D. Crear las medidas

12. *Inicio → Especificar datos*, crear una tabla vacía llamada `_Medidas` y cargarla.
    Sirve para tener todas las medidas en un solo lugar.
13. Con `_Medidas` seleccionada, *Nueva medida*, y pegar una por una las de
    `medidas.md`: primero las tres base, después los cinco indicadores, después las
    auxiliares.
14. Darle formato a cada una en *Herramientas de medición*: porcentaje con un decimal
    para las que empiezan con `%`, moneda para `Ventas` y `Ticket promedio`, decimal
    para las de días y la calificación.
15. Agregar tres medidas que sólo sirven a esta página:

    ```dax
    % Entregas tarde (mín. 300) =
    IF ( [Pedidos entregados] >= 300, [% Entregas tarde] )

    Color banda =
    IF (
        SELECTEDVALUE ( fct_order_items[delivery_bucket_sort] ) >= 4,
        "#e34948",
        "#2a78d6"
    )

    Color región =
    IF (
        SELECTEDVALUE ( dim_customer[customer_region] ) = "Nordeste",
        "#2a78d6",
        "#c3c2b7"
    )
    ```

### E. Validar antes de dibujar

16. En una página aparte, poner una *Tabla* con las medidas base y los cinco
    indicadores, sin ningún filtro, y compararla con la columna "Sin filtros" de la
    tabla de control de `medidas.md`. Tiene que coincidir.
17. Agregar `dim_date[year]` como primera columna: las filas 2017 y 2018 tienen que
    coincidir con las columnas de esos años.

Si un número no da, el problema está en el modelo o en la medida. Encontrarlo acá
lleva dos minutos; encontrarlo con el tablero armado, una tarde.

### F. Preparar el informe

18. *Vista → Temas → Examinar temas* y elegir
    [`docs/powerbi_theme.json`](powerbi_theme.json): carga la paleta del repositorio.
19. En el panel *Filtros*, arrastrar `dim_date[is_complete_month]` a *Filtros de todas
    las páginas* y dejar marcado el valor 1.
20. Renombrar la página a "Ventas".

### G. Armar la página 1

21. **Filtros.** Insertar cuatro *Segmentaciones de datos* en estilo *Desplegable*, con
    `dim_date[year_month]`, `dim_customer[customer_state_name]`,
    `dim_product[category_label]` y `dim_seller[seller_segment]`.
22. **Tarjetas ① a ⑤.** Cinco objetos *Tarjeta*, uno por medida. En `Ventas`, unidades
    de presentación en millones con un decimal.
23. **⑥ Ventas por mes.** *Gráfico de líneas*: eje X `dim_date[month_start]`, eje Y
    `Ventas`. Eje X de tipo *Continuo*.
24. **⑦ y ⑧.** Copiar ⑥ dos veces y cambiar la medida por `Pedidos` y por
    `Ticket promedio`. En ⑦ ocultar las etiquetas del eje X: las comparte con ⑧.
25. **⑨ Ventas por categoría.** *Gráfico de barras agrupadas*: eje Y
    `dim_product[category_label]`, eje X `Ventas`. En el panel *Filtros*, sobre
    `category_label`: tipo *N superiores*, mostrar *Superior 10*, por valor `Ventas`.
    Activar las etiquetas de datos y ocultar el eje X.
26. **⑩ Ventas por estado.** Igual que ⑨ con `dim_customer[customer_state_name]`.

### H. Armar la página 2

27. Duplicar la página (clic derecho sobre la pestaña → *Duplicar página*) y renombrarla
    a "Entregas y satisfacción". Se conservan el esqueleto y los filtros.
28. **Tarjetas.** Cambiar las medidas por `% Entregas a tiempo`, `Pedidos tarde`,
    `Días promedio de atraso`, `Días promedio de entrega` y `Calificación promedio`.
29. **⑥ Calificación según cumplimiento.** Cambiar el gráfico a *Gráfico de columnas
    agrupadas*: eje X `fct_order_items[delivery_bucket]`, eje Y `Calificación promedio`.
    - Filtro de este objeto visual: `delivery_bucket` distinto de "No entregado".
    - Color: *Formato → Columnas → Color → fx*, estilo de formato *Valor de campo*,
      campo `Color banda`.
    - Eje Y de 0 a 5 fijo. Etiquetas de datos activadas.
30. **⑦ % Entregas a tiempo por mes.** Línea con `% Entregas a tiempo`. En el panel
    *Analytics*, agregar una *Línea constante* en 0,932. Fijar el mínimo del eje Y en
    0,75: es una línea, no una barra, y con el eje desde cero los pozos no se ven.
31. **⑧ Calificación promedio por mes.** Línea con `Calificación promedio`.
32. **⑨ % Entregas tarde por estado.** Barras con eje Y
    `dim_customer[customer_state_name]` y eje X `% Entregas tarde`.
    - Filtro *N superiores*: *Superior 10* por valor `% Entregas tarde (mín. 300)`.
    - Color: *fx → Valor de campo →* `Color región`.
33. **⑩ Segmentos de vendedores.** Objeto *Tabla* con `dim_seller[seller_segment]`,
    `Vendedores`, `Ventas`, `% Despacho tardío`, `% Entregas a tiempo` y
    `Calificación promedio`. En `Ventas`, desde el menú del campo: *Mostrar valor como →
    Porcentaje del total general*.

### I. Terminar

34. *Vista → Sincronizar segmentaciones*: marcar las cuatro segmentaciones en las dos
    páginas, para que un filtro elegido en una siga puesto en la otra.
35. Comparar cada gráfico con la lista "Qué tiene que verse" de su página.
36. Borrar la página de validación, o dejarla oculta.
37. Guardar. Exportar cada página como imagen o PDF (*Archivo → Exportar*) para
    mostrarlas en el README.

---

## Paso a paso en Looker Studio

### A. Crear la fuente de datos

1. Generar los datos: `python -m src.star`.
2. En [lookerstudio.google.com](https://lookerstudio.google.com): *Crear → Fuente de
   datos → Subida de archivos* (File Upload). Subir
   `data/bi/looker_studio/order_items_flat.csv` (33,6 MB; el conector admite hasta
   100 MB por conjunto de datos y exige UTF-8, que es como se exporta). Cuando el
   estado pasa a *Subido*, elegir *Conectar*.
3. Revisar los tipos que detectó:
   - `purchase_date`, `delivered_date`, `estimated_delivery_date`: *Fecha*.
   - `order_id`, `customer_unique_id`: *Texto*.
   - `customer_state_iso`, `seller_state_iso`: cambiar a *Geográfico → Subdivisión de
     país (1.er nivel)*. Sólo hace falta para usar mapas.
   - el resto de las columnas numéricas: *Número*.

### B. Crear las medidas

4. En la fuente de datos, *Añadir un campo → Añadir campo calculado*. Crear uno por
   medida con el nombre y la fórmula de la sección "Looker Studio" de `medidas.md`.
   Se crean en la fuente, no en un gráfico, para escribirlas una sola vez.
5. Darle a cada campo su tipo: *Porcentaje* a los que empiezan con `%`, *Moneda (BRL)*
   a `Ventas` y `Ticket promedio`, *Número* al resto.
6. Crear dos dimensiones calculadas, que sólo sirven para dar color:

   ```
   Cumplimiento   CASE WHEN is_late = 1 THEN "Tarde"
                       WHEN is_on_time = 1 THEN "A tiempo"
                       ELSE "No entregado" END

   Zona           CASE WHEN customer_region = "Nordeste" THEN "Nordeste"
                       ELSE "Resto del país" END
   ```

### C. Crear el informe y fijar el período

7. *Crear informe* desde la fuente de datos.
8. *Tema y diseño → Diseño → Tamaño del lienzo*: personalizado, 1280 × 720.
9. **Fijar el período por defecto.** *Archivo → Configuración del informe*: fuente de
   datos, la creada; dimensión de período, `purchase_date`; período predeterminado,
   *Personalizado → Fijo*, del 1 de enero de 2017 al 31 de agosto de 2018.

   Este paso no es opcional. El período automático de Looker Studio son los últimos 28
   días, y como los datos terminan en 2018 **todos los gráficos salen vacíos**. El
   rango fijo equivale además al filtro de meses completos.

### D. Validar antes de dibujar

10. Insertar un *Cuadro de resultados* (Scorecard) por cada uno de los cinco
    indicadores y comparar con la columna "Meses completos" de la tabla de control de
    `medidas.md`.

### E. Armar la página 1

11. **Filtros.** *Añadir un control → Control de período*, y tres *Listas desplegables*
    con `customer_state_name`, `category_label` y `seller_segment`. Seleccionar los
    cuatro y, con clic derecho, convertirlos en elementos a nivel de informe (*Make
    report-level*): así aparecen en las dos páginas y conservan lo elegido.
12. **Tarjetas ① a ⑤.** Cinco *Cuadros de resultados*, uno por medida. En `Ventas`,
    activar los números compactos.
13. **⑥ Ventas por mes.** *Serie temporal*: dimensión `purchase_date`, cambiando su
    tipo a *Año y mes* desde el ícono del campo; métrica `Ventas`.
14. **⑦ y ⑧.** Copiar ⑥ y cambiar la métrica por `Pedidos` y por `Ticket promedio`.
15. **⑨ Ventas por categoría.** *Gráfico de barras* horizontal: dimensión
    `category_label`, métrica `Ventas`, orden por `Ventas` descendente, 10 barras.
    Etiquetas de datos activadas.
16. **⑩ Ventas por estado.** Igual que ⑨ con `customer_state_name`.

### F. Armar la página 2

17. *Página → Duplicar página* y renombrarla.
18. **Tarjetas.** Cambiar las métricas por `% Entregas a tiempo`, `Pedidos tarde`,
    `Días promedio de atraso`, `Días promedio de entrega` y `Calificación promedio`.
19. **⑥ Calificación según cumplimiento.** *Gráfico de columnas apiladas*: dimensión
    `delivery_bucket`, dimensión de desglose `Cumplimiento`, métrica
    `Calificación promedio`.
    - Orden: campo `delivery_bucket_sort`, agregación *Mínimo*, ascendente.
    - Filtro del gráfico: incluir `is_delivered` igual a 1.
    - En *Estilo*, color por valores de la dimensión: "A tiempo" `#2a78d6`, "Tarde"
      `#e34948`.
    - Eje Y de 0 a 5.

    Cada banda tiene un solo valor de `Cumplimiento`, así que la columna "apilada" es
    una columna simple con el color que le corresponde.
20. **⑦ % Entregas a tiempo por mes.** Serie temporal con `% Entregas a tiempo`. En
    *Estilo*, agregar una línea de referencia de valor constante 0,932 y fijar el
    mínimo del eje Y en 0,75.
21. **⑧ Calificación promedio por mes.** Serie temporal con `Calificación promedio`.
22. **⑨ % Entregas tarde por estado.** Barras horizontales apiladas: dimensión
    `customer_state_name`, dimensión de desglose `Zona`, métrica `% Entregas tarde`,
    orden descendente, 10 barras.
    - Filtro del gráfico: incluir `Pedidos entregados` mayor o igual que 300.
    - Colores: "Nordeste" `#2a78d6`, "Resto del país" `#c3c2b7`.
23. **⑩ Segmentos de vendedores.** *Tabla*: dimensión `seller_segment`; métricas
    `Vendedores`, `Ventas`, `% Despacho tardío`, `% Entregas a tiempo` y
    `Calificación promedio`. Orden por `seller_segment_sort` (agregación *Mínimo*)
    ascendente. En `Ventas`, editar la métrica y elegir como cálculo comparativo
    *Porcentaje del total*.

### G. Terminar

24. Comparar cada gráfico con la lista "Qué tiene que verse" de su página.
25. *Compartir → Administrar acceso*: cualquier persona con el enlace puede ver. Ese
    enlace es el que va en el README.

---

## Qué sumar al repositorio cuando esté armado

- `dashboard/olist.pbix`.
- Una captura de cada página en `figures/`, incrustadas en el README.
- El enlace al informe de Looker Studio.
