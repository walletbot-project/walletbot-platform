# Convex Schema

Source of truth:

- `packages/backend/convex/schema.ts`
- `packages/backend/convex/schema/*.ts`

## Tablas

### `accounts`

Campos:
- `userId`
- `id`
- `name`
- `currency`
- `description?`
- `color`
- `icon`
- `isArchived`
- `createdAt`
- `updatedAt`
- `seq`

Índices:
- `by_user_seq`
- `by_user_id`
- `by_user_archived`

### `categories`

Campos:
- `userId`
- `id`
- `name`
- `description?`
- `color`
- `icon`
- `isArchived`
- `createdAt`
- `updatedAt`
- `seq`

Índices:
- `by_user_seq`
- `by_user_id`
- `by_user_archived`

### `transactions`

Campos:
- `userId`
- `id`
- `type`
- `name`
- `description?`
- `status`
- `date`
- `accountId`
- `categoryId`
- `amount`
- `currency`
- `toAccountId?`
- `toAmount?`
- `toCurrency?`
- `exchangeRate?`
- `balanceAfter?`
- `isArchived`
- `createdAt`
- `updatedAt`
- `seq`
- `dateConfirmed`

Índices:
- `by_user_seq`
- `by_user_id`
- `by_user_date`
- `by_user_status`
- `by_user_type`
- `by_user_account_date`
- `by_user_category_date`
- `by_user_to_account`

### `tags`

Campos:
- `userId`
- `id`
- `name`
- `description?`
- `parentId?`
- `color`
- `isArchived`
- `createdAt`
- `updatedAt`
- `seq`

Índices:
- `by_user_seq`
- `by_user_id`
- `by_user_parent`
- `by_user_archived`

### `transactionTags`

Campos:
- `userId`
- `id`
- `transactionId`
- `tagId`
- `createdAt`
- `updatedAt`
- `seq`

Índices:
- `by_user_seq`
- `by_user_id`
- `by_user_transaction_tag`
- `by_user_transaction`
- `by_user_tag`

### `savedFilters`

Campos:
- `userId`
- `id`
- `name`
- `config`
- `isArchived`
- `createdAt`
- `updatedAt`
- `seq`

Índices:
- `by_user_seq`
- `by_user_id`
- `by_user_archived`

### `dashboardWidgets`

Campos:
- `userId`
- `id`
- `type`
- `filterId?`
- `position`
- `width`
- `options`
- `isArchived`
- `createdAt`
- `updatedAt`
- `seq`

Índices:
- `by_user_seq`
- `by_user_id`
- `by_user_archived`

### `syncCounters`

Campos:
- `userId`
- `value`

Índices:
- `by_user`

### `tombstones`

Campos:
- `userId`
- `tableName`
- `entityId`
- `seq`
- `deletedAt`

Índices:
- `by_user_seq`
- `by_user_table_entity`

## Notas

- Convex usa `camelCase`.
- El identificador estable entre cliente y servidor es `id`, no `_id`.
- `seq` ordena cambios globalmente por usuario para sync.
- `dateConfirmed` ya existe en backend y debe mantenerse alineado con SQLite.
- `color`/`icon` de cuentas y categorías, y `color` de tags, son obligatorios; los writers aplican defaults.
