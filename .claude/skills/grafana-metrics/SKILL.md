---
name: grafana-metrics
description: Trabajar con las métricas de negocio de WalletBot y sus dashboards de Grafana. Usar esta skill al escribir o corregir queries PromQL, editar los dashboards JSON de docs/dashboards/, agregar una métrica nueva al catálogo de telemetría, depurar un panel vacío o un export fallado, o decidir dónde instrumentar un evento. También cuando aparezcan conteos con decimales, valores inflados, o "No data" en un panel con datos existentes.
---

# Métricas y dashboards de WalletBot

Base de conocimiento: **[`docs/metrics/`](../../../docs/metrics/README.md)**.
Este archivo es el resumen operativo; los detalles y el porqué están ahí.

## Antes de escribir una query

Leé [`docs/metrics/promql.md`](../../../docs/metrics/promql.md). Lo esencial:

**Nunca uses `increase()` para contar.** Estos contadores son acumulativos y
solo reciben una muestra cuando ocurre un evento. `increase(v[w])` es
`rate(v[w]) * w` y `rate()` extrapola a los bordes de la ventana, así que con
eventos esporádicos devuelve valores inflados y fraccionarios (3 movimientos
reportados como 40.9, 2 sesiones como 1.55) y **"No data"** cuando un bucket
tiene menos de dos muestras.

| Querés | Usá |
|---|---|
| Eventos en el rango elegido | `count_over_time(v[$__range])` |
| Actividad por intervalo | `count_over_time(v[$__interval])` |
| Valor de un gauge, o total histórico | `last_over_time(v[$__range])` |
| Avance del contador en la ventana | `max_over_time(v[w]) - min_over_time(v[w])` |
| Una tasa, con tráfico real | `rate(v[5m])` |

`count_over_time` cuenta muestras, y cada evento produce exactamente una fila
exportada con su propio `receivedAt`, así que contar muestras es contar
eventos. Vale mientras nadie emita varias filas de la misma serie dentro de una
sola mutación.

Todo panel filtra por `{deployment_environment="$Scope"}`. Dev es
`development-3`, no `production`.

## Antes de editar un dashboard

Leé [`docs/metrics/dashboards.md`](../../../docs/metrics/dashboards.md).

Esquema v2: `spec.elements` (los paneles) y `spec.layout` (dónde va cada uno) se
mantienen en sincronía a mano. Cada fila usa `GridLayout` (items
`GridLayoutItem` con `x`/`y`/`width`/`height`) **o** `AutoGridLayout` (items
`AutoGridLayoutItem`, sin coordenadas). Mezclarlos hace fallar el import con
`Value must be "AutoGridLayoutItem"` sin decir en qué fila.

Ojo con la trampa: una fila `AutoGridLayout` de un solo panel tiene un item sin
coordenadas, idéntico a un `GridLayoutItem` incompleto.

**Siempre, después de editar:**

```sh
pnpm run validate-dashboards
```

Y si hay una copia de trabajo fuera del repo (Escritorio, para importar sin
sacar el worktree), actualizala también.

## Antes de agregar una métrica

Leé [`docs/metrics/adding-a-metric.md`](../../../docs/metrics/adding-a-metric.md).

Cinco archivos, todos obligatorios: `telemetry/types.ts`,
`telemetry/validators.ts`, `schema/telemetry.ts`, `telemetry/catalog.ts` y el
`case` en `exportableMetricAttributeKeys` de `telemetry/actions.ts` — los
atributos que falten en ese `Set` no se exportan.

**Medí en el borde del evento, no donde sea cómodo.** El contador de sesiones
casi se engancha en el mint del token: se mintea uno en cada reconexión y en el
prefetch de la pantalla, así que habría contado reconexiones. Preguntate qué
pasa si la red se corta a la mitad.

Cuidá la cardinalidad: nunca `user_id` crudo ni contenido libre (ver R-024 en
`docs/riesgos.md`).

Verificá contra el deployment con un POST a `/telemetry/metrics`, y probá
**también el rechazo** de un valor inválido — es lo que confirma que el catálogo
está vivo en el deployment y no solo en el código.

## Para depurar

Leé [`docs/metrics/runbook.md`](../../../docs/metrics/runbook.md).

Panel vacío, por orden de probabilidad: `$Scope` → el rango → la query
(`increase()`) → el nombre normalizado en Mimir → `exportStatus` en Convex → el
cliente no emite.

El export es **inmediato** (`runAfter(0)`); el cron de 5 min es red de
seguridad. Lo que sí tarda son los dos gauges de **6 horas**, que para una
prueba manual conviene forzar:

```sh
pnpm -C packages/backend exec convex run telemetry/actions:recordRegisteredUsersTotalNow
```

La ruta va con **barra**, no con punto.
