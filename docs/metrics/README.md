# Métricas y dashboards — centro de conocimiento

Todo lo que hay que saber para agregar, medir y graficar métricas de negocio en
WalletBot. Escrito para que lo lean personas y agentes (Claude Code vía
`.claude/skills/grafana-metrics/`, Codex vía `AGENTS.md`).

| Documento | Para qué |
|---|---|
| [promql.md](./promql.md) | **Leer antes de escribir cualquier query.** Por qué `increase()` miente acá y qué usar en su lugar. |
| [dashboards.md](./dashboards.md) | El esquema v2 de Grafana, sus trampas de layout, y el validador. |
| [adding-a-metric.md](./adding-a-metric.md) | Los archivos que hay que tocar para que una métrica nueva llegue a Grafana. |
| [runbook.md](./runbook.md) | Operarlo: desplegar, forzar, y depurar un panel vacío. |
| [observability-grafana.md](../observability-grafana.md) | Setup de Grafana Cloud, env vars y PromQL de arranque. |

## El modelo mental

Lo primero que hay que entender, porque casi todos los errores salen de acá:

```
cliente nativo ─┐
cliente web ────┼─→ telemetryMetrics ──→ exportPendingMetrics ──→ Grafana/Mimir
mutación backend┘   (outbox efímero)      (OTLP HTTP JSON)         (la fuente
                                                                    de los
                                                                    dashboards)
```

**Convex no es la fuente de los dashboards.** `telemetryMetrics` es un búfer de
salida: guarda, reintenta, y borra. Los paneles leen Grafana. Si una fila está
en Convex pero el panel está vacío, el problema está en el export o en la
query, nunca en que "falta el dato".

Tres propiedades que definen todo lo demás:

1. **Los contadores son acumulativos.** Cada muestra dice "van 47 en total", no
   "hubo 1". El estado acumulado vive en `telemetryMetricSeries` y sobrevive
   entre exports, así que la serie nunca se resetea.

2. **Solo hay muestra cuando pasa algo.** No hay scrape periódico: es push. Una
   serie sin actividad no tiene puntos, no tiene ceros. Esto es lo que rompe a
   `increase()` — ver [promql.md](./promql.md).

3. **Un evento es una muestra.** Cada fila exportada es un data point OTLP con
   su propio timestamp (`receivedAt`). Por eso contar muestras es contar
   eventos. Vale mientras nadie emita varias filas de la misma serie dentro de
   una sola mutación: comparten `receivedAt` y colapsarían en un punto.

## Reglas que ya costaron caro

- **Medí en el borde del evento, no donde es cómodo.** El contador de sesiones
  del agente casi se engancha en el mint del token, que parecía el lugar obvio
  porque cubría web y nativo. No lo es: se mintea un token en *cada reconexión*
  y en el *prefetch* de la pantalla de voz. Un mint no es una sesión. El borde
  real era `VoiceSessionRepository.openOrCreate`.

- **No etiquetes con algo de cardinalidad abierta.** Ver R-024 en
  [riesgos.md](../riesgos.md): el costo por usuario se exporta como top 20 con
  `user_hash` estable, nunca `user_id` crudo. Un `tool_name` de ~30 valores está
  bien; los argumentos de la tool, jamás.

- **El catálogo valida en runtime, no solo en tipos.** `telemetry/catalog.ts`
  declara los valores permitidos de cada atributo y el ingest rechaza lo que no
  esté. Es una red de seguridad real: un `start_kind` inventado vuelve como
  `attribute start_kind has unsupported value`.

- **Estas métricas son señal direccional, no contabilidad.** R-011 (el ingest
  no está autenticado) y R-023 (el costo es estimado, no facturado) están
  aceptados a propósito. No las uses para reporting externo sin releer esos
  riesgos.
