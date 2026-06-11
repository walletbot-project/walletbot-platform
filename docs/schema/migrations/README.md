# Schema Migrations

Esta carpeta registra migraciones de schema y backfills asociados.

Cada archivo debería documentar:

- versión origen y destino
- tablas afectadas
- cambio lógico
- SQL aplicado o estrategia Drift/Convex usada
- backfill requerido
- riesgos
- validación esperada

Convención sugerida:

- `0001-initial.md`
- `0002-sqlite-v2-add-archived-and-date-confirmed.md`
- `0003-convex-backfill-date-confirmed.md`

Importante:

- Convex y SQLite pueden requerir migraciones distintas para un mismo cambio conceptual.
- Un PR puede tocar ambos mundos, pero la documentación debe dejar claro qué se migró en cada uno.
