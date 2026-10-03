# Runbook de métricas

Operar el pipeline: desplegar, forzar, y depurar un panel vacío.

## Latencias reales

Saber cuál es cuál evita esperar de más:

| Etapa | Cuánto tarda |
|---|---|
| Insertar → exportar | **inmediato** (`scheduler.runAfter(0)`) |
| Cron `export pending telemetry metrics` | cada 5 min (red de seguridad, no el camino normal) |
| Reintento de `failed` | cada 15 min, hasta 6 intentos |
| Gauges `record registered users total` / `record agent monthly usage` | **cada 6 horas** |
| Borrado de filas exportadas | 24 h |

**El export no son 5 minutos**, es inmediato. Los 5 minutos son solo para filas
que quedaron en `pending` porque el export agendado no llegó a correr.

Los que sí te hacen esperar de verdad son **los dos gauges de 6 horas**. Para
una prueba manual eso es infinito: forzalos.

## Forzar

```sh
# el gauge de usuarios registrados
pnpm -C packages/backend exec convex run telemetry/actions:recordRegisteredUsersTotalNow

# el snapshot de costo mensual por usuario
pnpm -C packages/backend exec convex run telemetry/actions:recordAgentMonthlyUsageNow

# vaciar la cola de export
pnpm -C packages/backend exec convex run telemetry/actions:exportPendingMetrics '{}'
```

⚠️ La ruta va con **barra**, no con punto. `telemetry.actions:foo` falla con
`Module path has an extension that isn't 'js'`, que no ayuda nada a entender el
problema.

Agregá `--prod` para forzar en producción.

### Bajar los crons temporalmente

Si vas a probar varios minutos seguidos y necesitás ver moverse los gauges,
podés bajar los dos crons de 6 h a `{ minutes: 5 }` en `convex/crons.ts` y
redesplegar. **Dejalo sin commitear** y revertilo después:

```sh
git checkout -- packages/backend/convex/crons.ts
pnpm -C packages/backend exec convex dev --once
```

El redeploy es parte del revert: sin él el deployment se queda con los crons
cambiados aunque el archivo vuelva a estar bien.

## Desplegar

```sh
pnpm -C packages/backend exec convex dev --once
```

Despliega **el working tree**, no el commit. Eso permite probar un cambio sin
commitearlo, y también significa que un `convex dev` desde otra rama puede
sacar del deployment una función que creías desplegada.

## Depurar un panel vacío

En este orden — está puesto por probabilidad, no por profundidad:

**1. `$Scope`.** Es la causa número uno. Probando contra dev con
`$Scope = production` no aparece nada. Dev es `development-3`.

**2. El rango.** `count_over_time` necesita al menos una muestra dentro de la
ventana. Con "Last 15 minutes" y datos de hace media hora, no hay nada.

**3. La query.** Si el panel usa `increase()`, el problema es ese — ver
[promql.md](./promql.md).

**4. El nombre de la métrica.** Mimir normaliza y agrega sufijos. Confirmalo:

```promql
count by(__name__) ({__name__=~"agent_sessions_started.*"})
```

**5. El export.** Recién acá mirá Convex:

```sh
# ¿quedó algo trabado?
pnpm -C packages/backend exec convex run telemetry/queries:pendingMetricsForExport '{"limit":20}'

# las últimas filas y su estado
pnpm -C packages/backend exec convex data telemetryMetrics --limit 5 --order desc
```

| `exportStatus` | Qué significa |
|---|---|
| `pending` | esperando; forzá `exportPendingMetrics` |
| `exported` | llegó a Grafana — el problema es la query o el nombre |
| `failed` | mirá `lastExportError` |

Errores frecuentes en `lastExportError`:

- `status=401` — `OTEL_EXPORTER_OTLP_HEADERS` inválido o token vencido.
- `status=404` — endpoint OTLP mal armado o con el path duplicado.
- `invalid temporality and type combination` — Grafana rechazó un contador que
  no se mandó como OTLP `Sum` acumulativo monotónico.
- `OTEL_EXPORTER_OTLP_ENDPOINT not configured` — faltan env vars en *ese*
  deployment. Confirmalo con `convex env list | grep OTEL`.

**6. El cliente no está emitiendo.** Si nada llega ni siquiera a
`telemetryMetrics`, buscá `telemetry metrics: HTTP` en la consola de Flutter.
Suele ser el `TelemetryClient` sin auth.

## Probar el cliente nativo

`apps/native/.env` decide contra qué deployment corre (`CONVEX_URL` /
`CONVEX_SITE_URL`). `TelemetryClient` se construye siempre, así que no hay
ningún flag que habilitar.

Para una métrica de sesiones de voz, la prueba mínima son cuatro pasos, y **el
tercero es el que casi nadie hace**:

1. Abrir la pantalla de voz y arrancar una sesión → `start_kind="new"`.
2. Cerrarla y reabrirla antes de 2 h (la vida del resume handle) →
   `start_kind="resumed"`.
3. **Modo avión unos segundos a mitad de sesión y volver** → el contador de
   `new` **no** debe subir. Es el control que prueba que estás midiendo
   sesiones y no reconexiones.
4. Un movimiento por voz y otro a mano → los paneles de origen se mueven.
