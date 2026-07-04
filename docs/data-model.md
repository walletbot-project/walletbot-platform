# WalletBot — Modelo de Datos

Ver también:
- [Schema docs](./schema/README.md)

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

### Filosofía

La resolución de conflictos vive **en el cliente**. El servidor solo valida
legalidad (ownership, FKs, coherencia de moneda) y aplica un *compare-and-swap*
sobre el contador del usuario antes de aceptar un push. Si el push es
"fast-forward" (el cliente está al día), pasa; si no, el cliente debe primero
pullear, mergear localmente y reintentar.

Last-write-wins por `updatedAt` (cliente) y `deletedAt` (tombstones) es la
regla universal de resolución.

### Resolución de conflictos (decisión actual)

> Esta es la decisión tomada **hasta este punto**. No es necesariamente
> definitiva: el algoritmo de conflictos puede revisarse más adelante.

Adoptamos **last-write-wins (LWW) a nivel de fila**:

- Ante ediciones concurrentes de la misma entidad desde dos dispositivos,
  gana **completa** la versión con el `updatedAt` mayor (`deletedAt` para
  borrados). La versión perdedora se descarta entera.
- La resolución es **por fila, no por campo**: no hay merge campo a campo.
- En empate exacto de timestamp, gana el lado local (`>=`), lo que mantiene
  la operación determinística y evita oscilaciones.

**Por qué LWW.** Es simple, predecible y no requiere estado de conflicto ni
intervención del usuario. Para un caso de uso personal —donde un mismo
usuario rara vez edita la misma entidad en dos dispositivos a la vez— es un
trade-off razonable frente a la complejidad de un merge campo a campo o de
CRDTs.

**Riesgo asumido: pequeña pérdida de datos.** Si dos dispositivos editan la
misma fila antes de sincronizar, los cambios del que pierde el LWW se
pierden silenciosamente. Ejemplo: el dispositivo A cambia el `amount` de un
movimiento y el dispositivo B cambia su `name`; al sincronizar, solo
sobrevive el conjunto de cambios de la fila con `updatedAt` mayor, y la otra
edición desaparece. No hay aviso al usuario ni registro del descarte.

Asumimos este riesgo conscientemente porque:

- El blast radius es chico: afecta una sola fila y solo bajo edición
  concurrente real, que es poco frecuente en uso personal.
- No corrompe el modelo: el resultado siempre es un estado válido y
  consistente (una de las dos versiones completas), nunca una mezcla
  incoherente.
- Los borrados siguen la misma regla, así que tampoco hay "resurrección"
  inconsistente de filas.

Si en el futuro este trade-off resulta insuficiente (p. ej. edición
multi-dispositivo frecuente), las alternativas a evaluar son merge a nivel
de campo o estructuras CRDT, ambas con costo de complejidad mayor.

### Contador global por usuario

Cada usuario tiene un contador monotónico (`syncCounters.value`, `int64`).
Cualquier mutación en Convex que toque datos del usuario debe, dentro de la
misma transacción:

1. Incrementar el contador del usuario en `+1`.
2. Estampar el nuevo valor en el campo `seq` de cada fila afectada.
3. Si la mutación borra una fila, escribir el tombstone con ese mismo `seq`.

`seq` actúa como un timestamp lógico y ordena globalmente todos los cambios
de un usuario. **`nextSeq()` se llama una sola vez por mutación**; el valor
devuelto se reutiliza para todas las filas y tombstones escritos en esa
mutación.

### Estado del cliente

El cliente (Drift) mantiene:

- `sync_state.last_server_seq` — el `seq` más alto pulleado **y aplicado
  completamente**. Singleton. Se usa con doble propósito:
  - cursor de pull (`seq > last_server_seq`),
  - expectativa de CAS para push (el cliente le dice al server "yo creo que
    tu contador está en X; aceptá mi push solo si es cierto").
- Por fila local: `dirty` (bool). `true` cuando la fila tiene cambios locales
  no pusheados. Cada tabla tiene un índice parcial `<table>_needs_sync` con
  `WHERE dirty = 1` para barrer rápido las filas a empujar.
- `updatedAt` (int64, ms epoch) — fuente de verdad para last-write-wins. El
  cliente lo actualiza en cada edición local; el servidor lo respeta tal como
  llega (no lo regenera).

### Pull (servidor → cliente) — paginado

El cliente envía `{ since: last_server_seq, limit }`. El servidor responde,
en una sola query y para el usuario autenticado:

- Hasta `limit` filas con `seq > since`, ordenadas por `(seq, id)`
  ascendente, recorriendo todas las tablas sincronizadas.
- Hasta `limit` tombstones con `seq > since`, en el mismo orden.
- `{ nextCursor, hasMore, currentCounter }`:
  - `nextCursor` — el `(seq, id)` del último registro devuelto (o `null` si
    la página vino vacía).
  - `hasMore` — `true` si hay más registros después de `nextCursor`.
  - `currentCounter` — `syncCounters.value` al momento de la query.

El cliente:

1. Aplica las filas y tombstones de la página (ver "Merge local").
2. Si `hasMore`, vuelve a pullear con el cursor avanzado.
3. Cuando `hasMore = false`, fija `last_server_seq = currentCounter`. **Solo
   entonces** el cursor es seguro para usar como CAS en push.

> **Importante.** No avanzar `last_server_seq` hasta drenar todas las
> páginas. Si el cliente se cae a mitad de pull, en el próximo arranque
> retoma desde el `last_server_seq` ya commiteado y vuelve a paginar.

### Merge local (al aplicar pull)

Para cada **fila remota** con id `X`:

- Si no existe local → insertar; `dirty = false`.
- Si existe local con `dirty = false` → upsert remoto; `dirty = false`.
- Si existe local con `dirty = true`:
  - `local.updatedAt >= remote.updatedAt` → mantener local, sigue `dirty = true`.
  - `local.updatedAt <  remote.updatedAt` → tomar remoto; `dirty = false`.
- Si existe **tombstone local** para `X`:
  - `local_tombstone.deletedAt >= remote.updatedAt` → mantener tombstone
    (el borrado local es más nuevo, prevalecerá en el próximo push).
  - `local_tombstone.deletedAt <  remote.updatedAt` → borrar tombstone e
    insertar la fila remota; `dirty = false`.

Para cada **tombstone remoto** sobre entidad `X`:

- Si existe fila local `X`:
  - `local.updatedAt >  remote_tombstone.deletedAt` → **mantener** la fila
    local; pisa al tombstone en el próximo push (el server tendrá que borrar
    el tombstone y reinsertar la fila).
  - `local.updatedAt <= remote_tombstone.deletedAt` → borrar fila local;
    insertar tombstone local con `dirty = false`.
- Si no existe fila local → insertar tombstone con `dirty = false`.

Para cada **tombstone local con `dirty = true`** que aparece como fila viva
en el servidor: misma regla por `deletedAt` vs `updatedAt`. Si el server
gana, descartar tombstone (y tomar la fila remota). Si el cliente gana,
mantener tombstone, sigue `dirty = true`.

### Recompute de `balance_adjustment` post-pull

Después de drenar el pull, el cliente recorre las transacciones del usuario
en orden cronológico (`date` ascendente) recomputando saldo por cuenta.

Cada `balance_adjustment` tiene un `balanceAfter` que es la fuente de
verdad: si `saldo_previo + amount != balanceAfter`, el cliente corrige
`amount` (= `balanceAfter - saldo_previo`) y marca la fila `dirty = true`
para que el siguiente push propague el ajuste.

Esto garantiza la invariante "`balanceAfter` siempre matchea" frente a
inserciones tardías de transacciones desde otro dispositivo.

### Push (cliente → servidor) — particionado y con CAS

Push es una sucesión de chunks. Cada chunk es **una sola mutación de
Convex** y avanza el contador del usuario en `+1`.

#### Orden de chunks

1. **Chunk de catálogo** (siempre primero, todo en una mutación):
   - todas las `accounts` con `dirty = true`,
   - todas las `categories` con `dirty = true`,
   - todas las `tags` con `dirty = true`,
   - sus tombstones dirty.

   Estas tablas son chicas y son referenciadas por integridad referencial
   desde `transactions` / `transactionTags`: deben existir en server antes
   que las filas que las referencian.

2. **Chunks de movimientos**, transacciones ordenadas por `date`
   ascendente:
   - hasta `N` `transactions` dirty por chunk (`N` calibrado debajo de los
     límites de mutación de Convex),
   - los `transactionTags` dirty cuyos `transactionId` ya estén en server o
     vayan en el mismo chunk,
   - los tombstones de `transactions` y `transactionTags` cuyo `deletedAt`
     caiga dentro del rango temporal del chunk.

#### Forma del chunk

```json
{
  "expectedServerSeq": <last_server_seq>,
  "upserts": {
    "accounts":        [...],
    "categories":      [...],
    "tags":            [...],
    "transactions":    [...],
    "transactionTags": [...]
  },
  "tombstones": [
    { "tableName": "...", "entityId": "...", "deletedAt": <int64> }
  ]
}
```

Servidor:

1. Lee `syncCounters.value` (= `currentCounter`).
2. Si `currentCounter != expectedServerSeq` → rechaza con
   `{ error: "cursor_mismatch", currentCounter }`.
3. Valida cada upsert (ownership por `userId`, existencia de FKs,
   coherencia de moneda, shape del payload). Si algo es ilegal → rechaza el
   chunk entero.
4. Incrementa el contador a `currentCounter + 1` (= `newSeq`).
5. Por cada upsert:
   - upsert por `(userId, id)`, estampa `seq = newSeq` y respeta el
     `updatedAt` del cliente.
   - **Si existe un tombstone** para esa `(userId, tableName, entityId)`,
     **lo borra** (el cliente ya decidió localmente, vía la regla
     `updatedAt > deletedAt`, que la fila gana).
6. Por cada tombstone:
   - borra la fila si existe y escribe/actualiza el tombstone con
     `seq = newSeq`, `deletedAt` del cliente.
7. Devuelve `{ newSeq }`.

Cliente (al recibir `newSeq`):

1. `last_server_seq = newSeq`.
2. Por cada fila upserteada en este chunk: si `local.updatedAt ==
   payload.updatedAt` (no fue re-editada durante el push) → `dirty = false`.
   Si no → se queda `dirty = true` para el próximo round.
3. Por cada tombstone pusheado: mismo criterio sobre `deletedAt`.

#### Cursor mismatch

Si un chunk falla con `cursor_mismatch`:

1. El cliente pausa el push.
2. Hace un pull completo (paginado) hasta drenar.
3. Re-mergea localmente (incluye el recompute de `balance_adjustment`).
4. Reanuda el push desde el chunk que falló, con el nuevo
   `expectedServerSeq` y con las filas que sigan `dirty = true` post-merge.

#### Atomicidad por chunk

Un chunk se commitea entero o se rechaza entero. El push completo a través
de múltiples chunks **no** es atómico: si el chunk 3 de 5 falla por
`cursor_mismatch`, los chunks 1 y 2 ya quedaron en server. Eso es OK porque
las filas ya pusheadas tienen su `seq` y los pulls de otros dispositivos las
verán; el cliente reanuda desde donde quedó.

### Borrados

No hay soft delete a nivel UI. Cuando el usuario borra una entidad:

1. Local: se elimina la fila y se inserta un tombstone con
   `deletedAt = Date.now()`, `dirty = true`.
2. En el próximo push, el tombstone viaja en el chunk correspondiente; el
   server borra la fila (si aún existe) y persiste el tombstone con el
   `seq` del chunk.
3. Otros dispositivos, al pullear el tombstone, aplican la regla
   `local.updatedAt vs deletedAt` para decidir borrar localmente o
   resurrectar la fila.

Las queries normales nunca leen filas borradas: el delete es físico en
cliente y server.

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
color          string             — hex, con default
icon           string             — de lista predefinida, con default
archived       boolean
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
color          string             — hex, con default
icon           string             — de lista predefinida, con default
archived       boolean
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
dateConfirmed   boolean            — confianza en la fecha

archived        boolean
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
color          string             — hex, con default
archived       boolean
createdAt      int64
updatedAt      int64
seq            int64
```

Índices: `by_user_seq`, `by_user_id`, `by_user_parent`, `by_user_archived`

---

### `transactionTags`

Relación N a N entre movimientos y tags. Tiene su propio `id` para que el
modelo de sync sea uniforme; la unicidad lógica es
`(userId, transactionId, tagId)`.

```text
userId          string
id              string             — derivado determinísticamente, ver "Safeguards" abajo
transactionId   string             — uuid del movimiento
tagId           string             — uuid del tag
createdAt       int64
updatedAt       int64
seq             int64
```

Índices: `by_user_seq`, `by_user_id`, `by_user_transaction_tag`,
`by_user_transaction`, `by_user_tag`

#### Safeguards contra joins duplicados

El riesgo: dos dispositivos, sin haberse sincronizado entre sí, agregan el
mismo `tag` al mismo `transaction`. Si cada uno generara un UUID random
distinto para su fila de join, el servidor terminaría con dos filas
representando la misma relación lógica.

Defensa en capas:

1. **`id` determinístico, no random.** El `id` de un `transactionTags` se
   deriva exclusivamente de sus partes:

   ```
   id = `${transactionId}__${tagId}`
   ```

   Dos dispositivos que decidan independientemente agregar el mismo tag al
   mismo transaction producen **el mismo `id`**. El upsert por `(userId, id)`
   en el servidor colapsa los dos pushes a una sola fila de manera natural,
   sin necesidad de lógica de dedup explícita. El cliente debe construir el
   `id` con esta fórmula en cada inserción local.

2. **Constraint local SQLite.** La tabla `transaction_tags` en Drift declara
   `uniqueKeys: [{transactionId, tagId}]`. Cualquier intento de insertar un
   duplicado dentro del mismo dispositivo falla con constraint error antes
   de tocar el sync. Esto previene bugs de UI (doble click, etc.).

3. **Lookup defensivo en el push del servidor.** Antes de insertar/upsertear
   un `transactionTags`, el handler de push valida:
   - que `transactionId` exista y pertenezca al `userId`,
   - que `tagId` exista y pertenezca al `userId`,
   - que el `id` recibido coincida con el formato esperado
     (`${transactionId}__${tagId}`).

   La tercera validación rechaza explícitamente con `invalid_join_id`
   cualquier payload cuyo `id` no respete el formato canónico, en vez de
   aceptar silenciosamente filas duplicadas.

#### Borrado

Cuando se borra una `transaction`, el cliente, en la misma operación local:

1. Marca la fila de `transactions` para borrar (tombstone con
   `entity_table = "transactions"`, `entity_id = transactionId`).
2. Para cada `transactionTags` con ese `transactionId`, lo borra localmente
   y emite su propio tombstone (`entity_table = "transactionTags"`,
   `entity_id = "${transactionId}__${tagId}"`).

El servidor **no** hace cascade automático: si el cliente olvida emitir los
tombstones de los joins, esas filas quedan huérfanas en server hasta que
otro dispositivo las limpie. El cliente es responsable de la coherencia
referencial al borrar.

---

### `savedFilters`

Vistas guardadas de movimientos. `config` es JSON opaco para el backend.

```text
userId         string
id             string             — uuid
name           string
config         string             — JSON canónico del filtro
archived       boolean
createdAt      int64
updatedAt      int64
seq            int64
```

Índices: `by_user_seq`, `by_user_id`, `by_user_archived`

---

### `dashboardWidgets`

Widgets configurados del home dashboard. `options` es JSON opaco para el backend.

```text
userId         string
id             string             — uuid
type           string             — "stat" | "list" | "balance"
filterId?      string             — uuid de saved filter
position       number
width          string             — "full" | "half" | "third"
options        string             — JSON de presentación
archived       boolean
createdAt      int64
updatedAt      int64
seq            int64
```

Índices: `by_user_seq`, `by_user_id`, `by_user_archived`

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

1. **No hay `userId`** — la base es por usuario autenticado
   (`AppDatabase.forUser(userId)`).
2. **No hay `seq` por fila.** En su lugar, cada tabla tiene un boolean
   `dirty` y el módulo de sync usa el singleton
   `sync_state.last_server_seq` como cursor global (tanto para pull como
   para push).

Cada tabla espejo (`accounts`, `categories`, `transactions`, `tags`,
`transaction_tags`) tiene la misma forma que su contraparte en Convex más:

```text
dirty   bool   — true si la fila tiene cambios locales no pusheados
```

Cada tabla tiene un índice parcial `<table>_needs_sync` con `WHERE dirty = 1`
para barrer rápido las filas a empujar.

### `sync_state`

Singleton (PK fija = `'singleton'`).

```text
id               string
last_server_seq  int64    — el seq más alto pulleado y aplicado completamente
last_synced_at?  int64
```

### `tombstones` (Drift)

```text
entity_table     string
entity_id        string
deleted_at       int64
created_at       int64
updated_at       int64
dirty            bool
```

PK: `(entity_table, entity_id)`. Mismo modelo de `dirty` que las entidades
para saber qué tombstones quedan por empujar.

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
  archived: false,
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
  archived: false,
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
  archived: false,
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
  archived: false,
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
  archived: false,
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
  archived: false,
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
