# Agregar una métrica

Una métrica nueva toca **cinco archivos** antes de poder emitirse. Los cinco son
obligatorios: saltearse uno la hace rechazar en ingest o desaparecer en el
export, en ambos casos en silencio.

## 1. Declararla

| Archivo | Qué agregar |
|---|---|
| `convex/telemetry/types.ts` | el literal en `MetricName` |
| `convex/telemetry/validators.ts` | `v.literal(...)` en `metricName` |
| `convex/schema/telemetry.ts` | `v.literal(...)` en la unión de `name` |
| `convex/telemetry/catalog.ts` | `metricNames` + la entrada en `metricCatalog` |
| `convex/telemetry/actions.ts` | el `case` en `exportableMetricAttributeKeys` |

El último es el que más se olvida y el único que el compilador te reclama: el
`switch` es exhaustivo sobre `ReservedMetricName`, así que TypeScript rompe si
falta. **Los atributos que no estén en ese `Set` no se exportan** — la métrica
llega a Grafana sin sus labels.

La entrada del catálogo declara tipo, unidad y los valores permitidos:

```ts
'agent.sessions.started_count': {
    type: 'counter',
    unit: 'count',
    attributes: {
        model: 'string',
        start_kind: new Set(['new', 'resumed']),
    },
},
```

Un `Set` valida en runtime contra el ingest; `'string'` acepta cualquier
cadena no vacía. Preferí el `Set` siempre que el dominio sea cerrado: convierte
un typo del emisor en un `400` en vez de una serie fantasma en Grafana.

## 2. Emitirla

**Desde el backend**, en una mutación, con un helper en
`convex/telemetry/metrics.ts`:

```ts
export const recordAlgo = (ctx: MutationCtx, args: {...}): Promise<void> =>
    recordMetricSafely(ctx, { name: '...', userId, attributes: {...} })
```

`recordMetricSafely` traga los errores a propósito: una falla de telemetría
nunca puede voltear la escritura de negocio que la originó.

**Desde el cliente nativo**, un método en `AgentMetrics` o `BusinessMetrics` y
su variante `...BestEffort` que hace `unawaited(...)`. Nunca pongas un hop de
red de telemetría en el camino crítico de una interacción.

**Desde web**, `apps/web/src/lib/telemetry.ts` envía métricas del agente por
`v1/telemetry/mutations:recordWebMetricBatch`. Esa mutación exige autenticación
y acepta solo las métricas del agente enumeradas allí. Una métrica implementada
solo en nativo sigue subcontando la web; indicá esa limitación en el panel.

## 3. Elegir dónde medir

La decisión de diseño que más cuesta revertir. Medí **en el borde del evento
que querés contar**, aunque haya un lugar más cómodo.

Contraejemplo real: el contador de sesiones del agente casi se engancha en
`consumeMintLimit`, el gate del mint del token, porque cubría web y nativo de
una. No sirve — se mintea un token en **cada reconexión** y en el **prefetch**
especulativo de la pantalla de voz. Habría contado reconexiones y tokens
tirados. El borde real era `VoiceSessionRepository.openOrCreate`, que además ya
distinguía sesión nueva de reanudada.

Cuando dudes, preguntate qué pasa si la red se corta a la mitad: si el contador
sube, estás midiendo el transporte y no el evento.

## 4. Cardinalidad

Cada combinación de labels es una serie. Antes de agregar un atributo, contá
cuántos valores puede tomar.

- Dominio cerrado y chico (`movement_type`, `start_kind`, `auth_method`): bien.
- ~30 valores fijos (`tool_name` desde `TOOL_DEFINITIONS`): aceptable.
- Identificadores de usuario: **no**. Ver R-024 en [riesgos.md](../riesgos.md):
  el detalle por usuario queda en Convex (`agentUsageMonthly`) y a Grafana solo
  va el top 20 mensual con `user_hash` estable y `rank`, nunca `user_id` crudo.
- Contenido libre (argumentos de tools, nombres, descripciones): nunca. Además
  de cardinalidad es PII, y el contrato de ingest la prohíbe.

## 5. Verificarlo de punta a punta

Compilar no prueba nada. Contra el deployment ya desplegado:

```sh
curl -s -X POST https://<deployment>.convex.site/telemetry/metrics \
  -H 'Content-Type: application/json' \
  -d '{"metrics":[{"name":"agent.sessions.started_count","source":"native",
       "type":"counter","value":1,"unit":"count",
       "attributes":{"model":"x","start_kind":"new"},
       "installationId":"smoke-test"}]}'
```

Esperado: `{"ok":true,"accepted":1}`.

**Probá también el rechazo**, que es la mitad que confirma que el catálogo está
vivo en el deployment y no solo en el código:

```sh
# ...con "start_kind":"reconnect"
# → {"code":"bad_request","message":"attribute start_kind has unsupported value"}
```

Un llamador anónimo necesita `installationId` (R-011: el endpoint no está
autenticado a propósito, para poder probar desde Bruno sin token).

Después confirmá que salió:

```sh
pnpm -C packages/backend exec convex data telemetryMetrics --limit 5 --order desc
```

`exportStatus: "exported"` con `exportAttempts: 0` es la cadena completa
andando. Ver [runbook.md](./runbook.md) para los otros estados.

## 6. Lo que no hay que olvidar

- **`docs/observability-grafana.md`**: agregá el nombre normalizado a Expected
  Metrics, los labels nuevos, y una query de arranque.
- **`docs/riesgos.md`**: la regla del repo pide revisar si la métrica mitiga un
  riesgo existente, le cambia la probabilidad, o introduce uno nuevo. Una
  métrica que hace medible algo que antes era una impresión suele actualizar la
  mitigación de un riesgo — `agent.sessions.started_count` cerró la parte de
  R-026 que pedía "revisar si reanudar sesiones pasa a ser un flujo frecuente".
- **Un panel.** Una métrica que nadie grafica no existe.
