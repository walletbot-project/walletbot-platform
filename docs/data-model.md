# WalletBot — Modelo de Datos

## Filosofía central

Toda operación financiera tiene dos caras: cuando pagás en el super, sale plata de tu cuenta y entra en la categoría "Comida". Modelar ambas caras explícitamente —en vez de guardar solo "gasté X en Y"— da consistencia matemática, hace los balances siempre correctos y habilita transferencias y multi-moneda sin casos especiales.

La unidad mínima del modelo es el **posting**: un cambio de monto en una cuenta. Cada transacción agrupa dos o más **postings** cuya suma es siempre cero.

---

## Plan de cuentas

Todas las cuentas —las del banco, el efectivo, las tarjetas y también las categorías— viven en la misma jerarquía con cinco tipos raíz:

| Tipo | Qué representa | Ejemplos |
|---|---|---|
| `asset` | Lo que tenés | Efectivo, cuenta bancaria, inversiones |
| `liability` | Lo que debés | Tarjeta de crédito, préstamos |
| `equity` | Patrimonio neto | Saldo de apertura |
| `income` | Fuentes de dinero | Sueldo |
| `expense` | Destinos de dinero | Comida, transporte, entretenimiento |

Las **cuentas** que ve el usuario son hojas de `asset` o `liability`.
Las **categorías** son hojas de `income` o `expense`.

Internamente son la misma tabla. La jerarquía se modela con `parentId`, lo que permite subcategorías (`Expenses:Comida:Supermercado`) sin tablas adicionales.

---

## Ejemplos de registros

Los IDs son ilustrativos. Cada ejemplo muestra los registros exactos que se crean en la base de datos.

---

**Gasto — "Starbucks, $5.50 en efectivo"**

```js
// accounts (preexistentes)
{ _id: "acc_efectivo",  name: "Efectivo",  type: "asset",   parentId: undefined,    currency: "ARS", ... }
{ _id: "acc_cafe_root", name: "Comida",    type: "expense", parentId: undefined,    ... }
{ _id: "acc_cafe",      name: "Cafe",      type: "expense", parentId: "acc_cafe_root", ... }

// transactions
{ _id: "txn_1", userId: "usr_1", date: 1745712000000, description: "Starbucks",
  status: "cleared", tags: [], ... }

// postings
{ _id: "pst_1", transactionId: "txn_1", userId: "usr_1", accountId: "acc_cafe",     amount:  550, currency: "ARS" }
{ _id: "pst_2", transactionId: "txn_1", userId: "usr_1", accountId: "acc_efectivo", amount: -550, currency: "ARS" }
//                                                                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
//                                                                                   pst_1 + pst_2 = 0  ✓
```

---

**Ingreso — "Sueldo de abril"**

```js
// accounts (preexistentes)
{ _id: "acc_bbva",   name: "BBVA",   type: "asset",  parentId: undefined, currency: "ARS", ... }
{ _id: "acc_sueldo", name: "Sueldo", type: "income", parentId: "acc_trabajo", ... }

// transactions
{ _id: "txn_2", userId: "usr_1", date: 1746057600000, description: "Sueldo abril",
  status: "cleared", tags: ["trabajo"], ... }

// postings
{ _id: "pst_3", transactionId: "txn_2", userId: "usr_1", accountId: "acc_bbva",   amount:  200000, currency: "ARS" }
{ _id: "pst_4", transactionId: "txn_2", userId: "usr_1", accountId: "acc_sueldo", amount: -200000, currency: "ARS" }
```

---

**Transferencia — "Pase $500 a Galicia" (sin caso especial)**

```js
// accounts (preexistentes)
{ _id: "acc_bbva",    name: "BBVA",    type: "asset", parentId: undefined, currency: "ARS", ... }
{ _id: "acc_galicia", name: "Galicia", type: "asset", parentId: undefined, currency: "ARS", ... }

// transactions
{ _id: "txn_3", userId: "usr_1", date: 1745280000000, description: "Pase a ahorro",
  status: "cleared", tags: [], ... }

// postings
{ _id: "pst_5", transactionId: "txn_3", userId: "usr_1", accountId: "acc_galicia", amount:  50000, currency: "ARS" }
{ _id: "pst_6", transactionId: "txn_3", userId: "usr_1", accountId: "acc_bbva",    amount: -50000, currency: "ARS" }
```

---

**Saldo inicial — "Tengo $200 en efectivo al arrancar"**

```js
// accounts
{ _id: "acc_efectivo",        name: "Efectivo",        type: "asset",  parentId: undefined, currency: "ARS", ... }
{ _id: "acc_opening_balance", name: "Opening Balance", type: "equity", parentId: undefined, isDefault: true, ... }

// transactions
{ _id: "txn_4", userId: "usr_1", date: 1735689600000, description: "Opening Balance",
  status: "cleared", tags: [], ... }

// postings
{ _id: "pst_7", transactionId: "txn_4", userId: "usr_1", accountId: "acc_efectivo",        amount:  20000, currency: "ARS" }
{ _id: "pst_8", transactionId: "txn_4", userId: "usr_1", accountId: "acc_opening_balance", amount: -20000, currency: "ARS" }
```

---

**Multi-moneda — "Compré USD 100 pagando $100.000 ARS"**

```js
// accounts (preexistentes)
{ _id: "acc_usd", name: "Billetera USD", type: "asset", parentId: undefined, currency: "USD", ... }
{ _id: "acc_ars", name: "Efectivo ARS",  type: "asset", parentId: undefined, currency: "ARS", ... }

// transactions
{ _id: "txn_5", userId: "usr_1", date: 1744243200000, description: "Compra USD",
  status: "cleared", tags: [], ... }

// postings
{ _id: "pst_9",  transactionId: "txn_5", userId: "usr_1", accountId: "acc_usd",
  amount: 10000, currency: "USD", costAmount: 1000000, costCurrency: "ARS" }
  //                                                    ^^^^^^^^^^^^^^^^^^^^^^^^
  //                                                    tipo de cambio implícito: 100 ARS/USD
{ _id: "pst_10", transactionId: "txn_5", userId: "usr_1", accountId: "acc_ars",
  amount: -1000000, currency: "ARS" }
```

---

## Convención de signo

- `+` significa que entra plata a esa cuenta
- `-` significa que sale plata de esa cuenta

**Invariante**: la suma de los montos de todos los apuntes de una transacción es siempre `0`.

---

## Tablas Convex

### `accounts`

Cuentas del usuario y categorías, unificadas en una jerarquía.

```
userId        id("users")
name          string               — nombre corto: "BBVA", "Supermercado"
parentId?     id("accounts")       — para jerarquía
type          "asset" | "liability" | "equity" | "income" | "expense"
currency?     string               — moneda por defecto de esta cuenta
note?         string
isArchived    boolean
isDefault     boolean              — true = pre-cargada al registrarse
sortOrder?    number
createdAt     number
updatedAt     number
```

Índices: `by_user`, `by_user_type`, `by_user_parent`

---

### `transactions`

El encabezado de cada operación. No tiene monto propio: los montos viven en los apuntes.

```
userId        id("users")
date          number               — fecha del evento (no de creación)
description   string               — "Starbucks", "Sueldo abril"
note?         string
status        "pending" | "cleared"   — pendiente vs. confirmada/conciliada
tags          string[]             — etiquetas libres
createdAt     number
updatedAt     number
```

Índices: `by_user_date`, `by_user_status`
Search index: `description` (filtrado por `userId`)

---

### `postings`

Un apunte por cada lado de la transacción. Cada transacción tiene al menos dos.

```
transactionId   id("transactions")
userId          id("users")          — denormalizado para auth y queries
accountId       id("accounts")
amount          number               — entero en centavos, positivo = entra, negativo = sale
currency        string               — código ISO 4217: "ARS", "USD"
costAmount?     number               — base de costo para multi-moneda
costCurrency?   string
note?           string               — nota a nivel de apunte
createdAt       number
```

Índices: `by_transaction`, `by_user_account`, `by_account_currency`

---

## Consultas que habilita este modelo

Los siguientes ejemplos usan pseudocódigo SQL para ilustrar la expresividad del modelo. En Convex se implementan con índices, joins en memoria y el Aggregate component.

---

**Net worth — patrimonio neto total**

```sql
SELECT SUM(p.amount)
FROM postings p
JOIN accounts a ON p.accountId = a._id
WHERE p.userId = 'usr_1'
  AND a.type IN ('asset', 'liability')
  AND p.currency = 'ARS'
```

Funciona porque assets y liabilities son simplemente cuentas con un tipo. Los créditos (tarjetas, préstamos) ya tienen amounts negativos en sus postings, así que restan solos.

---

**Gastos de una categoría y todas sus hijas (recursivo)**

```sql
WITH RECURSIVE subtree AS (
  -- nodo raíz
  SELECT _id FROM accounts WHERE _id = 'acc_comida'
  UNION ALL
  -- hijos recursivos
  SELECT a._id FROM accounts a
  JOIN subtree s ON a.parentId = s._id
)
SELECT SUM(p.amount) AS total
FROM postings p
WHERE p.accountId IN (SELECT _id FROM subtree)
  AND p.userId = 'usr_1'
```

"Cuánto gasté en Comida" incluye automáticamente Comida:Cafe, Comida:Supermercado, Comida:Delivery, etc., sin lógica especial. Agregar una subcategoría nueva no rompe ninguna query existente.

---

**Gastos del mes por categoría raíz (tipo dashboard)**

```sql
WITH RECURSIVE subtree AS (
  SELECT _id, _id AS root_id
  FROM accounts
  WHERE parentId IS NULL AND type = 'expense' AND userId = 'usr_1'
  UNION ALL
  SELECT a._id, s.root_id FROM accounts a
  JOIN subtree s ON a.parentId = s._id
)
SELECT root.name, SUM(p.amount) AS total
FROM postings p
JOIN subtree s      ON p.accountId = s._id
JOIN accounts root  ON s.root_id   = root._id
JOIN transactions t ON p.transactionId = t._id
WHERE p.userId = 'usr_1'
  AND p.currency = 'ARS'
  AND t.date BETWEEN :inicio AND :fin
GROUP BY root._id, root.name
ORDER BY total DESC
```

Resultado: `[{ name: "Comida", total: 45000 }, { name: "Transporte", total: 18000 }, ...]`

---

**Todos los movimientos de una cuenta específica**

```sql
SELECT t.date, t.description, p.amount, p.currency
FROM transactions t
JOIN postings p ON t._id = p.transactionId
WHERE p.accountId = 'acc_bbva'
  AND p.userId = 'usr_1'
ORDER BY t.date DESC
```

Una transferencia aparece acá con su amount negativo (salió de BBVA), y la cuenta destino la ve con amount positivo. El mismo registro, dos perspectivas.

---

**Ingresos vs. gastos de un período (P&L)**

```sql
SELECT a.type, SUM(p.amount) AS total
FROM postings p
JOIN accounts a    ON p.accountId    = a._id
JOIN transactions t ON p.transactionId = t._id
WHERE p.userId  = 'usr_1'
  AND a.type   IN ('income', 'expense')
  AND p.currency = 'ARS'
  AND t.date BETWEEN :inicio AND :fin
GROUP BY a.type
```

Resultado: `[{ type: "expense", total: 80000 }, { type: "income", total: 200000 }]`
Diferencia = ahorro del período. No hace falta ningún campo calculado en las tablas.

---

**Saldo consolidado multi-moneda (convertido a ARS)**

```sql
SELECT
  SUM(
    CASE p.currency
      WHEN 'ARS' THEN p.amount
      WHEN 'USD' THEN p.amount * :tipo_de_cambio_usd
    END
  ) AS total_ars
FROM postings p
JOIN accounts a ON p.accountId = a._id
WHERE p.userId = 'usr_1'
  AND a.type IN ('asset', 'liability')
```

El tipo de cambio se inyecta en el momento de la query (puede venir de una API externa), no se guarda en los postings. Los postings siempre almacenan el valor original en su moneda.

---

## Balance de cuentas

El balance de una cuenta en una moneda es simplemente:

```
SUM(amount) WHERE accountId = X AND currency = Y
```

Para no recalcular esto en cada query, se usa el **Convex Aggregate component** con una clave compuesta `(accountId, currency)`. El aggregate se actualiza en cada mutación que crea, edita o elimina postings.

---

## Lo que no cambia para el usuario

La UI puede seguir exponiendo "Cuentas" y "Categorías" como conceptos separados: son filtros sobre la misma tabla `accounts` por `type`. El usuario nunca interactúa con "apuntes" directamente; ve transacciones con descripción, monto, cuenta y categoría.

El agente de voz también encaja: "gasté 500 en el super con efectivo" se traduce en un `transaction` + dos `postings`, sin lógica especial por tipo de operación.

---

## Decisiones pendientes

1. **¿Multi-moneda desde Etapa 1?** El modelo lo soporta nativamente, pero la UI puede ignorar `costAmount`/`costCurrency` hasta Etapa 2.
2. **¿Aggregates desde el inicio?** Recomendado sí, para no tener que migrar con datos cuando la tabla de postings crezca.
3. **¿Tags con clave-valor o solo strings?** El modelo actual usa strings simples (`["viaje", "trabajo"]`). Se puede extender a `key:value` si surge la necesidad.
