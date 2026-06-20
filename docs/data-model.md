# WalletBot — Modelo de Datos

## Filosofía central

WalletBot usa un modelo simple y directo:

- `Cuentas`: dónde está la plata
- `Categorías`: para qué fue un movimiento o de dónde vino
- `Movimientos`: gastos, ingresos, transferencias y ajustes
- `Tags`: etiquetas reutilizables, opcionales

La app trabaja con esos conceptos de forma explícita. No expone lógica contable interna ni conceptos técnicos al usuario.

---

## Conceptos visibles en la app

### Cuenta

Dónde vive la plata.

Ejemplos:
- Efectivo
- BBVA
- Galicia
- Visa
- Mercado Pago

Cada cuenta tiene una moneda fija.

### Categoría

Sirve para clasificar movimientos.

Ejemplos:
- Comida
- Transporte
- Sueldo
- Regalos

Las categorías no tienen tipo. La app sabe si algo fue ingreso o gasto por el
`type` del movimiento.

### Movimiento

Una operación registrada en la app.

Tipos:
- `expense`
- `income`
- `transfer`
- `balance_adjustment`

### Tag

Etiqueta libre, reutilizable, asociable a movimientos. Pueden formar jerarquía
opcional vía `parentId`.

---

## Reglas del modelo

- Un `expense` resta saldo de una cuenta y usa una categoría.
- Un `income` suma saldo a una cuenta y usa una categoría.
- Un `transfer` mueve saldo entre dos cuentas.
- Un `balance_adjustment` corrige el saldo de una cuenta y deja trazabilidad.
- Una cuenta tiene una sola moneda.
- Los tags son globales por usuario y reutilizables.

---

## Identidad: `id` (uuid) vs `_id` (Convex)

Cada fila tiene **dos** identificadores distintos:

- `id` — UUID generado por el cliente. Es el identificador estable que viaja
  entre cliente y servidor, y el que aparece en relaciones (`accountId`,
  `categoryId`, `transactionId`, `tagId`, etc.) y en tombstones. **Este es el
  id de negocio.**
- `_id` — id interno de Convex (`Id<"accounts">`, etc.). Solo se usa dentro de
  Convex. **Nunca se referencia desde el cliente ni desde otra tabla.**

Las relaciones entre entidades (e.g. `transactions.accountId →
accounts.id`) usan el UUID, no el `_id`.

---

## Sincronización

### Contador global por usuario

Cada usuario tiene un contador monotónico (`syncCounters.value`, `int64`).
Cualquier mutación en Convex que toque datos del usuario debe, dentro de la
misma transacción:

1. Incrementar el contador del usuario en `+1`.
2. Estampar el nuevo valor en el campo `seq` de cada fila afectada.
3. Si la mutación borra una fila, escribir el tombstone con ese mismo `seq`.

`seq` actúa como un timestamp lógico y ordena globalmente todos los cambios de
un usuario.

### Estado del cliente

El cliente (Drift) mantiene:

- `SyncState.lastServerSeq` — el `seq` más alto que ya pulleó del servidor.
  Singleton.
- Por fila local: `version` (contador local que se incrementa en cada edición)
  y `remoteVersion` (el `version` confirmado por el server). Una fila está
  *sucia* y necesita push cuando `remoteVersion IS NULL OR version !=
  remoteVersion`.

### Pull (servidor → cliente)

El cliente envía `lastServerSeq`. El servidor responde, para el usuario
autenticado:

- Filas con `seq > lastServerSeq` en cada tabla sincronizada.
- Tombstones con `seq > lastServerSeq`.
- El valor actual del contador para que el cliente lo guarde como
  `lastServerSeq` en el próximo pull.

El cliente aplica upserts por `id` (UUID) y borra las filas listadas en
tombstones.

### Push (cliente → servidor)

El cliente envía las filas sucias y los tombstones sucios. El servidor, para
cada uno: incrementa el contador, estampa `seq`, hace upsert (o delete +
tombstone) por UUID, y devuelve confirmación. El cliente marca las filas
empujadas como limpias (`remoteVersion = version`).

### Borrados

No hay soft delete a nivel UI: cuando el usuario borra una entidad, la fila se
elimina y se inserta un tombstone con el mismo `seq`. Las consultas normales
nunca leen filas borradas.

---

## Tablas Convex

Convención: todas las tablas owneadas por usuario tienen `userId: string`
(identidad provista por better-auth), `id: string` (UUID), y
`seq: int64`. Los timestamps (`createdAt`, `updatedAt`, `date`, `deletedAt`)
son `int64` (ms desde epoch) para alinear con la representación del cliente.

### `accounts`

```text
userId         string
id             string             — uuid
name           string
currency       string             — moneda fija
description?   string
color?         string             — hex
icon?          string             — de lista predefinida
isArchived     boolean
createdAt      int64
updatedAt      int64
seq            int64
```

Índices: `by_user_seq`, `by_user_id`, `by_user_archived`

---

### `categories`

```text
userId         string
id             string             — uuid
name           string
description?   string
isArchived     boolean
createdAt      int64
updatedAt      int64
seq            int64
```

Índices: `by_user_seq`, `by_user_id`, `by_user_archived`

---

### `transactions`

```text
userId          string
id              string             — uuid

type            "expense" | "income" | "transfer" | "balance_adjustment"
name            string
description?    string
status          "pending" | "cleared"
date            int64              — ms epoch

accountId       string             — uuid de la cuenta origen / principal
amount          int64              — centavos
currency        string             — debe coincidir con accountId.currency
categoryId      string             — uuid de categoría

toAccountId?    string             — uuid (transferencias)
toAmount?       int64              — centavos (transferencias)
toCurrency?     string             — moneda destino (transferencias)
exchangeRate?   number             — float (transferencias con conversión)

balanceAfter?   int64              — centavos (ajustes de balance)

isArchived      boolean
createdAt       int64
updatedAt       int64
seq             int64
```

Índices:
- `by_user_seq`
- `by_user_id`
- `by_user_date`
- `by_user_status`
- `by_user_type`
- `by_user_account_date`
- `by_user_category_date`
- `by_user_to_account`

---

### `tags`

```text
userId         string
id             string             — uuid
name           string
description?   string
parentId?      string             — uuid de tag padre (jerarquía opcional)
color?         string             — hex
isArchived     boolean
createdAt      int64
updatedAt      int64
seq            int64
```

Índices: `by_user_seq`, `by_user_id`, `by_user_parent`, `by_user_archived`

---

### `transactionTags`

Relación N a N entre movimientos y tags. Tiene su propio `id` (UUID) para que
el modelo de sync sea uniforme; la unicidad lógica es `(userId,
transactionId, tagId)`.

```text
userId          string
id              string             — uuid del join
transactionId   string             — uuid del movimiento
tagId           string             — uuid del tag
createdAt       int64
updatedAt       int64
seq             int64
```

Índices: `by_user_seq`, `by_user_id`, `by_user_transaction_tag`,
`by_user_transaction`, `by_user_tag`

---

### `syncCounters`

Una fila por usuario. Fuente de verdad del contador monotónico.

```text
userId   string
value    int64
```

Índice: `by_user`

---

### `tombstones`

Registro de borrados para que el sync los propague al cliente.

```text
userId      string
tableName   "accounts" | "categories" | "transactions" | "tags" | "transactionTags"
entityId    string             — uuid de la fila borrada
seq         int64
deletedAt   int64
```

Índices: `by_user_seq`, `by_user_table_entity`

---

## Tablas del cliente (Drift)

El cliente espeja el modelo de Convex con dos diferencias estructurales:

1. **No hay `userId`** — el cliente sirve a un único usuario autenticado.
2. **No tiene `seq` por fila.** En su lugar usa `version` / `remoteVersion`
   para saber si la fila está sucia, y un `SyncState` singleton para
   `lastServerSeq` global.

Cada tabla espejo (`accounts`, `categories`, `transactions`, `tags`,
`transaction_tags`) tiene la misma forma que su contraparte en Convex más:

```text
version          int64    — contador local (1 al crear, +1 en cada edición)
remoteVersion?   int64    — último version confirmado por el server (NULL si nunca se sincronizó)
```

Una fila está sucia (necesita push) cuando
`remoteVersion IS NULL OR version != remoteVersion`. Cada tabla tiene un
índice parcial `<table>_needs_sync` con esa condición exacta.

### `sync_state`

Singleton (PK fija = `'singleton'`).

```text
id               string
last_server_seq  int64    — el seq más alto que ya pulleamos
last_synced_at?  int64
```

### `tombstones` (Drift)

```text
entity_table     string
entity_id        string
deleted_at       int64
created_at       int64
updated_at       int64
version          int64
remote_version?  int64
```

PK: `(entity_table, entity_id)`. Sigue la misma convención de versionado que
las tablas de entidades para saber qué tombstones quedan por empujar.

---

## Ejemplos

**Gasto — "Starbucks, $5.50 en efectivo"**

```js
{
  id: "uuid_txn_1",
  userId: "usr_1",
  type: "expense",
  name: "Starbucks",
  status: "cleared",
  date: 1745712000000n,
  accountId: "uuid_acc_efectivo",
  categoryId: "uuid_cat_cafe",
  amount: 550n,
  currency: "ARS",
  isArchived: false,
  createdAt: 1745712000000n,
  updatedAt: 1745712000000n,
  seq: 42n
}
```

**Ingreso — "Sueldo de abril"**

```js
{
  id: "uuid_txn_2",
  userId: "usr_1",
  type: "income",
  name: "Sueldo abril",
  status: "cleared",
  date: 1746057600000n,
  accountId: "uuid_acc_bbva",
  categoryId: "uuid_cat_sueldo",
  amount: 200000n,
  currency: "ARS",
  isArchived: false,
  createdAt: 1746057600000n,
  updatedAt: 1746057600000n,
  seq: 43n
}
```

**Transferencia — "Pase $500 a Galicia"**

```js
{
  id: "uuid_txn_3",
  userId: "usr_1",
  type: "transfer",
  name: "Pase a ahorro",
  status: "cleared",
  date: 1745280000000n,
  accountId: "uuid_acc_bbva",
  categoryId: "uuid_cat_transfer",
  amount: 50000n,
  currency: "ARS",
  toAccountId: "uuid_acc_galicia",
  toAmount: 50000n,
  toCurrency: "ARS",
  isArchived: false,
  createdAt: 1745280000000n,
  updatedAt: 1745280000000n,
  seq: 44n
}
```

**Transferencia con conversión — "Compré USD 100 pagando $100.000 ARS"**

```js
{
  id: "uuid_txn_4",
  userId: "usr_1",
  type: "transfer",
  name: "Compra USD",
  status: "cleared",
  date: 1744243200000n,
  accountId: "uuid_acc_ars",
  categoryId: "uuid_cat_transfer",
  amount: 1000000n,
  currency: "ARS",
  toAccountId: "uuid_acc_usd",
  toAmount: 10000n,
  toCurrency: "USD",
  exchangeRate: 100,
  isArchived: false,
  createdAt: 1744243200000n,
  updatedAt: 1744243200000n,
  seq: 45n
}
```

**Ajuste de balance — "Conté efectivo y había $200"**

```js
{
  id: "uuid_txn_5",
  userId: "usr_1",
  type: "balance_adjustment",
  name: "Ajuste de saldo",
  status: "cleared",
  date: 1735689600000n,
  accountId: "uuid_acc_efectivo",
  categoryId: "uuid_cat_ajuste",
  amount: 20000n,
  currency: "ARS",
  balanceAfter: 20000n,
  isArchived: false,
  createdAt: 1735689600000n,
  updatedAt: 1735689600000n,
  seq: 46n
}
```

**Tags reutilizables**

```js
// tags
{
  id: "uuid_tag_1",
  userId: "usr_1",
  name: "trabajo",
  color: "#4F46E5",
  isArchived: false,
  createdAt: 1746057600000n,
  updatedAt: 1746057600000n,
  seq: 47n
}

// transactionTags
{
  id: "uuid_tt_1",
  userId: "usr_1",
  transactionId: "uuid_txn_2",
  tagId: "uuid_tag_1",
  createdAt: 1746057600000n,
  updatedAt: 1746057600000n,
  seq: 48n
}
```

**Tombstone — borrado de un movimiento**

```js
{
  userId: "usr_1",
  tableName: "transactions",
  entityId: "uuid_txn_2",
  seq: 99n,
  deletedAt: 1746500000000n
}
```

---

## Validaciones importantes

### `expense`
- requiere `categoryId`
- `currency` debe coincidir con la moneda de `accountId`

### `income`
- requiere `categoryId`
- `currency` debe coincidir con la moneda de `accountId`

### `transfer`
- requiere `toAccountId`
- `accountId !== toAccountId`
- `currency` debe coincidir con la moneda de `accountId`
- `toCurrency` debe coincidir con la moneda de `toAccountId`
- `toAmount` y `toCurrency` permiten transferencias con o sin conversión

### `balance_adjustment`
- ajusta el saldo de una cuenta por diferencia real
- `balanceAfter` permite guardar el saldo final observado

---

## Aggregates

Para no recalcular balances y totales en cada query, los aggregates se
actualizan en cada mutación que crea, edita o elimina transacciones.

### Balance por cuenta

Clave:

```text
(accountId)
```

Valor:
- saldo actual de la cuenta en su moneda fija

Reglas de actualización:
- `expense`: `-amount`
- `income`: `+amount`
- `transfer`: `-amount` en origen, `+toAmount` en destino
- `balance_adjustment`: `+amount`

---

### Totales por categoría

Clave recomendada:

```text
(categoryId, month, currency, transactionType)
```

Valor:

```text
SUM(amount)
```

Como la categoría no tiene tipo, `transactionType` es parte del aggregate.

Esto permite:
- gastos por categoría
- ingresos por categoría
- dashboards mensuales
- acumulados por subárbol de categorías

---

### Tags

Aggregates por tag requiere un tratamiento más complejo todavía no definido.

---

## Lo que ve el usuario

La UI sigue siendo simple:

- `Cuentas`
- `Categorías`
- `Movimientos`
- `Tags`

El usuario crea movimientos claros y explícitos. El sistema mantiene saldos,
reportes, filtros y conversiones sin exponer complejidad innecesaria.
