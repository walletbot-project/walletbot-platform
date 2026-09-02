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

### 2.3. Semántica del "último día del mes" → **inferencia automática**

Este es el caso borde central de la frecuencia mensual (y aplica igual a la
anual). Ejemplo: creo un movimiento el **31 de enero** y elijo **Mensual**.

Se decidió inferir el comportamiento automáticamente, sin
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

**Por qué no preguntar:** menor fricción para el usuario. La diferencia
entre "día 30" y "último día" solo importa para anclas de día 31 (o 29/30 en
febrero), y la inferencia cubre el caso más intuitivo. Queda para más adelante
una eventual preguntar explícitamente cuando hay ambigüedad si
los usuarios lo piden.

### 2.4. Alcance de plataformas

Paridad mobile ↔ web desde el inicio. Toda decisión de semántica debe valer para
ambas.

### 2.5. Los movimientos futuros NO se ven desde Actividad

**Norma:** los movimientos recurrentes que todavía no ocurrieron **no** deben
aparecer en la pantalla de **Actividad** ni ser encontrables desde sus filtros.
Solo se ven en la nueva vista **"Movimientos futuros"**.

- Actividad muestra únicamente movimientos que ya sucedieron (historial).
- Un movimiento recurrente "pasa" a Actividad recién cuando se materializa en su
  fecha; hasta entonces vive solo en Movimientos futuros.
- Acceso: botón **"Ver movimientos futuros"** en Inicio →
  - Web: ruta `/future-movements` (`apps/web/src/pages/future-movements.tsx`).
  - Native: `FutureMovementsScreen`
    (`apps/native/lib/screens/future_movements.dart`), abierta como ruta pushed
    desde una action card en Inicio.
- La vista replica el diseño de Actividad (mismas filas `TransactionRow`,
  agrupación por día), con un banner que aclara la separación.

**Estado actual:** ambas vistas usan **datos mock** — nada se persiste ni se
consulta al backend todavía. Cuando exista el motor (sección 3), la query de
Actividad debe filtrar `date <= now` (o `status`/materialización) y la de
Movimientos futuros `date > now`, de modo que la norma se cumpla server-side y no
solo en la UI.

### 2.6. Editar / eliminar un movimiento futuro → alcance obligatorio

Los movimientos futuros son **clickeables, editables y eliminables** desde la
vista de Movimientos futuros (mismo patrón que el detalle de Actividad: pantalla/
sheet de detalle con modo lectura ↔ edición inline).

**Norma:** antes de **guardar** una edición o **confirmar** un borrado, siempre
se pregunta el alcance (estilo Google Calendar para eventos recurrentes):

- **"Solo este movimiento"** (`onlyThis`) → la operación afecta únicamente esa
  ocurrencia. Semántica futura: se crea una *excepción* de la regla para esa
  fecha (editar) o se omite esa ocurrencia (borrar), dejando el resto de la
  serie intacta.
- **"Este y los futuros"** (`allFuture`) → la operación afecta esa ocurrencia y
  todas las siguientes. Semántica futura: se modifica/termina la *regla* de
  recurrencia desde esa fecha en adelante (sin tocar las ocurrencias ya pasadas
  en Actividad).

Implementación actual (mock):
- El mock materializa **varias ocurrencias por regla** (3 por ahora), cada una
  con un `ruleId` compartido, de modo que el alcance tiene un efecto **visible**:
  - `onlyThis` → afecta solo la ocurrencia tocada (por `id`).
  - `allFuture` → afecta esa ocurrencia y las **posteriores de la misma regla**
    (`ruleId` igual y `date` mayor a la ocurrencia original). En edición, la
    ocurrencia editada pasa a ser el **nuevo ancla** y las siguientes se
    **re-proyectan** desde ella según la (posiblemente nueva) frecuencia:
    - Mensual: mover del 17 al 18 → todas las siguientes al 18.
    - Semanal / "cada X días": se recalculan las próximas desde la nueva fecha.
    - También se puede **editar la frecuencia**; al cambiarla, las siguientes se
      regeneran con la nueva cadencia (`stepDate` / `_stepDate`).
    - El resto de los campos (monto, título, cuenta, categoría, descripción) se
      propaga a las siguientes.
    En borrado se eliminan esa y las siguientes.
- Web: `apps/web/src/pages/future-movements/details-sheet.tsx` — `Sheet`
  (detalle/edición) + `Dialog` de alcance con dos botones + Cancelar. La lógica
  de alcance vive en `index.tsx` (`handleSave`/`handleDelete`).
- Native: `apps/native/lib/screens/future_movements.dart` —
  `_FutureMovementDetailScreen` (AppBar con editar/guardar + eliminar) +
  `AlertDialog` de alcance. Devuelve el resultado por `Navigator.pop` y
  `_openDetail` aplica el alcance sobre la lista.
- La distinción semántica **real** (excepción de la regla vs. modificar/terminar
  la regla) queda para cuando exista el motor y la persistencia; el mock ya
  refleja el comportamiento observable esperado.

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

---

## 5. Implementación

Bitácora de las decisiones tomadas al construir la feature, paso por paso.
Cada sección corresponde a un commit.

### 5.1. Paso 1 — el corte de ocurrencia

**El problema.** Una regla recurrente materializa sus ocurrencias como
transacciones comunes con fecha futura. Eso es deliberado (§2.5: "los
movimientos que se crean son iguales a los de Actividad"), pero implica que
*toda* lectura que describa "qué pasó" tiene que detenerse antes de ellas: la
lista de Actividad, el saldo de una cuenta, el gasto de una categoría, el
contador de un tag, cada tile del dashboard. Si una sola se olvida, un gasto
programado para diciembre baja el saldo hoy.

#### Dónde cae el corte: fin del día local, no el instante

`date <= ahora` es la lectura literal, pero rompe algo que ya funcionaba: un
gasto cargado hoy a las 10:00 con hora confirmada 20:00 desaparecería de
Actividad y del saldo hasta las 20:00. El corte es entonces **el comienzo del
día siguiente en hora local**: todo lo fechado hoy ya ocurrió, sin importar la
hora.

- TS: `pastCutoffMs()` en `packages/shared/src/occurrence.ts`.
- Dart: `pastCutoffMs()` en `apps/native/lib/data/occurrence.dart`.

#### El corte viaja como argumento, no se lee del reloj del servidor

En el backend, `asOfMs` es un argumento **requerido** de toda query afectada.
Nunca `Date.now()` adentro del handler. Dos razones, ninguna estética:

1. El servidor no sabe qué día es *para este usuario*. "Fin de hoy" es una
   noción de hora local, y la medianoche UTC parte el día en el lugar
   equivocado para casi todo el mundo.
2. Una query de Convex se cachea contra sus argumentos y sus dependencias de
   datos — y el paso del tiempo no es ninguna de las dos. Una query que leyera
   el reloj le seguiría sirviendo una respuesta vieja a una suscripción
   abierta mucho después de que la fecha del movimiento pasara. Como
   argumento, el cliente decide cuándo la respuesta puede cambiar.

Hacerlo **requerido** fue a propósito: el compilador enumeró los 20 llamadores
en vez de dejar que alguno quedara silenciosamente sin acotar.

En web el valor sale de `useOccurrenceCutoff()`
(`apps/web/src/hooks/use-occurrence-cutoff.ts`), que además se re-arma para el
siguiente límite: una pestaña abierta cruzando la medianoche mueve sus
suscripciones sola. En nativo no viaja nada — el dispositivo es dueño del reloj
y de la base.

#### Cómo se aplica en cada capa

| Capa | Mecanismo |
|---|---|
| Saldo (backend) | Cota superior sobre los agregados, que ya ordenan por `date`. Sigue siendo O(log n) y no lee filas. |
| Listas y sumas por índice | El corte se pliega sobre el `dateTo` que la query ya tenía, así que viaja en el mismo rango de índice y no cuesta nada. |
| Filtros del dashboard | `occurredWindow()` sobre el `DateWindow`, dentro de `EvaluationContext`. Como `collectMatching` es la única puerta de las lecturas del dashboard, no se puede llamar sin corte. |
| `by_user_status` | Único índice sin `date`: es la sola rama que filtra en vez de acotar. |
| Contador de tags | El join no tiene fecha, así que hay que leer la transacción detrás de cada uno. Es la única lectura que se volvió más cara. |
| Nativo | `TxnOccurrence` en `buildTransactionQuery`, con default `occurred`. El default es la decisión: todo llamador existente pregunta por lo que pasó, así que el lado seguro es el que se obtiene sin pensarlo, y querer lo programado hay que pedirlo. |

#### Lo que deliberadamente NO se acotó

- **`balanceAroundTransaction`** (web y nativo) ya está anclado a la
  transacción objetivo, no a "ahora": suma sólo lo anterior a su fecha, así
  que las filas futuras nunca entran. No necesita corte.
- **El replay de `balance_adjustment`** (`sync_recompute.dart`) recorre en
  orden de fecha; las filas futuras quedan en la cola y ningún ajuste queda
  después de ellas salvo que el ajuste mismo sea futuro. Se deja como está.
- **El motor de sync** mueve filas enteras sin importar de qué lado del corte
  caen — para eso existe `TxnOccurrence.all`.

#### `createBalanceAdjustment` también toma el corte

Un ajuste de saldo dice "mi cuenta tiene X ahora mismo" y el backend deriva
`amount = balanceAfter − saldoActual`. Ese saldo tiene que ser el que el
usuario ve, así que se detiene en el corte: un movimiento programado para el
mes que viene no puede cambiar qué significa "ahora mismo".

#### Estado de la pantalla de movimientos futuros

Pasa a leer transacciones reales con fecha futura (`listUpcoming` en web,
`watchUpcoming` en nativo) en vez de los datos mock de la demo. Efecto
inmediato y deseable: un movimiento manual con fecha futura, que hoy ensuciaba
Actividad y el saldo, ahora aparece acá.

El detalle queda **de solo lectura en este paso**. Editar o eliminar una
ocurrencia tiene que decir si aplica a esta o a esta y las siguientes (§2.6), y
"las siguientes" necesita la regla de recurrencia que las generó, que todavía
no existe. Cablear los botones a algo que tocara una fila suelta sería peor
respuesta que no ofrecerlos; vuelven en el paso 4.

Por la misma razón la fila pierde la frecuencia en su descripción: sin regla no
hay frecuencia que mostrar. Vuelve en el paso 2, y el `X/N` del paso 3 con ella.

### 5.2. Paso 2 — la regla se persiste y materializa sus ocurrencias

#### "Sin fecha de fin" no puede significar "para siempre"

Las ocurrencias son transacciones comunes (§2.5), así que una regla sin límite
sería una cantidad ilimitada de filas. Cada frecuencia materializa un lote fijo
por adelantado, y el usuario lo amplía cuando quiere. Como eso es una decisión
del producto y no un detalle, el formulario **lo dice**: el placeholder pasa a
"Sin fecha de fin\*" y una nota al pie aclara cuántos movimientos se crean y
qué período cubren.

| Frecuencia | N | T |
|---|---|---|
| Diario | 500 | 500 días |
| Semanal | 100 | 23 meses (100 semanas) |
| Mensual | 48 | 4 años |
| Anual | 20 | 20 años |
| Cada X días | según X | N × X días, en meses o años |

Para "cada X días" el lote sale de la cadencia a la que X se parece, en bandas
semiabiertas hacia arriba: X < 7 usa el de diario, X < 30 el de semanal,
X < 365 el de mensual, y de ahí en adelante el de anual. El asterisco va sobre
el *placeholder*, no sobre la etiqueta: lo que la nota matiza es la **ausencia**
de fecha de fin.

La política vive en `packages/shared/src/recurrence.ts` y su espejo Dart
`apps/native/lib/data/recurrence.dart`, con tests equivalentes en ambos lados —
una serie creada en el teléfono tiene que caer en los mismos días que una
creada en la web.

#### La proyección se hace desde el ancla, siempre

`occurrenceDateMs` / `occurrenceDate` implementan §2.3 al pie: cada ocurrencia
se calcula desde la fecha ancla por índice, nunca desde la anterior, y un ancla
que cae en el último día de su mes se trata como "último día del mes". Los
tests cubren el ejemplo del doc (31 ene → 28 feb → 31 mar → 30 abr), el 29 de
febrero anual, y que un febrero recortado no arrastre marzo.

Toda la aritmética es sobre componentes de calendario locales, así que un
cambio de horario de verano mueve el instante pero nunca el día ni la hora de
reloj.

#### Esquema: una tabla de reglas, no campos denormalizados

`recurrences` guarda la regla una sola vez y cada ocurrencia la referencia por
`recurrenceId` (+ `recurrenceIndex`, su posición en la serie). El índice se
**almacena** en vez de derivarse de la fecha, para que editar una ocurrencia no
renumere el resto.

La regla guarda sólo lo que no se puede derivar de sus filas: cuántas hay es un
conteo, y hasta cuándo está cubierta es la fecha máxima. Guardar cualquiera de
las dos sería una segunda fuente de verdad capaz de contradecir a las filas
después de una edición.

Es un cambio de wire, así que es un bump coordinado, como pide CLAUDE.md:
drift `schemaVersion` 4 → 5 (tabla nueva + dos columnas nullable, sin backfill:
una transacción anterior a la recurrencia **es** un movimiento suelto),
`minSupportedVersion` 0.3.0 → 0.4.0 y `pubspec` 0.4.0+7. Un cliente pre-v5
falla cerrado en sync en vez de round-tripear una ocurrencia sin sus campos y
dejar que LWW le borre el vínculo con la serie.

#### Quién materializa: cada origen el suyo, exactamente una vez

- **Web** llama `v1/recurrences/mutations:create`, que escribe la regla y la
  ocurrencia 0 en una sola mutation, y arranca un workflow que crea el resto en
  lotes de 50. Una regla diaria son 500 inserts más sus updates de agregado:
  demasiado para una transacción sola.
- **Nativo** las escribe localmente, en la misma transacción de drift. No es
  una asimetría gratuita: un movimiento creado sin conexión tiene que existir
  sin conexión. Suben por push como cualquier fila.

El backend **no** regenera una serie que recibió por sync, así que los dos
caminos no pueden duplicarse.

`materializeBatch` es idempotente por construcción: lee qué índices ya existen
y llena sólo los huecos. Un paso del workflow reintentado después de una falla
parcial completa el lote en vez de duplicarlo — y acá un duplicado es plata que
el usuario nunca gastó.

La regla y su ocurrencia 0 se escriben juntas a propósito: las ocurrencias
copian sus campos de la ancla, así que una regla sin ancla no tiene forma y el
materializador se niega a correr.
