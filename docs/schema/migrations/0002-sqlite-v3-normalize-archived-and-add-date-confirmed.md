# 0002 SQLite v3: normalize local schema

## Alcance

Migración local de Drift/SQLite para preservar bases existentes al abrir una app con el schema actual.

Versión:

- origen: `v1` o `v2`
- destino: `v3`

## Problema que corrige

Había instalaciones existentes cuya tabla `transactions` no tenía la columna `is_archived`, aunque el código nuevo ya la consultaba.

Además, existió un estado intermedio de schema donde varias tablas usaban `archived` en lugar de `is_archived`.

También se agregó `transactions.date_confirmed` en código sin una migración local explícita.

Luego `main` incorporó persistencia local de dashboard (`saved_filters`, `dashboard_widgets`, `sync_state.dashboard_seeded`) y acentos obligatorios (`color`/`icon`) en cuentas/categorías/tags.

## Tablas afectadas

- `accounts`
- `categories`
- `transactions`
- `tags`
- `saved_filters`
- `dashboard_widgets`
- `sync_state`

## Cambios aplicados

1. Crear `saved_filters` y `dashboard_widgets` si todavía no existen.
2. Agregar `sync_state.dashboard_seeded` si todavía no existe.
3. Agregar columnas de acento si faltan: `accounts.color`, `accounts.icon`, `categories.color`, `categories.icon`, `tags.color`.
4. Completar defaults para esas columnas cuando existen pero tienen `NULL`.
5. Renombrar `archived -> is_archived` si la tabla todavía usa el nombre viejo.
6. Agregar `transactions.date_confirmed` con default `true` si la columna todavía no existe.

## Estrategia técnica

Se implementa en `apps/native/lib/database.dart` con:

- `schemaVersion = 3`
- `MigrationStrategy`
- inspección de tablas vía `sqlite_master`
- inspección de columnas vía `PRAGMA table_info`
- `m.createTable(...)`
- `m.addColumn(...)`
- `ALTER TABLE ... RENAME COLUMN ...`
- `UPDATE ... WHERE ... IS NULL` para defaults de acentos

## SQL lógico equivalente

```sql
CREATE TABLE saved_filters (...);
CREATE TABLE dashboard_widgets (...);

ALTER TABLE sync_state
ADD COLUMN dashboard_seeded INTEGER NOT NULL DEFAULT 0;

ALTER TABLE accounts ADD COLUMN color TEXT NOT NULL DEFAULT '#3B82F6';
ALTER TABLE accounts ADD COLUMN icon TEXT NOT NULL DEFAULT 'wallet';
ALTER TABLE categories ADD COLUMN color TEXT NOT NULL DEFAULT '#6366F1';
ALTER TABLE categories ADD COLUMN icon TEXT NOT NULL DEFAULT 'category';
ALTER TABLE tags ADD COLUMN color TEXT NOT NULL DEFAULT '#69F0AE';

UPDATE accounts SET color = '#3B82F6' WHERE color IS NULL;
UPDATE accounts SET icon = 'wallet' WHERE icon IS NULL;
UPDATE categories SET color = '#6366F1' WHERE color IS NULL;
UPDATE categories SET icon = 'category' WHERE icon IS NULL;
UPDATE tags SET color = '#69F0AE' WHERE color IS NULL;

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

- `v1 -> v3`: aplica dashboard local, acentos, normalización de archivado y `date_confirmed`.
- `v2 -> v3`: aplica idempotentemente lo que falte. Esto cubre tanto bases `v2` con dashboard de `main` como bases intermedias que todavía usaban `archived`.
- cualquier destino distinto del `schemaVersion` actual falla con `UnsupportedError`.

## Validación

Tests agregados:

- upgrade desde `v1`
- upgrade desde `v2`
- verificación del shape actual mínimo

Resultado esperado:

- existen `saved_filters` y `dashboard_widgets`
- existe `sync_state.dashboard_seeded`
- existen y tienen default las columnas de acento
- ya no existe la columna `archived`
- existe `is_archived`
- existe `date_confirmed`
- los valores previos de archivado se preservan
- `date_confirmed` queda inicializado en `true` para filas previas
