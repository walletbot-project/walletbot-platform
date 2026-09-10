# AGENTS.md

Instrucciones para agentes de código (Codex, Claude Code, y cualquier otro) que
trabajen en este repo.

## Reglas del proyecto

**[`CLAUDE.md`](./CLAUDE.md) es la fuente única de las reglas del repo** —
estructura del monorepo, convenciones de backend y frontend, reglas de acceso a
la base en Convex, versionado del contrato cliente-servidor, feature flags y
localización. Leelo antes de tocar código, aunque no seas Claude: el nombre del
archivo es histórico, el contenido no es específico de ninguna herramienta.

**[`LESSONS.md`](./LESSONS.md)** documenta errores recurrentes que ya se
pagaron. Obligatorio antes de tocar auth, la app nativa, o cualquier cosa que
roce `convex_flutter`.

## Centros de conocimiento

Documentación por tema, para leer antes de trabajar en esa área:

| Área | Dónde |
|---|---|
| **Métricas y dashboards de Grafana** | [`docs/metrics/`](./docs/metrics/README.md) |
| Terminología y visión general | [`README.md`](./README.md) |
| Registro de riesgos | [`docs/riesgos.md`](./docs/riesgos.md) |
| Modelo de datos | [`docs/data-model.md`](./docs/data-model.md) |
| Ciclo de vida de la sesión de voz | [`docs/voice-session-lifecycle.md`](./docs/voice-session-lifecycle.md) |
| Esquema SQLite nativo y migraciones | [`docs/schema/README.md`](./docs/schema/README.md) |
| Setup de Grafana Cloud | [`docs/observability-grafana.md`](./docs/observability-grafana.md) |

### Métricas: lo que más se rompe

Si vas a escribir PromQL, editar un dashboard o agregar una métrica, leé
[`docs/metrics/`](./docs/metrics/README.md) primero. El error más caro y más
repetido:

**Nunca uses `increase()` para contar eventos.** Los contadores de este proyecto
son acumulativos y solo reciben una muestra cuando pasa algo. `increase()`
extrapola a los bordes de la ventana, así que devuelve valores inflados y
fraccionarios (3 movimientos reportados como 40.9) y **"No data"** cuando hay
menos de dos muestras en el bucket. Usá `count_over_time(v[$__range])`.

Después de editar cualquier dashboard: `pnpm run validate-dashboards`.

## Comandos

```sh
pnpm dev                    # web + convex dev en paralelo
pnpm run typecheck          # todos los paquetes (desde la raíz)
pnpm run format             # biome, después de cualquier cambio
pnpm run validate-dashboards
pnpm run lint               # desde apps/web
```

Nativo, desde `apps/native`: `flutter analyze`, `flutter test`, y
`dart format` **solo sobre los archivos que tocaste** — el repo no está
enteramente formateado y correrlo sobre un archivo entero mete ruido ajeno en
el diff.

Usar **pnpm**, nunca npm ni yarn.

## Git

No commitear sin que te lo pidan explícitamente. "Hacelo en una rama" no es
"commiteálo".
