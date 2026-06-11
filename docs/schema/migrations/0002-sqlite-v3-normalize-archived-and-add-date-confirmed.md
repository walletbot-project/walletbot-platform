# 0002 SQLite v3: normalize archived and add date_confirmed

## Alcance

Migración local de Drift/SQLite para preservar bases existentes al abrir una app con el schema actual.

Versión:

- origen: `v1` o `v2`
- destino: `v3`

## Problema que corrige

Había instalaciones existentes cuya tabla `transactions` no tenía la columna `is_archived`, aunque el código nuevo ya la consultaba.

Además, existió un estado intermedio de schema donde varias tablas usaban `archived` en lugar de `is_archived`.

También se agregó `transactions.date_confirmed` en código sin una migración local explícita.

## Tablas afectadas

- `accounts`
- `categories`
- `transactions`
- `tags`

## Cambios aplicados

1. Renombrar `archived -> is_archived` si la tabla todavía usa el nombre viejo.
2. Agregar `transactions.date_confirmed` con default `true` si la columna todavía no existe.

## Estrategia técnica

Se implementa en `apps/native/lib/database.dart` con:

- `schemaVersion = 3`
- `MigrationStrategy`
- inspección de columnas vía `PRAGMA table_info`
- `ALTER TABLE ... RENAME COLUMN ...`
- `m.addColumn(transactions, transactions.dateConfirmed)`

## SQL lógico equivalente

```sql
ALTER TABLE accounts RENAME COLUMN archived TO is_archived;
ALTER TABLE categories RENAME COLUMN archived TO is_archived;
ALTER TABLE transactions RENAME COLUMN archived TO is_archived;
ALTER TABLE tags RENAME COLUMN archived TO is_archived;

ALTER TABLE transactions
ADD COLUMN date_confirmed INTEGER NOT NULL DEFAULT 1;
```

Nota:

- No todas esas sentencias corren siempre. La migración primero inspecciona el estado real de cada tabla y aplica solo lo necesario.

## Compatibilidad

- `v1 -> v3`: renombra `transactions.archived` y agrega `date_confirmed`.
- `v2 -> v3`: renombra `archived` en `accounts`, `categories`, `transactions` y `tags`, y agrega `date_confirmed`.

## Validación

Tests agregados:

- upgrade desde `v1`
- upgrade desde `v2`

Resultado esperado:

- ya no existe la columna `archived`
- existe `is_archived`
- existe `date_confirmed`
- los valores previos de archivado se preservan
- `date_confirmed` queda inicializado en `true` para filas previas
