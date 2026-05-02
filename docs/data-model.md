# WalletBot — Modelo de Datos

## Filosofía central

WalletBot usa un modelo simple y directo:

- `Cuentas`: dónde está la plata
- `Categorías`: para qué fue un movimiento o de dónde vino
- `Movimientos`: gastos, ingresos, transferencias y ajustes

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

---

## Reglas del modelo

- Un `expense` resta saldo de una cuenta y usa una categoría.
- Un `income` suma saldo a una cuenta y usa una categoría.
- Un `transfer` mueve saldo entre dos cuentas.
- Un `balance_adjustment` corrige el saldo de una cuenta y deja trazabilidad.
- Una cuenta tiene una sola moneda.
- Los tags son globales por usuario y reutilizables.

---

## Ejemplos

**Gasto — "Starbucks, $5.50 en efectivo"**

```js
{
  _id: "txn_1",
  userId: "usr_1",
  type: "expense",
  date: 1745712000000,
  description: "Starbucks",
  status: "cleared", // Yo creo que lo podemos revisar pero estaba en el doc de Pablo
  accountId: "acc_efectivo",
  amount: 550,
  currency: "ARS",
  categoryId: "cat_cafe",
  createdAt: 1745712000000,
  updatedAt: 1745712000000
}
```

**Ingreso — "Sueldo de abril"**

```js
{
  _id: "txn_2",
  userId: "usr_1",
  type: "income",
  date: 1746057600000,
  description: "Sueldo abril",
  status: "cleared",
  accountId: "acc_bbva",
  amount: 200000,
  currency: "ARS",
  categoryId: "cat_sueldo",
  createdAt: 1746057600000,
  updatedAt: 1746057600000
}
```

**Transferencia — "Pase $500 a Galicia"**

```js
{
  _id: "txn_3",
  userId: "usr_1",
  type: "transfer",
  date: 1745280000000,
  description: "Pase a ahorro",
  status: "cleared",
  accountId: "acc_bbva",
  amount: 50000,
  currency: "ARS",
  toAccountId: "acc_galicia",
  toAmount: 50000,
  toCurrency: "ARS",
  createdAt: 1745280000000,
  updatedAt: 1745280000000
}
```

**Transferencia con conversión — "Compré USD 100 pagando $100.000 ARS"**

```js
{
  _id: "txn_4",
  userId: "usr_1",
  type: "transfer",
  date: 1744243200000,
  description: "Compra USD",
  status: "cleared",
  accountId: "acc_ars",
  amount: 1000000,
  currency: "ARS",
  toAccountId: "acc_usd",
  toAmount: 10000,
  toCurrency: "USD",
  exchangeRate: 100,
  createdAt: 1744243200000,
  updatedAt: 1744243200000
}
```

**Ajuste de balance — "Conté efectivo y había $200"**

```js
{
  _id: "txn_5",
  userId: "usr_1",
  type: "balance_adjustment",
  date: 1735689600000,
  description: "Ajuste de saldo",
  status: "cleared",
  accountId: "acc_efectivo",
  amount: 20000,
  currency: "ARS",
  balanceAfter: 20000,
  createdAt: 1735689600000,
  updatedAt: 1735689600000
}
```

**Tags reutilizables**

```js
// tags
{
  _id: "tag_1",
  userId: "usr_1",
  name: "trabajo",
  color: "#4F46E5",
  isArchived: false,
  createdAt: 1746057600000,
  updatedAt: 1746057600000
}

// transactionTags
{
  _id: "tt_1",
  userId: "usr_1",
  transactionId: "txn_2",
  tagId: "tag_1",
  createdAt: 1746057600000
}
```

---

## Tablas Convex

### `accounts`

Cuentas visibles para el usuario.

```text
userId        id("users")
name          string
type          "cash" | "bank" | "credit_card" | "wallet" | "investment"
currency      string               — moneda fija de la cuenta
note?         string
isArchived    boolean
isDefault     boolean
sortOrder?    number
createdAt     number
updatedAt     number
```

Índices: `by_user`, `by_user_type`

---

### `categories`

Categorías neutrales para clasificar movimientos.

```text
userId        id("users")
name          string
parentId?     id("categories")
note?         string
isArchived    boolean
isDefault     boolean
sortOrder?    number
createdAt     number
updatedAt     number
```

Índices: `by_user`, `by_user_parent`

---

### `transactions`

Movimiento principal de la app.

```text
userId            id("users")
type              "expense" | "income" | "transfer" | "balance_adjustment"
date              number
description       string
note?             string
status            "pending" | "cleared"

accountId         id("accounts")     — cuenta origen o principal
amount            number             — entero en centavos
currency          string             — debe coincidir con accountId.currency

categoryId?       id("categories")   — requerido en expense/income

toAccountId?      id("accounts")     — requerido en transfer
toAmount?         number             — monto destino
toCurrency?       string             — moneda destino
exchangeRate?     number             — cotización usada como snapshot

balanceAfter?     number             — saldo resultante, útil en ajustes

createdAt         number
updatedAt         number
```

Índices:
- `by_user_date`
- `by_user_status`
- `by_user_type`
- `by_user_account`
- `by_user_category`

Search index: `description` filtrado por `userId`

Nota: se podrán registrar otros índices eventualmente de ser necesario

---

### `tags`

Etiquetas globales y reutilizables del usuario.

```text
userId        id("users")
name          string
parentId?     id("tags")
color?        string
isArchived    boolean
createdAt     number
updatedAt     number
```

Índices: `by_user`, `by_user_name`, `by_user_parent`

Regla: `name` único por usuario.

---

### `transactionTags`

Relación N a N entre movimientos y tags.

```text
userId          id("users")
transactionId   id("transactions")
tagId           id("tags")
createdAt       number
```

Índices: `by_transaction`, `by_tag`, `by_user_transaction`

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
- no usa `categoryId`
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

Aggregates por tag require un tratamiento más complejo todavía no definido.

---

## Lo que ve el usuario

La UI sigue siendo simple:

- `Cuentas`
- `Categorías`
- `Movimientos`
- `Tags`

El usuario crea movimientos claros y explícitos. El sistema mantiene saldos,
reportes, filtros y conversiones sin exponer complejidad innecesaria.