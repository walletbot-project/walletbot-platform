# Diseño de movimientos recurrentes

Documento vivo con las decisiones de diseño de la funcionalidad de
**movimientos recurrentes** (ingresos y gastos recurrentes). Registra el estado
actual, las decisiones tomadas y lo que queda pendiente.

> Ticket: `wal-153` · Rama: `wal-153-demo-gastos-recurrentes`
> Última actualización: 2026-08-07

---

## 1. Estado actual (qué está implementado)


### Native (`apps/native/lib/screens/transaction_form.dart`)

- Switch de recurrencia visible en **ingreso** ("Ingreso recurrente") y en
  **gasto** ("Gasto recurrente"). No aparece en transferencia.
- Al activarlo se muestra un panel (`_RecurrencePanel`) que pregunta:
  - **Frecuencia**: Diario / Semanal / Mensual / Anual / Cada X días (por
    defecto Mensual).
  - **Cantidad de días**: solo cuando la frecuencia es "Cada X días" — campo
    numérico (mínimo 1, por defecto 15).
  - **Fecha de fin (opcional)**: elegible y limpiable; por defecto "Sin fecha de
    fin". El date picker no permite fechas anteriores a la fecha del movimiento.
- Estado local: `_isRecurring`, `_recurrenceFrequency`,
  `_recurrenceDayInterval`, `_recurrenceEndDate`. Se resetea al cambiar el tipo
  de movimiento.
- Claves l10n nuevas (es/en): `recurringIncome`, `frequency`, `recurrenceDaily`,
  `recurrenceWeekly`, `recurrenceMonthly`, `recurrenceYearly`,
  `recurrenceEndDateOptional`, `recurrenceNoEndDate`, `recurrenceCustomDays`,
  `recurrenceRepeatEvery`, `recurrenceDaysUnit`.

### Web (`apps/web/src/pages/add-manual.tsx`)

- Componente `RecurrenceControl` con paridad total: mismo switch (agregado vía
  shadcn CLI, `components/ui/switch.tsx`), mismas frecuencias (incluida "Cada X
  días" con cantidad configurable) y misma fecha de fin opcional.
- Estado local: `isRecurring`, `recurrenceFrequency`, `recurrenceDayInterval`,
  `recurrenceEndDate`.



---

## 2. Decisiones tomadas

### 2.1. Frecuencias soportadas

`daily` · `weekly` · `monthly` · `yearly` · `customDays`. Por defecto
**monthly**.

- **`customDays` ("Cada X días")**: el usuario elige la cantidad de días (mínimo
  1, por defecto 15). Cada ocurrencia es `ancla + k × N días` (aritmética de días
  simple), así que no tiene el caso borde de fin de mes de la regla 2.3 — solo
  hay que respetar la zona horaria / DST al sumar días de calendario.
- No hay intervalo configurable para las otras frecuencias ("cada N semanas",
  "cada N meses") por ahora — si aparece la necesidad, `customDays` es el patrón
  a generalizar.

### 2.2. Fecha de fin

Opcional. Si no se define, la recurrencia es indefinida (hasta que el usuario la
cancele). No puede ser anterior a la fecha del movimiento ancla.

### 2.3. Semántica del "último día del mes" → **Opción A (inferencia automática)**

Este es el caso borde central de la frecuencia mensual (y aplica igual a la
anual). Ejemplo: creo un movimiento el **31 de enero** y elijo **Mensual**.

Se decidió la **Opción A**: inferir el comportamiento automáticamente, sin
preguntarle nada al usuario. Reglas:

1. **Cada ocurrencia se calcula desde la fecha ancla original**, nunca desde la
   ocurrencia anterior. Esto evita la "deriva": que un febrero recortado a 28
   arrastre el error y deje marzo en 28 en vez de 31.

2. **Si la fecha ancla es el último día de su mes, la recurrencia se trata como
   "último día del mes"**. Para los meses más cortos se usa el último día
   disponible.

   Resultado esperado para un ancla el 31 de enero, mensual:

   ```
   31 ene → 28/29 feb → 31 mar → 30 abr → 31 may → 30 jun → …
   ```

   (siempre el último día del mes)

3. Si la fecha ancla **no** es el último día, se usa el mismo número de día y,
   en meses que no lo tienen, se recorta al último día de ese mes — pero la
   siguiente ocurrencia vuelve a calcularse desde el ancla (regla 1), así no hay
   deriva.

   Ejemplo ancla el 30 de enero, mensual:

   ```
   30 ene → 28/29 feb → 30 mar → 30 abr → …
   ```

**Por qué Opción A y no preguntar:** menor fricción para la demo. La diferencia
entre "día 30" y "último día" solo importa para anclas de día 31 (o 29/30 en
febrero), y la inferencia cubre el caso más intuitivo. Queda para más adelante
una eventual **Opción B** (preguntar explícitamente cuando hay ambigüedad) si
los usuarios lo piden.

### 2.4. Alcance de plataformas

Paridad mobile ↔ web desde el inicio. Toda decisión de semántica debe valer para
ambas.

---

## 3. Pendiente / próximos pasos

La implementación real del motor es un **cambio coordinado backend + schema
nativo** (ver `CLAUDE.md` § Client–server contract y `docs/schema/README.md`).

1. **Modelo de datos** (backend Convex + schema nativo SQLite/Drift):
   - Definir cómo se guarda una "regla de recurrencia" (frecuencia, ancla, fecha
     de fin, flag de "último día del mes").
   - Relación entre la regla y los movimientos generados.
   - Coordinar bump de `schemaVersion` y `minSupportedVersion` si toca el
     formato de sync.

2. **Motor de próximas ocurrencias** (idealmente en `packages/shared` para
   compartir entre web y native, y evitar divergencias):
   - Función pura `nextOccurrence(anchor, frequency, index)` que respete las
     reglas 2.3.
   - Tests del caso borde de fin de mes, años bisiestos (29 feb) y DST (ya hay
     precedente de manejo de DST en `parseTransactionDate`).

3. **Materialización**: decidir si los movimientos se generan por adelantado o
   bajo demanda; si es un proceso durable, considerar Convex Workflows.

4. **Persistir los flags de UI** actuales hacia las mutations/repos una vez
   exista el modelo.

5. **Casos de error / estados**: qué pasa al editar o borrar la regla, o un
   movimiento generado; loading/empty/error states.

6. Revisar `docs/riesgos.md` cuando se implemente el motor.

---

## 4. Casos borde a cubrir en tests (cuando se implemente)

- Ancla el 31 → meses de 30, 28 y 29 días.
- Ancla el 29/30 de febrero en año bisiesto vs no bisiesto.
- Frecuencia anual sobre el 29 de febrero.
- Fecha de fin que cae justo en/entre ocurrencias.
- Zona horaria y DST (no debe correr el día de calendario).
