# SQLite Schema

Source of truth:

- `apps/native/lib/database.dart`

Implementación:

- ORM: Drift
- Motor: SQLite
- Archivo generado relacionado: `apps/native/lib/database.g.dart`

## Estado actual

- `schemaVersion` actual en código: `1`
- El schema en código ya incluye columnas nuevas como `transactions.is_archived` y `transactions.date_confirmed`
- No hay `MigrationStrategy` documentada ni implementada todavía

Esto implica que una instalación nueva y una base ya existente pueden divergir.

## Tablas

### `accounts`

Columnas:
- `id`
- `name`
- `currency`
- `description?`
- `color?`
- `icon?`
- `is_archived`
- `created_at`
- `updated_at`
- `dirty`

Índices:
- `accounts_archived`
- `accounts_updated_at`
- `accounts_needs_sync`

### `categories`

Columnas:
- `id`
- `name`
- `description?`
- `is_archived`
- `created_at`
- `updated_at`
- `dirty`

Índices:
- `categories_archived`
- `categories_updated_at`
- `categories_needs_sync`

### `transactions`

Columnas:
- `id`
- `type`
- `name`
- `description?`
- `status`
- `date`
- `account_id`
- `category_id`
- `amount`
- `currency`
- `date_confirmed`
- `to_account_id?`
- `to_amount?`
- `to_currency?`
- `exchange_rate?`
- `balance_after?`
- `is_archived`
- `created_at`
- `updated_at`
- `dirty`

Índices:
- `transactions_account_id`
- `transactions_category_id`
- `transactions_to_account_id`
- `transactions_date`
- `transactions_status`
- `transactions_type`
- `transactions_archived`
- `transactions_updated_at`
- `transactions_account_id_date`
- `transactions_category_id_date`
- `transactions_needs_sync`

### `tags`

Columnas:
- `id`
- `name`
- `description?`
- `parent_id?`
- `color?`
- `is_archived`
- `created_at`
- `updated_at`
- `dirty`

Índices:
- `tags_parent_id`
- `tags_archived`
- `tags_updated_at`
- `tags_needs_sync`

### `transaction_tags`

Columnas:
- `id`
- `transaction_id`
- `tag_id`
- `created_at`
- `updated_at`
- `dirty`

Índices:
- `transaction_tags_transaction_id`
- `transaction_tags_tag_id`
- `transaction_tags_updated_at`
- `transaction_tags_needs_sync`

Restricciones:
- unique key: `(transaction_id, tag_id)`

### `sync_state`

Columnas:
- `id`
- `last_server_seq`
- `last_synced_at?`

### `tombstones`

Columnas:
- `entity_table`
- `entity_id`
- `deleted_at`
- `created_at`
- `updated_at`
- `dirty`

Índices:
- `tombstones_entity_table`
- `tombstones_updated_at`
- `tombstones_needs_sync`

## Notas

- SQLite usa `snake_case`.
- `dirty` marca cambios locales pendientes de push.
- `sync_state` guarda el cursor de pull/CAS del cliente.
- La próxima migración formal debería documentar el upgrade desde la base `v1` hacia este schema efectivo.
