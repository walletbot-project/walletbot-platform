# 0001 Initial

## Alcance

Punto de partida documental.

No representa una migración ejecutada retrospectivamente en código. Sirve para dejar asentado:

- dónde vive el schema remoto
- dónde vive el schema local
- que SQLite todavía no tiene historial formal de migraciones documentado

## Sources of truth

- Convex: `packages/backend/convex/schema.ts` y `packages/backend/convex/schema/*.ts`
- SQLite: `apps/native/lib/database.dart`

## Estado conocido

- Convex ya incluye cambios de schema recientes en `transactions`, incluyendo `isArchived` y `dateConfirmed`.
- SQLite en Drift refleja esos campos en código, pero sigue con `schemaVersion = 1`.
- Esa falta de migración explícita puede romper instalaciones existentes con bases previas al cambio.

## Próximo paso esperado

Registrar la primera migración formal de SQLite como `v1 -> v2`, incluyendo:

- bump de `schemaVersion`
- `MigrationStrategy`
- `ALTER TABLE` o estrategia equivalente
- validación de upgrade sobre una base existente
