# Schema Docs

Esta carpeta documenta los dos schemas persistentes del proyecto:

- `Convex`: schema remoto/backend.
- `SQLite/Drift`: schema local de la app nativa.

Objetivo:

- Tener una referencia humana del estado actual del schema.
- Registrar migraciones de forma explícita.
- Evitar reconstruir cambios leyendo PRs, código generado o logs.

Reglas de mantenimiento:

- Si cambia `packages/backend/convex/schema.ts` o algún archivo en `packages/backend/convex/schema/`, actualizar [convex-schema.md](./convex-schema.md).
- Si cambia `apps/native/lib/database.dart`, actualizar [sqlite-schema.md](./sqlite-schema.md).
- Si el cambio requiere compatibilidad hacia atrás, agregar una entrada en [migrations/](./migrations/README.md).
- Si el cambio requiere backfill, documentarlo en la migración correspondiente.
- Para SQLite/Drift, no dejar saltos de versión implícitos: cada upgrade soportado debe tener un path explícito y los no soportados deben fallar de forma clara.

Estado actual:

- El schema remoto de Convex ya evolucionó varias veces.
- El schema local de SQLite está definido en Drift, pero todavía no tiene historial formal de migraciones documentado.
- La próxima migración formal debería arrancar con `v1 -> v2` en SQLite.

Referencias de código:

- Convex root: `packages/backend/convex/schema.ts`
- Convex tables: `packages/backend/convex/schema/*.ts`
- SQLite root: `apps/native/lib/database.dart`
- SQLite generated code: `apps/native/lib/database.g.dart`
