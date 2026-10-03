---
name: walletbot-metrics-doctor
description: "Diagnosticar métricas y dashboards de WalletBot: contrastar instrumentación y PromQL con datos reales de Grafana Cloud, investigar paneles vacíos o conteos incorrectos y validar cambios antes de darlos por comprobados."
---

# Doctor de métricas de WalletBot

Usá este flujo para evaluar una hipótesis sobre métricas o un cambio de dashboard. La API de consulta es de solo lectura; nunca uses el token de ingestión OTLP como sustituto del token de lectura.

1. Leé `docs/metrics/promql.md`, `docs/metrics/dashboards.md` y los paneles relevantes en `docs/dashboards/`. Buscá la métrica en `packages/backend/convex/telemetry/catalog.ts` y su emisión/export en el código. Separá el nombre interno del nombre Prometheus normalizado.
2. Corré `pnpm run validate-dashboards` si cambiaste un JSON. Esto valida estructura; no demuestra que la query tenga datos.
3. Configurá el acceso de lectura como se indica abajo. Si faltan credenciales, decí explícitamente que la validación remota queda pendiente.
4. Ejecutá `python3 .agents/skills/walletbot-metrics-doctor/scripts/query.py '<PromQL>'`. Para confirmar nombres de series esporádicas, usá `--series-days 14 '<selector>'`: la consulta instantánea puede estar vacía aunque la serie exista. WalletBot conserva 14 días de muestras en Grafana según la configuración reportada en septiembre de 2026; verificá si cambió antes de interpretar un rango mayor. Una búsqueda de 90 días no prueba nada anterior a la retención efectiva. Después probá la expresión del panel con el scope y el rango correctos. Un resultado vacío puede indicar falta de muestras, etiquetas distintas o una query incorrecta; comprobá cuál antes de cambiar código. Consultá desarrollo y producción por separado cuando aplique.
5. Informá el PromQL probado, scope, ventana temporal, resultado y conclusión. Marcá como hipótesis todo lo que no pudiste confirmar en Grafana. Para una métrica nueva, probá también su emisión y exportación siguiendo `docs/metrics/adding-a-metric.md` y `docs/metrics/runbook.md`.

Ejemplos de consultas exploratorias:

```sh
python3 .agents/skills/walletbot-metrics-doctor/scripts/query.py --series-days 14 '{__name__=~"agent_session_cost_bucket.*"}'
python3 .agents/skills/walletbot-metrics-doctor/scripts/query.py 'count by (deployment_environment) (agent_session_cost_usd)'
```

La consulta de Grafana no reemplaza una prueba en Convex cuando el problema está antes del export.

## Acceso de lectura

En [Grafana Cloud Portal](https://grafana.com/docs/grafana-cloud/send-data/metrics/metrics-prometheus/query-http-api/), abrí el stack de WalletBot → **Prometheus → Details**. Copiá **Query endpoint** y **User** (metrics instance ID). En **Security → Access Policies**, creá una política para ese stack con `metrics:read` y generá su token con **Add token**. Un token de ingestión con `metrics:write` no alcanza. Copiá el Query endpoint, no el enlace a la documentación ni el endpoint de remote write; el script agrega `/api/v1/query`.

Guardá estos valores en el archivo ignorado `packages/backend/.env.local` o en el entorno del proceso:

```dotenv
GRAFANA_METRICS_QUERY_URL=<Query endpoint>
GRAFANA_METRICS_INSTANCE_ID=<User>
GRAFANA_METRICS_READ_TOKEN=<token con metrics:read>
```

El script lee ese archivo sin ejecutar su contenido y acepta `--env-file <ruta>` para otro archivo local. No guardes secretos en archivos versionados, issues ni respuestas de chat. Probá la conexión con `query.py 'vector(1)'`: un resultado exitoso confirma endpoint y autenticación, no la existencia de métricas de WalletBot.
