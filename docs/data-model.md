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

## Asientos de ejemplo

**Gasto:**
```
2026-04-20 Starbucks
    Expenses:Comida:Cafe    +550  ARS
    Assets:Efectivo         -550  ARS
```

**Ingreso:**
```
2026-04-30 Sueldo
    Assets:Banco:BBVA       +200000  ARS
    Income:Trabajo:Sueldo   -200000  ARS
```

**Transferencia** (sin caso especial, igual que cualquier transacción):
```
2026-04-15 Pase a ahorro
    Assets:Banco:Galicia    +50000  ARS
    Assets:Banco:BBVA       -50000  ARS
```

**Saldo inicial** (al crear una cuenta con balance preexistente):
```
2026-01-01 Opening Balance
    Assets:Efectivo            +20000  ARS
    Equity:Opening Balance     -20000  ARS
```

**Multi-moneda** (compra de dólares):
```
2026-04-10 Compra USD
    Assets:Billetera:USD    +10000  USD  @@ 1000000  ARS
    Assets:Efectivo:ARS     -1000000  ARS
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
