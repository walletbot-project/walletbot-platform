# PromQL sobre estas métricas

Leer esto antes de escribir una query. Los contadores de WalletBot son
**acumulativos y esporádicos** (push, una muestra por evento), y esa
combinación rompe la función que todo el mundo usa por reflejo.

## `increase()` miente acá

Es la trampa principal. `increase(v[w])` es literalmente `rate(v[w]) * w`, y
`rate()` **extrapola a los bordes de la ventana**. Con muestras densas eso es
inofensivo. Con eventos esporádicos es catastrófico.

Medido en dev el 2026-09-10, con 3 movimientos creados a mano y 2 sesiones:

| Panel | Real | `increase()` mostró |
|---|---|---|
| Movimientos creados | 3 | **40.9** |
| Sesiones abiertas | 2 | **1.55** |
| Sesiones en el tiempo | 2 | **"No data"** |

Los tres síntomas, una causa:

- **Inflado.** Los 3 eventos ocurrieron en un par de minutos dentro de una
  ventana mucho más ancha. Prometheus proyectó esa pendiente sobre toda la
  ventana.
- **Fraccionario.** `increase()` devuelve una tasa integrada, no un conteo. Un
  conteo con decimales es la señal de que estás usando la función equivocada.
- **"No data".** Necesita **al menos dos muestras** en la ventana para calcular
  una pendiente. Los buckets de `$__interval` de una serie esporádica tienen 0
  o 1. Devuelve nada, que en un panel se lee como "no pasó nada" — el peor modo
  de falla de los tres, porque es indistinguible de la verdad.

## Qué usar

### Conteo de eventos en el rango elegido → `count_over_time`

```promql
sum by(movement_type) (count_over_time(business_movements_created_count_total{deployment_environment="$Scope"}[$__range]))
```

Cuenta **muestras**, no valores del contador. Como cada evento produce
exactamente una fila exportada y cada fila un data point con su propio
`receivedAt`, contar muestras es contar eventos.

Es lo que querés casi siempre: exacto, entero, sin extrapolar, y la ventana es
`$__range`, así que **el selector de tiempo vuelve a mandar** — elegir 24 h
responde por 24 h y 6 h por 6 h.

Para actividad por intervalo en una serie temporal, la misma función contra
`[$__interval]`.

**La condición que lo sostiene:** un evento, una muestra. Filas exportadas en
un mismo request HTTP comparten `receivedAt` y colapsarían en un solo punto.
Hoy nada hace eso — los movimientos se registran una mutación por movimiento
(tres call sites en `v1/transactions/mutations.ts`, todos de entidad única) y
las sesiones una por apertura. **Si alguna vez aparece un camino en lote que
emita varias del mismo contador junto, esto empieza a subcontar en silencio** y
hay que darle timestamps distintos a cada fila en el exporter.

### Total acumulado, y gauges → `last_over_time`

```promql
last_over_time(business_users_registered_total{deployment_environment="$Scope"}[$__range])
```

Lee el último valor dentro de la ventana. Exacto y entero, pero responde
"cuántos en total", no "cuántos en este rango": el rango solo decide hasta
dónde mirar hacia atrás buscando la muestra más reciente.

Es lo correcto para los **gauges** (`business.users.registered_total`,
`agent.user.monthly_cost_usd`), que son fotos periódicas y no eventos.

### Delta de ventana → `max_over_time - min_over_time`

```promql
max_over_time(v[$__range]) - min_over_time(v[$__range])
```

Exacto, entero, no extrapola, y sí acota a la ventana. **Se pierde el
incremento que produjo la primera muestra de la ventana**, así que subcontá en
uno por serie cuando la actividad empieza dentro del rango. Con 3 movimientos
(acumulado 1, 2, 3) da 2.

Útil cuando `count_over_time` no aplica porque las muestras se agrupan.

## Tabla de decisión

| Querés | Usá |
|---|---|
| Cuántos eventos en el rango elegido | `count_over_time(v[$__range])` |
| Actividad por intervalo, serie temporal | `count_over_time(v[$__interval])` |
| El valor actual de un gauge | `last_over_time(v[$__range])` |
| El total histórico de un contador | `last_over_time(v[$__range])` |
| Cuánto avanzó el contador en la ventana | `max_over_time(v[w]) - min_over_time(v[w])` |
| Una tasa, con tráfico real | `rate(v[5m])` |
| Un conteo | **nunca `increase()`** mientras el volumen sea bajo |

`increase()` vuelve a ser correcto cuando hay tráfico real y las muestras son
densas. El problema es específico de bajo volumen — o sea dev, y el arranque de
prod, que es justo cuando más se mira el dashboard.

## Nombres de métricas en Grafana

Mimir normaliza los nombres OTLP a estilo Prometheus: los puntos pasan a
guiones bajos, y **los contadores acumulativos aparecen con sufijo `_total`**.

```
agent.sessions.started_count   →   agent_sessions_started_count_total
business.users.registered_total →  business_users_registered_total_count
```

⚠️ El sufijo **no está verificado contra la instancia** — se dedujo de los
paneles que ya funcionaban. Si un panel queda en "No data" con datos
exportados, lo primero es confirmar el nombre real:

```promql
count by(__name__) ({__name__=~"agent_sessions_started.*"})
```

## `$Scope`

Todos los paneles filtran por `{deployment_environment="$Scope"}`. La etiqueta
sale de `OTEL_RESOURCE_ATTRIBUTES`, o del fallback `WALLETBOT_ENV`.

| Deployment | Valor |
|---|---|
| producción | `production` |
| dev (`joyous-grouse-582`) | `development-3` |

**Es la causa número uno de "todo el dashboard está vacío".** Probando contra
dev con `$Scope = production` no aparece absolutamente nada.
