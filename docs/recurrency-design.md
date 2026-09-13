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
   - Incrementar `schemaVersion` y conservar el contrato de clientes publicados;
     subir `minSupportedVersion` sólo si no existe una ruta compatible.

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

#### Dónde cae el corte: fin del bloque de 20 minutos

`date <= ahora` es la lectura literal y es la que queremos, pero un valor que
cambia a cada milisegundo no sirve como argumento de una query de Convex: el
caché está indexado por argumentos, así que cada llamada erraría el caché. La
solución es **cuantizar**: el corte es el final del bloque de 20 minutos en
curso.

Veinte minutos es fino como para que un movimiento entre en Actividad cuando
efectivamente ocurre, y grueso como para que el argumento cambie tres veces por
hora en vez de constantemente. Dentro de un bloque, todos los clientes mandan
el mismo número y comparten la respuesta cacheada.

**Redondea hacia arriba, y eso es load-bearing.** El corte es una cota superior
exclusiva, así que redondear hacia abajo pondría un movimiento cargado *recién
ahora* por encima del corte: el gasto que el usuario acaba de anotar
desaparecería de Actividad hasta 20 minutos. Hacia arriba se conserva la
dirección de la regla anterior —errar hacia "ya ocurrió"— con grano más fino. El
costo es que algo que vence en los próximos minutos cuenta como hecho un rato
antes, que nadie puede notar.

La versión anterior cortaba en **fin del día local**, para que un gasto cargado
a la mañana con hora 20:00 no desapareciera hasta las 20:00. El redondeo hacia
arriba conserva esa propiedad en lo que importaba (nada que acabás de cargar se
esconde) y a cambio deja de contar todo el día por adelantado.

Un efecto secundario que no habíamos previsto: los bloques se cortan **desde el
epoch**, no desde un día local, así que el corte pasó a ser independiente de la
zona horaria. Un mediodía en Buenos Aires y un mediodía en Madrid son el mismo
instante y mandan el mismo argumento, cosa que un límite de medianoche local no
podía hacer.

- TS: `pastCutoffMs()` en `packages/shared/src/occurrence.ts`.
- Dart: `pastCutoffMs()` en `apps/native/lib/data/occurrence.dart`.

#### En nativo el corte lo evalúa SQL, no Dart

Drift **hornea** los valores en la sentencia que construye, y re-ejecuta *esa*
sentencia cuando cambian las tablas. Con el corte como constante de Dart, una
pantalla que sostiene el stream se queda con el corte del momento en que se
construyó la query — ni una escritura lo refresca. Con un límite diario eso era
una desactualización de una vez por día que nadie llegaba a ver; a 20 minutos
sería el caso común.

Así que el predicado es SQL (`pastCutoffSql`): cada re-ejecución de la query
—incluida la que dispara una escritura— vuelve a preguntar el reloj. Con
`strftime('%s','now')` y no `unixepoch()`, que necesita SQLite 3.38 y acá hay
que aguantar lo que traiga el dispositivo.

Queda un caso sin cubrir: una pantalla nativa abierta sin que se escriba nada
no se actualiza sola al cruzar un bloque. En web sí, porque
`useOccurrenceCutoff` rearma un timer en cada límite. Hacerlo en nativo pedía un
notifier de app entera y ocho sitios replumbados; se puede agregar si molesta.

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

**El lote aplica sólo al caso abierto.** Con fecha de fin el usuario ya dijo
dónde termina la serie, así que se crean **todas** sus ocurrencias: "mensual
hasta 2036" son 120 movimientos, no los primeros 48. `occurrenceCount` sólo
consulta el horizonte cuando `endDate` es nulo.

La cuenta se resuelve por **búsqueda binaria** sobre la proyección, no
recorriendo ocurrencia por ocurrencia: las fechas crecen estrictamente con el
índice, y "diario hasta 2050" son unas 8.700 ocurrencias que nada debería
caminar de a una sólo para contarlas. Hay un test en los dos lados que compara
la búsqueda binaria contra el recorrido ingenuo, que quedó como oráculo.

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

Drift pasa de `schemaVersion` 4 a 5 y `pubspec` a 0.4.0+7, pero
`minSupportedVersion` **permanece en 0.3.0**: el despliegue no obliga a actualizar.
La capacidad de recurrencias se negocia por versión, separada del soporte de sync.

- Un cliente 0.3.x recibe los movimientos ocurridos como movimientos normales,
  sin reglas ni campos de recurrencia. Los futuros se proyectan como tombstones
  **sólo en la respuesta**: también desaparece un movimiento que se reprograma
  hacia el futuro, sin borrar el dato canónico.
- La proyección ocurre después de calcular la página y su cursor, por lo que
  una página sin filas visibles sigue avanzando. Los joins futuros se ocultan
  también; los contadores y saldos del binario viejo no necesitan código nuevo.
- Cada escritura mantiene `legacyPendingDate`, un campo exclusivo del servidor
  e indexado. Un cron por minuto publica las ocurrencias vencidas con nuevos
  `seq` y sus joins, por lotes; no cambia `updatedAt`, para respetar ediciones
  offline. La cola sobrevive retrasos y reinicios. La migración
  `backfillLegacyOccurrences` encola las filas futuras que ya existían.
- Un push sin `recurrenceId`/`recurrenceIndex` conserva los valores canónicos.
  Una edición o eliminación antigua afecta sólo ese movimiento.
- Al actualizar v4→v5 se reinicia el cursor de sync, sin borrar datos ni writes
  pendientes. El replay trae reglas y futuros; si hay una edición offline,
  se conservan sus campos y se hidrata sólo el vínculo con la serie que v4 no
  podía almacenar.
- `asOfMs` es opcional en las APIs v1 existentes. Para clientes web anteriores,
  el fallback lee un reloj persistido que el cron invalida al cambiar de bloque.
- `recurrence` y `scope` en las tools requieren flag **y** versión nativa 0.4.0,
  igual que las tools nuevas; un ejecutor viejo nunca los recibe.

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

`materializeBatch` es idempotente por construcción: lee qué ocurrencias ya
existen en la ventana que le toca y llena sólo los huecos. Un paso del workflow
reintentado después de una falla parcial completa el lote en vez de duplicarlo
— y acá un duplicado es plata que el usuario nunca gastó.

El rango `[from, to)` es **argumento**, nunca se re-deriva adentro. Eso es lo
que hace segura la ampliación del paso 2B: "añadir 48 más" se resuelve a una
ventana concreta en el momento del click, así que un reintento llena esa misma
ventana en vez de leer una serie que ya creció y estirarla otra vez.

La presencia se chequea sobre `by_user_recurrence_index`, un rango
`[from, to)` que contiene exactamente las ocurrencias del lote: trabajo acotado
por lote, en lugar de releer la serie entera (que crece con cada ampliación).
Por **índice** y no por fecha, a propósito — hay dos índices sobre la serie y no
son redundantes: en cuanto el paso 4 permita editar la fecha de una sola
ocurrencia, el orden por índice y el orden por fecha dejan de coincidir, y el
que dice qué lugares están ocupados es el índice.

La regla y su ocurrencia 0 se escriben juntas a propósito: las ocurrencias
copian sus campos de la ancla, así que una regla sin ancla no tiene forma y el
materializador se niega a correr.

### 5.3. Paso 2B — ampliar una serie abierta

En el detalle de un movimiento futuro hay un botón "añadir N más", con el mismo
N con el que se creó la regla (`recurrenceHorizon`).

#### Continúa desde la última ocurrencia que existe, no desde la abierta

Es la única invariante que importa acá. Abrir el movimiento de septiembre de una
serie ya materializada hasta noviembre y pedir 48 más tiene que significar
diciembre en adelante: cualquier otra lectura o choca con los movimientos que ya
están o deja un hueco.

Por eso la operación se dirige **a la regla**, no a la ocurrencia: el índice del
movimiento abierto no es ni un argumento. `from` sale del máximo `recurrenceIndex`
de la serie, una sola lectura por índice descendente.

Y lo que las ocurrencias nuevas *copian* es la ocurrencia 0, no la última: el
ancla es la forma de la regla. Copiar la última dejaría que un movimiento
editado redefina en silencio toda la serie futura, que es justamente la
decisión que "sólo este" vs "este y los futuros" existe para hacer explícita.

#### Sólo para reglas sin fecha de fin

Una regla con fecha de fin ya está completa: el usuario puso ese límite a
propósito y pasarlo sería editar la regla, no ampliarla (eso es el paso 4). El
botón no aparece.

#### No hace falta persistir "cuántas pidió"

La tentación era guardar un contador en `recurrences`. No hace falta y sería una
segunda fuente de verdad: con el rango como argumento del workflow, "cuántas
hay" sigue siendo una propiedad de las filas y nada puede contradecirlas.

#### Los dos caminos, otra vez

- **Web**: `v1/recurrences/mutations:addOccurrences` resuelve `from`/`to` y
  arranca el mismo workflow del paso 2.
- **Nativo**: `TransactionRepository.addOccurrences` las escribe localmente, en
  una transacción de drift, copiando los campos de la última ocurrencia.

Devuelven cuántas crearon, y el snackbar/toast reporta **ese** número, no el que
ofrecía el botón: si la regla cambió abajo, la escritura es la que dice la
verdad. Cero significa que la regla dejó de ser ampliable mientras preguntábamos
(borrada, o con fecha de fin puesta en otro dispositivo) y se reporta como error,
no como un éxito vacío.

### 5.4. Paso 3 — cuánto abarca la serie, en el detalle

El detalle ahora abre con una fila de **frecuencia**, y a su derecha, en tono
apagado, hasta dónde llega la serie. La fila no existía: el detalle mostraba
fecha, hora, cuenta, categoría y descripción, ninguna de las cuales dice que
este movimiento es parte de algo.

Qué se muestra depende de si la regla tiene fecha de fin, porque son dos
preguntas distintas:

- **Con fecha de fin** → `X/N`. El total se conoce, así que el dato útil es la
  posición: "este es el 3.º de 12".
- **Sin fecha de fin** → `hasta 15/01/2030`. No hay un total del que ser
  fracción — la regla es abierta y el lote es una decisión de implementación,
  no una promesa —, así que dice hasta dónde llegan los movimientos que
  existen. Que es exactamente lo que amplía el botón del paso 2B.

#### Las dos cifras se derivan, y cuestan una lectura

`N` y "hasta cuándo" salen de la **última ocurrencia**, en un solo documento:
los índices corren contiguos desde 0, así que el índice más alto *es* la
cantidad. No hay que contar filas (lo que además violaría la regla de no hacer
conteos por colección), y no hay nada nuevo persistido: las filas siguen siendo
la única verdad sobre hasta dónde llegó una serie.

`X` es `recurrenceIndex + 1` del movimiento abierto, que ya venía en la fila.

#### La frecuencia se lee del mismo catálogo con el que se escribe

Las etiquetas ("Diario", "Mensual") son las que ya usa el formulario
(`addManual.recurrence*` en web, las mismas claves en los ARB), no un juego
nuevo: una regla se describe igual donde se crea y donde se lee. La única que
difiere es `customDays`, porque el formulario muestra el chip "Cada X días" con
el intervalo en su propio campo y acá el intervalo es parte de la descripción
(`recurrenceEveryNDays`).

#### Un hueco que este paso hizo visible, y se cerró

Mientras se escribía este paso apareció que `occurrenceCount` topeaba en el
horizonte **también** con fecha de fin: una regla "mensual hasta 2036"
materializaba 48 ocurrencias en vez de las 120 pedidas, y como el botón de
ampliar sólo aparece para reglas sin fecha de fin, no había forma de
completarla. El `X/N` de este paso lo dejaba a la vista sin remedio.

Está arreglado en §5.2: el lote es sólo para reglas abiertas. Con eso el gate
del botón vuelve a ser exacto — una regla con fecha de fin **sí** está completa
— y `X/N` es el total de verdad.

El costo es que el usuario ahora manda: "diario hasta 2050" son unas 8.700
transacciones reales. En web las crea el workflow en lotes de 50 (unos 174
pasos); en nativo es un solo `db.transaction` con esas 8.700 inserciones, que en
un teléfono se va a notar. Es lo pedido, y el corte de ocurrencia las mantiene
fuera de Actividad, del saldo y de los contadores, pero es la razón por la que
R-049 sigue pidiendo un tope antes de sacar el feature flag.

### 5.5. La misma fila en el detalle de Actividad

Un movimiento que ya ocurrió sigue siendo una ocurrencia de su regla, y "el 3.º
de 12" es igual de útil mirando atrás que mirando adelante. Así que el detalle
de Actividad muestra la misma fila de frecuencia que el de movimientos futuros,
con el mismo `X/N` o el mismo "hasta ...".

Salió barato porque no había nada nuevo que calcular:

- **Costo de lectura**: dos filas por índice (la regla y su última ocurrencia),
  y sólo cuando el movimiento tiene `recurrenceId`. Es la misma consulta del
  paso 3, ya acotada por índice y sin conteos.
- **Web**: un `useQuery` más en `TransactionDetail`.
- **Nativo**: el detalle de Actividad carga con lecturas puntuales, no con
  streams, así que se sumó un `seriesOf` — la versión one-shot de
  `watchSeries`, compartiendo las mismas consultas y el mismo constructor. No
  puede entrar en el `Future.wait` porque necesita la transacción primero, así
  que es un await encadenado.

Lo que hubo que mover para no duplicar: las etiquetas de cadencia y de alcance
vivían privadas en la pantalla de movimientos futuros. Ahora están en
`activity/helpers.ts` (web — la dirección de dependencia que ya existía:
future-movements ya importaba de activity) y en
`lib/components/recurrence_summary.dart` (nativo). Una regla se describe igual
en los tres lugares donde aparece: el formulario que la crea, el detalle futuro
y el detalle pasado.

`seriesReachLabel` pasó a recibir el índice de la ocurrencia en vez de la
transacción entera: era lo único que usaba, y así sirve a los dos detalles sin
acoplarlos al tipo de fila de cada lista.

### 5.6. Paso 4 — editar y eliminar, con alcance

El detalle de movimientos futuros ahora edita y elimina, y las dos operaciones
hacen la pregunta que una serie obliga a hacer: **este movimiento, o este y los
futuros**. No se escribe nada hasta que está contestada — el alcance no es un
default que el usuario pueda pasar por alto.

#### "Solo este movimiento" no necesitó nada nuevo

Una ocurrencia es una transacción ordinaria (§2.5), así que ese alcance usa las
mutations que ya existían: `v1/transactions/mutations:update` y `:archive` en
web, `TransactionRepository.update`/`delete` en nativo. La regla no se toca.

#### "Este y los futuros" va por lotes

Hasta 500 filas más sus entradas de agregado: el mismo problema que
materializar, así que la misma solución. `updateFutureBatch` y
`archiveFutureBatch` procesan 50 por vez y los workflows caminan los lotes. El
recorrido es por **índice** (`by_user_recurrence_index`), no por fecha: "los que
siguen" significa más adelante en la serie, y desde que se puede editar la
fecha de una sola ocurrencia los dos órdenes dejan de coincidir.

La ocurrencia abierta se escribe sincrónicamente y la cola sigue en lotes, así
que la pantalla que el usuario está mirando queda bien en el momento en que la
mutation vuelve.

#### Borrar la cola trunca la regla

La `endDate` de la regla es lo que leen el `X/N` y el botón de ampliar, así que
dejarla apuntando más allá de una cola que ya no existe haría que el detalle
describa una serie más larga que la de la pantalla. Se corta en la fecha de la
ocurrencia **anterior**. En el índice 0 no hay anterior, así que se archiva la
regla entera.

El orden importa: primero truncar, mientras la ocurrencia `index - 1` todavía
es la última en pie, y después borrar.

#### Cambiar la cadencia parte la regla en dos

No hay forma de expresar "de acá en adelante, semanal" con una sola regla: cada
ocurrencia se proyecta desde el ancla por índice (§2.3), así que cambiar la
frecuencia movería también las ocurrencias **anteriores** a esta. Lo que el
usuario quiere son dos reglas — la original terminando donde la cortó, y una
nueva empezando acá — y eso es lo que se escribe.

Sale compuesto de las dos operaciones que ya existían: se borra la cola vieja y
se crea una serie nueva en la fecha editada. La regla nueva hereda la
`endDate` de la vieja, porque el usuario movió la cadencia, no el final.

Lo mismo aplica a mover la **fecha** con alcance "este y los futuros": es un
re-anclaje, así que va por el mismo camino.

Y como la cadencia no se puede confinar a una ocurrencia, cuando el formulario
la cambió el diálogo deshabilita "solo este movimiento" y dice por qué
(`scopeOnlyThisUnavailable`) en lugar de aceptar la elección y descartar el
cambio en silencio.

Eso hace que "¿cambió la cadencia?" tenga que ser exacto. La primera versión en
web sembraba los campos de frecuencia desde la regla en el `useState` inicial,
que parece equivalente y no lo es: la query todavía está cargando en el primer
render, así que el fallback quedaba como cadencia "actual" y **cualquier**
guardado parecía un cambio de cadencia. Ahora los campos guardan sólo la
elección del usuario y se resuelven contra la regla al leerlos. El nativo tenía
el mismo error por el mismo motivo (la regla llega con el stream, no con el
movimiento) y se arregló igual.

#### El diálogo, igual en los dos lados

Orden de Material y el mismo en las dos plataformas: primero la salida
(`Cancelar`), después los dos alcances. Una elección destructiva sólo recolorea
su etiqueta.

#### Un movimiento suelto no tiene alcance que preguntar

La lista de movimientos futuros se llena por el corte de ocurrencia, que filtra
por fecha y no sabe nada de recurrencias (§5.1). Así que un movimiento suelto
con fecha futura cae ahí igual, sin regla — y editarlo o borrarlo no tiene dos
alcances posibles: las dos respuestas significan el mismo movimiento.

El diálogo ahora se saltea cuando el movimiento no tiene `recurrenceId`. Se
decide sobre la fila y no sobre la query de la regla, que en el primer render
todavía está cargando.

Y las operaciones **degradan** en vez de fallar: `deleteFuture`/`updateFuture`
sobre algo sin serie actúan sobre esa única fila. Antes el nativo devolvía 0 y
el llamador reportaba un borrado que nunca había pasado — un botón muerto que
además mentía. "Este y los que siguen", cuando no hay ninguno que siga,
significa este.

#### El formulario no reusa la forma del recibo

En modo lectura el detalle es un recibo: etiqueta a la izquierda, valor
alineado a la derecha. En modo edición pasa al layout apilado del demo
(wal-153): la etiqueta arriba en versalitas y el control abajo a todo el ancho.
Un slot alineado a la derecha funciona para texto y pelea con cualquier cosa en
la que se pueda escribir — un dropdown o un campo de texto exprimidos ahí se
ven mal.

En nativo el split va en **una** transacción de drift (anidan como savepoints):
uno que sólo llegara a borrar la cola vieja dejaría al usuario sin ninguna de
las dos series.

#### Un bug latente que este paso destapó

`writeTombstone` tenía la unión de tablas sincronizadas **repetida a mano**, y
había quedado atrás de `recurrences`. Nada lo notaba porque el push escribe los
tombstones directo a la tabla y hasta acá el backend nunca había necesitado
tombstonear una regla — recién al truncar una serie en el índice 0 hacía falta.
Ahora el tipo se deriva del schema (`Infer<typeof syncedTable>`), así que no
puede volver a divergir.

De paso se extrajo `archiveTransactionRow` a `convex/transactions/helpers.ts`:
borrar "este y los futuros" tiene que dejar cada ocurrencia exactamente como la
dejaría borrarla sola —los tombstones por join incluidos, que son
load-bearing porque el servidor no recibe cascada de un tombstone de
transacción— y con el cuerpo duplicado eso duraba hasta el primer cambio.

### 5.7. El `X/N` cuenta movimientos, no casilleros

Con 5 mensuales, borrar el 2/5 dejaba a los demás diciendo `3/5`, `4/5`, `5/5`
— cuando ya son cuatro movimientos y el tercero es el `2/4`.

La causa: `recurrenceIndex` estaba haciendo **dos trabajos** que coinciden sólo
mientras la serie no tenga agujeros.

1. Es la **clave de proyección**: `occurrenceDateMs(ancla, frecuencia, índice)`.
   El índice 3 *significa* "tres meses después del ancla".
2. Se estaba usando además como **posición a mostrar** (`X = índice + 1`,
   `N = índice_máximo + 1`).

El borrado es lógico (`isArchived`), así que la fila borrada conserva su
índice, el máximo no se mueve y el `N` sigue contando casilleros.

**Y el índice no se puede renumerar.** Es load-bearing en cuatro lugares: la
proyección de fechas, el relleno de huecos del materializador (que usa "el
índice 1 ya existe" justamente para **no** recrear lo borrado), el
`recurrenceIndex >= x` de "este y los futuros", y el `maxIndex + 1` del botón
de ampliar. Renumerar reviviría movimientos borrados.

Así que posición y total se cuentan sobre los **sobrevivientes**, aparte del
índice.

#### El costo, y por qué hay un tope

Contar sobrevivientes obliga a mirar `isArchived` fila por fila: no hay señal
libre que diga "esta serie tiene un agujero". Y `X/N` sólo se muestra para
reglas con fecha de fin, que el usuario acota — "diario hasta 2050" son 8.700
filas.

Así que la lectura está **capeada** en `SERIES_COUNT_CAP` (500, compartido
entre las dos plataformas para que caigan al fallback al mismo tamaño): se
leen `cap + 1` casilleros por índice descendente y se filtran los archivados en
memoria. Sin filtrar en la consulta a propósito — un `.take()` filtrado tendría
que caminar por todos los borrados que se cruce, y así el costo es exactamente
`cap + 1` documentos.

Pasado el tope no hay `X/N`: el detalle muestra "hasta \<fecha>", igual que una
regla abierta. Un `X/8700` nunca era el dato útil.

#### Lo que quedaría por hacer

Hacerlo exacto y sin tope es un agregado de Convex sobre `transactions`:
namespace `${userId}:${recurrenceId}`, `sortKey` el índice y
`sumValue: isArchived ? 0 : 1`. Sumar en vez de contar es lo que lo haría
barato de mantener: los archivados aportan 0, así que la disciplina sería
idéntica a la de los dos agregados que ya existen (`replace` al archivar, no
`delete`). `N` sería la suma del namespace y `X` la suma acotada a
`[0, mi índice]`, dos lecturas O(log n).

No está hecho porque cuesta más que el tope: hay **once** sitios de
mantenimiento (`transactions/helpers.ts`, `recurrences/internal.ts`,
`v1/recurrences/mutations.ts`, `v1/accounts/internal.ts`, `v1/sync/mutations.ts`
×3, `userDeletion/internal.ts`, el backfill), conviene encauzarlos todos por los
helpers antes de agregar un tercero, y sobre todo **requiere un backfill**: un
agregado sólo es correcto si toda fila existente entró en él, así que sería un
paso de deploy y no de merge.

### 5.8. Gastón

El agente operaba sobre la app anterior a esta branch. Los cuatro pasos le
dejaron tres agujeros de distinta gravedad, y uno de ellos era peligroso.

#### Lo que ya estaba bien

El corte de ocurrencia (§5.1) le llegó gratis. `buildTransactionQuery`
defaultea a `TxnOccurrence.occurred` y los ejecutores de web ya pasaban
`pastCutoffMs`, así que `listTransactions` y `summarizeTransactions` nunca
vieron movimientos futuros. Ese default es deliberado: toda pregunta existente
es sobre lo que pasó, y querer las filas programadas es el caso excepcional que
hay que pedir.

#### Lo que faltaba

1. **No podía ver el futuro.** Ninguna tool devuelve movimientos del otro lado
   del corte, así que "¿qué tengo por pagar la semana que viene?" no tenía
   respuesta posible. Nuevo `listUpcomingTransactions`.
2. **No podía crear una recurrencia.** "Cargá el alquiler todos los meses"
   habría creado un gasto suelto. `addExpense`/`addIncome` ahora aceptan
   `recurrence`, y el resultado reporta cuántas ocurrencias se crearon y hasta
   cuándo llegan — para que el modelo diga el número en vez de dar a entender
   "para siempre".
3. **Editar y borrar eran una trampa.** `deleteTransaction` borraba una fila.
   "Borrá el alquiler" habría borrado un mes y el usuario habría creído que la
   serie entera se fue. Este era el agujero grave, y el arreglo no es sólo un
   argumento: es la instrucción de **preguntar**.

#### Cómo se resolvió el alcance

`scope` va en las tools que ya existen, no en tools nuevas. Es a propósito: el
modelo ya alcanza `deleteTransaction` por reflejo, y si el alcance viviera en
una tool aparte podría borrar una ocurrencia sin considerar nunca la serie —
exactamente la trampa que hay que cerrar. Con el argumento donde ya está, la
decisión aparece en el lugar donde se toma, el default es el reversible
(`only-this`), y la descripción de la tool más la sección del prompt le dicen
que pregunte antes.

Dos refusals en vez de adivinar:

- Cambiar la cadencia con `only-this` se rechaza explicando por qué es
  imposible (las ocurrencias anteriores conservan su espaciado).
- Mover la fecha con `all-future` se rechaza indicando el camino: es un split,
  así que necesita `recurrence`; o `only-this` para mover sólo esta.

#### Los gates

- **Versión nativa 0.4.0** para las tres tools nuevas: los ejecutores necesitan
  el schema local v5 (la tabla `recurrences` y las columnas de ocurrencia), que
  es el bump coordinado de 0.4.0. Un binario 0.3.x no tiene dónde poner una
  regla, y el mint nunca debe declarar una tool que el cliente no puede
  ejecutar.
- **Feature flag `recurringExpense`** para `listRecurrences` y
  `addRecurrenceOccurrences`, el mismo que gatea la UI: con el flag apagado el
  usuario no tiene forma de ver ni administrar una regla, así que el agente no
  debe poder crear una.
- **`listUpcomingTransactions` NO está gateada.** Un movimiento suelto con
  fecha futura existe con el flag apagado, y es invisible en todo el resto de
  la app, así que el agente tiene que poder verlo de cualquier manera.
- El prompt sigue la misma regla que `MATH_GUIDE` y `FX_GUIDE`:
  `RECURRENCE_GUIDE` sólo entra si la sesión declaró las tools, así que nunca
  menciona algo que no se puede llamar.

#### La skill

`recurring-movements` entra al índice de skills. Ahí van las reglas que el
modelo necesita **antes** de explicar el feature: que las ocurrencias son
movimientos reales creados por adelantado, que "sin fecha de fin" es un lote y
no el infinito, que estar en la lista de futuros no implica ser recurrente, y
que la posición cuenta movimientos que existen y no pasos de cadencia desde el
inicio.

#### Un detalle de telemetría

`v1/recurrences/mutations:create` hardcodeaba `createdBy: 'form'`. Ahora toma el
argumento como las demás mutations de creación, porque desde este paso el
agente también crea recurrencias y el dashboard las habría contado todas como
cargas manuales.
