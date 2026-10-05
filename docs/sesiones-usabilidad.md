# Sesiones de usabilidad

Borrador, 2026-10-05.

Guion para las sesiones con personas reales. Le damos nuestro celular con la
app abierta, le leemos una consigna por escenario y miramos cómo la resuelve.
Al final hacemos el cuestionario SUS y una entrevista corta.

## Objetivos

Todos se evalúan de forma cualitativa. No hay umbrales numéricos de éxito.

1. Usabilidad. ¿La persona se mueve sola por la app? ¿Dónde se traba? El
   escenario 0 mide la primera impresión y la curva de aprendizaje: por dónde
   intenta cargar y si cada gasto le cuesta menos que el anterior. En todos los
   escenarios anotamos las trabas y cada pista que damos.
2. Utilidad. Qué funcionalidades le sirven, cuáles ignora y qué cambiaría.
3. Tedio de carga. ¿Cargar con el asistente le resulta menos pesado que cargar
   a mano o que lo que hace hoy?
4. Comprensión del asistente. ¿El asistente registró lo que la persona quiso
   decir? ¿La persona revisa lo que cargó el asistente y corrige lo que está
   mal?

También registramos:

- Si usó el asistente. Es lo que más nos importa, más que el canal. Igual
  anotamos si fue por texto, nota de voz o modo en vivo. Nunca se lo sugerimos.
- Cómo registra gastos e ingresos hoy, como línea base para medir conversión
  en otro momento.

### Fuera de alcance

- El costo de IA por sesión.
- Fallas catastróficas y pérdida de datos. Si pasan, se anotan, pero no hay
  tareas para provocarlas.
- Login y onboarding. Todos los escenarios arrancan con un usuario ya logueado.

## Participantes

Hasta 10 personas, según los voluntarios que consigamos.

| Grupo | Quiénes | Cantidad aproximada | Foco |
| --- | --- | --- | --- |
| 1 | Nunca usaron la app | 6 | Principal |
| 2 | Ya usan la app hace un tiempo | 4 | Comparación y entrevista |

Los dos grupos hacen los tres escenarios. Si la persona registra o no sus
gastos hoy se pregunta, pero no define el grupo.

## Formato

- Dispositivo: nuestro Android, con el celular y la app en español.
- Personas del equipo: idealmente dos, una conduce y otra acompaña tomando
  notas. Se puede hacer con una sola.
- Registro: audio de la sala con otro celular, más notas a mano en la planilla.
- Duración: libre. Esperamos entre 30 y 60 minutos, pero anotamos la hora de
  inicio y fin de cada escenario para calibrar las próximas rondas.
- Pensar en voz alta: no se pide. Si la persona habla sola, el acompañante
  anota las frases textuales.

### Qué tener en cuenta del modelo de la app

Sirve para interpretar lo que hace la persona, no para explicárselo.

- Cada cuenta tiene una sola moneda. Un resumen con pesos y dólares no entra en
  una sola cuenta.
- No existe un tipo de cuenta "tarjeta de crédito". Una tarjeta es una cuenta
  más.
- Los movimientos son gasto, ingreso, transferencia o ajuste de saldo. No hay
  un tipo "devolución".
- Gastos e ingresos pueden ser recurrentes, con frecuencia y fecha de fin
  opcional. Las cuotas se pueden modelar así. Las transferencias no pueden ser
  recurrentes.
- En la app el asistente se llama Gaston. En el equipo le decimos Gasti.

## Reglas para quien conduce

- Insistí en que lo resuelva sola. Si pregunta cómo se hace algo, devolvé la
  pregunta: "¿Cómo lo harías vos?", "¿Dónde lo buscarías?".
- Si está trabada y no hay forma de que avance, das una pista. La pista se
  anota siempre: qué dijiste, en qué escenario y en qué paso. Es de los datos
  más importantes de la sesión.
- No menciones el asistente ni dónde está, ni nombres botones o pantallas.
- No corrijas errores. Si carga algo mal, se anota y se sigue.
- Si dice "terminé", se acepta aunque falten cosas. Se anota qué faltó.
- Respuestas neutras. Nada de "muy bien" o "perfecto". Alcanza con "gracias,
  sigamos".
- Si está en una llamada con el asistente, no le hables, porque el asistente
  también te escucha.

## Guion

### 1. Bienvenida y consentimiento

Leer o decir con palabras propias:

> Gracias por venir. Vamos a probar una app, no a vos. No hay respuestas
> correctas ni incorrectas: si algo te cuesta, el problema es de la app y es
> justo lo que queremos encontrar.
>
> Te vamos a dar un celular y algunas consignas. Mientras las hacés no te
> podemos ayudar mucho, porque queremos ver cómo lo resolverías si estuvieras
> solo o sola. Al final contestamos todas tus preguntas.
>
> Todos los datos que vas a ver son inventados. No hace falta que uses nada
> tuyo.
>
> ¿Nos das permiso para grabar el audio de la sesión? Lo usamos solo nosotros
> para no perdernos nada de lo que digas, no lo compartimos. Podés pedir que
> paremos o cortar la sesión cuando quieras.

Anotar en la planilla si dio permiso. Sin permiso, la sesión sigue solo con
notas.

### 2. Preguntas de perfil

1. ¿Qué edad tenés?
2. Del 1 al 5, cuando instalás una app nueva, ¿qué tan fácil te resulta
   arreglártelas sin ayuda?
   - 1: casi siempre necesito que alguien me ayude.
   - 3: me arreglo con las apps que uso seguido.
   - 5: pruebo apps nuevas seguido y las entiendo rápido.
3. ¿Hoy anotás tus gastos o ingresos de alguna forma? ¿Cómo? ¿Cada cuánto?
4. ¿Usaste Wallet Bot antes? Solo grupo 2: ¿hace cuánto la usás, cada cuánto
   la abrís y qué es lo que más usás?

### 3. Presentación de la app

Decir, sin agregar nada sobre dónde está o cómo se usa el asistente:

> Wallet Bot es un anotador de gastos e ingresos pensado para que sea rápido y
> fácil. También tiene un asistente con inteligencia artificial.

### 4. Escenario 0: primera impresión

Estado de la app: usuario del escenario 0. Ver
[materiales](#escenario-0-lista-de-gastos).

Entregar la lista impresa y leer:

> Esta es tu app de gastos y ya tiene tus cuentas cargadas. Esta semana fuiste
> anotando tus gastos en un papel. Pasalos a la app.

Qué observar:

- Por dónde intenta cargar cada gasto: formulario manual, asistente por texto,
  nota de voz o modo en vivo. Si cambia de camino en el medio.
- La curva entre gastos: si el segundo y el tercero le llevan menos tiempo y
  menos dudas que el primero. El acompañante anota la hora de inicio de cada
  gasto.
- Si usa el asistente, si lo registrado coincide con la lista y si revisa lo
  que cargó.

Al terminar:

1. Del 1 al 5, ¿qué tan fácil o difícil te resultó? 1 es muy difícil y 5 es
   muy fácil.
2. ¿Qué cambiarías de lo que acabás de hacer?

### 5. Escenario 1: arrancar desde cero

Estado de la app: un usuario vacío nuevo, sin cuentas ni movimientos. Uno por
participante, porque el escenario lo llena.

Entregar el resumen y los tickets impresos y leer:

> Empezaste a usar Wallet Bot hoy. Te llegó el resumen de la tarjeta y tenés
> algunos tickets en la billetera. Cargá todo en la app y organizalo como te
> parezca mejor, como si fuera tu plata.

Qué observar:

- Qué cuentas crea, con qué nombre y moneda, y cómo resuelve los dólares del
  resumen.
- Cómo carga las cuotas: un gasto suelto por la cuota del mes, el total de la
  compra o un gasto recurrente.
- Cómo carga la devolución: como ingreso, borrando el gasto original, o no la
  carga.
- Si separa los tickets de los gastos de la tarjeta. El ticket de Farmacity ya
  está en el resumen: ¿lo carga dos veces? El de Coto es posterior al cierre:
  ¿lo asigna a la tarjeta?
- Si descubre categorías y tags, si crea propios y para qué los usa.
- Si usa el asistente, cómo, y si lo que registró coincide con el papel.

Al terminar, las mismas dos preguntas del escenario 0.

### 6. Escenario 2: sacar información

Estado de la app: usuario del escenario 2, con 6 meses de historial. Ver
[dataset](#escenario-2-dataset-y-respuestas-esperadas).

Leer:

> Ahora imaginá que venís usando la app hace 6 meses. Te vamos a hacer algunas
> preguntas sobre tu plata. Respondelas usando la app.

Entregar las tarjetas de una en una, en este orden:

1. ¿Cuánta plata tenés hoy en MercadoPago?
2. El mes pasado compraste algo en una ferretería. ¿Cuánto pagaste y con qué lo
   pagaste?
3. ¿Cuánto gastaste en supermercado el mes pasado?
4. ¿Gastaste más el mes pasado o el anterior? ¿Por qué creés que cambió?
5. ¿Cuánto gastaste en salidas con Martina en los últimos 3 meses?
6. Compraste una heladera en 6 cuotas. ¿Ya se pagó la cuarta cuota?
7. Con lo que ganás y gastás hoy, ¿en cuánto tiempo llegarías a tener 5.000 USD
   ahorrados?

Qué observar en cada consigna:

- Si la resuelve navegando y filtrando a mano o preguntándole al asistente. Es
  lo más importante de este escenario, sobre todo en las consignas 5, 6 y 7.
- La respuesta que da y si coincide con la
  [hoja de respuestas](#hoja-de-respuestas).
- Si usó el asistente: si entendió lo que le respondió y si lo verificó en la
  app.

Al terminar, las mismas dos preguntas del escenario 0.

### 7. Cuestionario SUS

Entregar el [cuestionario](#cuestionario-sus) impreso apenas termina el
escenario 2, antes de la entrevista, para que responda con la experiencia
fresca y sin la influencia de la charla.

### 8. Entrevista

Repreguntar sobre lo concreto que vimos. Si algo ya quedó respondido, se
saltea.

1. ¿Cómo te resultó la app?
2. Repasar las trabas anotadas, una por una. Por ejemplo: "Vi que te costó
   encontrar dónde cargar la cuota, ¿me contás qué estabas pensando?".
3. Si usó el asistente: ¿por qué lo elegiste? ¿Te entendió? ¿Entendiste lo que
   te respondió? ¿Por qué elegiste escribirle, mandarle un audio o llamarlo?
   Si no lo usó: ¿lo viste? ¿Por qué no lo usaste?
4. Comparado con cómo registrás tus gastos hoy, o con no registrarlos, ¿cómo te
   resultó? ¿Te pareció más o menos trabajo?
5. ¿Qué cambiarías?
6. ¿Qué te gustó o te resultó útil?
7. ¿Usarías la app? ¿Por qué sí o por qué no?
8. Solo grupo 2: desde que usás la app, ¿cambió algo en cómo manejás tu plata?
9. ¿Algún otro comentario?

Evitar preguntas que se contestan con sí o no y empujan la respuesta, como
"¿te gustó la app?", "¿te resultó fácil?" o "¿te pareció útil?".

### 9. Cierre

Agradecer, contestar las preguntas que haya guardado y cortar la grabación.

## Materiales

### Escenario 0: lista de gastos

La app tiene tres cuentas en pesos, sin movimientos más allá del saldo inicial:

| Cuenta | Saldo inicial |
| --- | --- |
| Efectivo | $ 45.000 |
| MercadoPago | $ 380.000 |
| Tarjeta de crédito | -$ 250.000 |

Categorías cargadas: Supermercado, Comida, Transporte, Salidas, Servicios,
Salud, Ropa y Hogar. Sin tags.

Para imprimir. Las fechas son relativas para que la lista sirva cualquier día:

> Gastos de la semana
>
> 1. Verdulería, hoy, $ 8.500, efectivo
> 2. Taxi, hace 3 días, $ 12.000, efectivo
> 3. Café con amigos, ayer, $ 9.800, MercadoPago
> 4. Factura de luz, hace 5 días, $ 38.400, MercadoPago
> 5. Farmacia, hace 2 días, $ 21.300, tarjeta
> 6. Zapatillas, hoy, $ 120.000 en 3 cuotas de $ 40.000, tarjeta
> 7. Pagué el resumen de la tarjeta desde MercadoPago, ayer, $ 250.000

Para quien observa, qué categoría corresponde y qué prueba cada línea:

| # | Categoría esperada | Qué prueba |
| --- | --- | --- |
| 1 | Supermercado | Caso base |
| 2 | Transporte | Fecha distinta a hoy |
| 3 | Salidas | Otra cuenta |
| 4 | Servicios | Otra cuenta y otra fecha |
| 5 | Salud | Tarjeta |
| 6 | Ropa | Cuotas |
| 7 | Ninguna | Transferencia entre cuentas |

### Escenario 1: resumen y tickets

Para imprimir. El banco es inventado.

> Banco Ejemplo, Visa terminada en 4821
>
> Período: 25/08/2026 al 24/09/2026. Cierre: 24/09/2026. Vencimiento:
> 06/10/2026.
>
> | Fecha | Detalle | Cuota | Pesos | Dólares |
> | --- | --- | --- | --- | --- |
> | 27/08 | COTO SUC 125 | | 64.320,00 | |
> | 02/09 | YPF FULL PALERMO | | 45.000,00 | |
> | 05/09 | AMAZON MKTPLACE | | | 42,50 |
> | 08/09 | MERCADOLIBRE*TIENDA | | 22.900,00 | |
> | 10/09 | FARMACITY 089 | | 18.750,00 | |
> | 14/09 | FRAVEGA | 03/06 | 85.000,00 | |
> | 15/09 | ZARA ALTO PALERMO | 02/03 | 30.000,00 | |
> | 16/09 | NETFLIX.COM | | | 12,99 |
> | 18/09 | DEV. MERCADOLIBRE*TIENDA | | -22.900,00 | |
> | 20/09 | LA PAROLACCIA | | 52.600,00 | |
> | 22/09 | UBER *TRIP | | 9.870,00 | |
>
> Saldo actual: $ 305.540,00 y U$S 55,49. Pago mínimo: $ 45.000,00.

> Ticket 1. Verdulería La Huerta, 26/09/2026. Pago: efectivo.
>
> | Producto | Importe |
> | --- | --- |
> | Tomate 1 kg | 2.400 |
> | Papa 2 kg | 2.100 |
> | Banana 1 kg | 1.950 |
> | Lechuga | 1.400 |
> | Total | 7.850 |

> Ticket 2. Farmacity 089, 10/09/2026. Pago: Visa terminada en 4821.
>
> | Producto | Importe |
> | --- | --- |
> | Ibuprofeno 600 x20 | 9.350 |
> | Protector solar | 9.400 |
> | Total | 18.750 |

> Ticket 3. Coto Suc 125, 28/09/2026. Pago: Visa terminada en 4821.
>
> | Producto | Importe |
> | --- | --- |
> | Leche x2 | 3.600 |
> | Pan lactal | 2.900 |
> | Fideos x3 | 4.200 |
> | Aceite 1,5 L | 6.800 |
> | Detergente | 3.150 |
> | Carne picada 1 kg | 9.800 |
> | Queso | 10.780 |
> | Total | 41.230 |

Para quien observa, qué prueba cada caso:

| Caso | Qué prueba |
| --- | --- |
| Amazon y Netflix en dólares | Modelo de cuentas: cuenta aparte en USD, conversión a pesos o nada |
| Frávega 03/06 y Zara 02/03 | Cuotas: gasto suelto, total de la compra o recurrente |
| Devolución de MercadoLibre | Cómo representa un reintegro |
| Ticket de Farmacity | Ya está en el resumen. Si lo carga dos veces |
| Ticket de Coto | Pagado con la tarjeta después del cierre. Si lo asigna a la tarjeta |
| Ticket de la verdulería | Pagado en efectivo. Si crea una cuenta aparte |

### Escenario 2: dataset y respuestas esperadas

Las fechas son relativas al día de la sesión, que llamamos S. M0 es el mes
calendario actual, M-1 el mes pasado y así hacia atrás. El historial cubre de
M-5 a S, más los movimientos futuros que generan los recurrentes.

Cuentas:

| Cuenta | Moneda |
| --- | --- |
| Efectivo | ARS |
| MercadoPago | ARS |
| Galicia | ARS |
| Visa | ARS |
| Ahorro USD | USD |

Categorías: Supermercado, Comida afuera, Salidas, Transporte, Servicios,
Alquiler, Salud, Ropa, Suscripciones, Hogar, Regalos y Sueldo.

Tags: Martina, Facu, Vacaciones y Trabajo.

Recurrentes, todos con primera ocurrencia en M-5 salvo la heladera:

| Nombre | Tipo | Cuenta | Frecuencia | Monto | Categoría | Fin |
| --- | --- | --- | --- | --- | --- | --- |
| Sueldo | Ingreso | Galicia | Mensual, día 1 | $ 2.000.000 | Sueldo | Sin fin |
| Alquiler | Gasto | Galicia | Mensual, día 5 | $ 650.000 | Alquiler | Sin fin |
| Gimnasio | Gasto | MercadoPago | Mensual, día 10 | $ 45.000 | Suscripciones | Sin fin |
| Netflix | Gasto | Visa | Mensual, día 15 | $ 12.000 | Suscripciones | Sin fin |
| Heladera | Gasto | Visa | Mensual | $ 150.000 | Hogar | 6 cuotas |

La cuota 4 de la heladera cae en S + 5 días. Las cuotas 1 a 3 caen 3, 2 y 1
meses antes de esa fecha, y la 5 y la 6 después.

Ahorro: una transferencia por mes de Galicia a Ahorro USD, el día 2, de
$ 300.000 a USD 200, con cotización 1.500. Van una por una porque las
transferencias no pueden ser recurrentes.

Movimientos que sostienen las respuestas:

| Para la consigna | Fecha | Nombre | Monto | Cuenta | Categoría | Tag |
| --- | --- | --- | --- | --- | --- | --- |
| 2 | M-1, día 12 | Ferretería El Tornillo | $ 23.450 | Efectivo | Hogar | |
| 3 | M-1, día 2 | Coto | $ 85.400 | Visa | Supermercado | |
| 3 | M-1, día 7 | Día | $ 62.150 | MercadoPago | Supermercado | |
| 3 | M-1, día 13 | Coto | $ 98.700 | Visa | Supermercado | |
| 3 | M-1, día 18 | Verdulería | $ 41.300 | Efectivo | Supermercado | |
| 3 | M-1, día 23 | Carrefour | $ 73.950 | Visa | Supermercado | |
| 3 | M-1, día 28 | Día | $ 50.800 | MercadoPago | Supermercado | |
| 4 | M-1, día 20 | Dentista | $ 180.000 | Visa | Salud | |
| 4 | Cada mes de M-5 a M-1, día 8 | Farmacia | $ 12.000 | Efectivo | Salud | |
| 5 | S - 80 días | Cine | $ 32.000 | MercadoPago | Salidas | Martina |
| 5 | S - 62 días | Bar | $ 45.500 | Visa | Salidas | Martina |
| 5 | S - 41 días | Pizzería | $ 28.000 | Efectivo | Salidas | Martina |
| 5 | S - 20 días | Recital | $ 51.000 | Visa | Salidas | Martina |
| 5 | S - 6 días | Cena | $ 30.000 | MercadoPago | Salidas | Martina |
| 5, distractor | S - 130 días | Salida | $ 35.000 | Visa | Salidas | Martina |
| 5, distractor | S - 35 días | Regalo de cumpleaños | $ 40.000 | MercadoPago | Regalos | Martina |
| 5, distractor | S - 70 días | Bar | $ 27.000 | Efectivo | Salidas | Facu |
| 5, distractor | S - 45 días | Asado | $ 38.000 | MercadoPago | Salidas | Facu |
| 5, distractor | S - 15 días | Bowling | $ 22.500 | Visa | Salidas | Facu |

Relleno: entre 150 y 250 movimientos más en Comida afuera, Transporte,
Servicios, Ropa, Salidas sin tag y Supermercado fuera de M-1. Reglas para que
no rompa las respuestas:

- Gastos totales por mes entre $ 1.600.000 y $ 1.800.000, contando los
  recurrentes. M-2 cerca de $ 1.610.000 y M-1 cerca de $ 1.780.000.
- Fuera de Salud, cada categoría varía poco entre M-2 y M-1.
- Ninguna otra ferretería en todo el período.
- En M-1, Supermercado tiene solo los 6 movimientos de la tabla.
- Salud tiene solo los movimientos de la tabla.
- El tag Martina está solo en los movimientos de la tabla.
- El saldo de MercadoPago el día S da $ 87.320 y el de Ahorro USD da USD 2.600.
  Se ajustan con el saldo inicial de cada cuenta.

#### Hoja de respuestas

Al preparar el dataset, completar la última columna con lo que muestra la app.
Si no coincide con el diseño, manda lo que muestra la app.

| # | Respuesta esperada | Errores probables | Valor en la app |
| --- | --- | --- | --- |
| 1 | $ 87.320 | Mirar el saldo de otra cuenta o el proyectado con movimientos futuros | |
| 2 | $ 23.450, en efectivo, día 12 del mes pasado | | |
| 3 | $ 412.300 en 6 compras | Sumar el mes actual o los últimos 30 días | |
| 4 | Más el mes pasado, unos $ 170.000, sobre todo por el dentista en Salud | Comparar el mes actual, que está incompleto | |
| 5 | $ 186.500 en 5 salidas | $ 226.500 si suma el regalo, $ 221.500 si suma la salida de hace 4 meses, o sumar todas las salidas | |
| 6 | No. Se pagaron 3, la cuarta vence en S + 5 días | Contar los movimientos futuros como pagados | |
| 7 | Unos 12 meses: faltan USD 2.400 y ahorra unos USD 200 por mes. Aceptar entre 10 y 14 | Si el asistente usa una cotización real en vez de 1.500, el número cambia. Importa el método y si entiende la respuesta | |

## Planilla de observación

Una por participante. Copiar e imprimir.

| Dato | Valor |
| --- | --- |
| ID de participante | |
| Grupo | 1 nuevo / 2 usuario |
| Fecha | |
| Conduce | |
| Acompaña | |
| Permiso de grabación | Sí / No |
| Versión de la app | |
| Edad | |
| Habilidad con la tecnología, 1 a 5 | |
| Cómo registra hoy | |
| Uso previo de la app | |

Escenario 0. Inicio: ____ Fin: ____

| Gasto | Hora de inicio | Camino | Dudas | Pista | Quedó bien | Notas |
| --- | --- | --- | --- | --- | --- | --- |
| 1 Verdulería | | | | | | |
| 2 Taxi | | | | | | |
| 3 Café | | | | | | |
| 4 Luz | | | | | | |
| 5 Farmacia | | | | | | |
| 6 Zapatillas | | | | | | |
| 7 Pago resumen | | | | | | |

Camino: M formulario manual, T asistente por texto, A nota de voz, V modo en
vivo. Dudas: ninguna, pocas o muchas.

Escenario 1. Inicio: ____ Fin: ____

| Caso | Qué hizo | Camino | Pista | Notas |
| --- | --- | --- | --- | --- |
| Cuentas creadas, nombre y moneda | | | | |
| Dólares | | | | |
| Cuotas | | | | |
| Devolución | | | | |
| Ticket Farmacity, duplicado | | | | |
| Ticket Coto, después del cierre | | | | |
| Ticket verdulería, efectivo | | | | |
| Categorías y tags | | | | |

Escenario 2. Inicio: ____ Fin: ____

| # | Método | Respuesta que dio | ¿Coincide? | Pista | Notas |
| --- | --- | --- | --- | --- | --- |
| 1 Saldo MercadoPago | | | | | |
| 2 Ferretería | | | | | |
| 3 Supermercado | | | | | |
| 4 Comparar meses | | | | | |
| 5 Salidas con Martina | | | | | |
| 6 Cuarta cuota | | | | | |
| 7 5.000 USD | | | | | |

Método: N navegación y filtros, T asistente por texto, A nota de voz, V modo
en vivo. Puede ser más de uno.

Asistente, completar si lo usó en cualquier escenario:

| Pregunta | Respuesta |
| --- | --- |
| ¿En qué escenarios lo usó? | |
| ¿Cómo lo encontró? | |
| Canales que usó: texto, nota de voz, modo en vivo | |
| ¿Registró o respondió lo que la persona quiso decir? | |
| ¿Revisó lo que cargó el asistente? | |
| ¿Corrigió errores del asistente? ¿Cómo? | |

Cierre:

| Dato | Valor |
| --- | --- |
| Dificultad escenario 0, 1 a 5 | |
| Dificultad escenario 1, 1 a 5 | |
| Dificultad escenario 2, 1 a 5 | |
| Puntaje SUS | |
| Trabas principales | |
| Pistas dadas | |
| Frases textuales | |
| Fallas o pérdida de datos, si pasó | |

## Cuestionario SUS

Para imprimir. Cada afirmación se responde del 1 al 5, donde 1 es "totalmente
en desacuerdo" y 5 es "totalmente de acuerdo".

| # | Afirmación | 1 | 2 | 3 | 4 | 5 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Creo que me gustaría usar esta app con frecuencia. | | | | | |
| 2 | La app me pareció innecesariamente compleja. | | | | | |
| 3 | Me pareció que la app era fácil de usar. | | | | | |
| 4 | Creo que necesitaría ayuda de alguien con conocimientos técnicos para poder usar esta app. | | | | | |
| 5 | Las distintas funciones de la app me parecieron bien integradas. | | | | | |
| 6 | Me pareció que la app tenía demasiadas inconsistencias. | | | | | |
| 7 | Imagino que la mayoría de las personas aprendería a usar esta app muy rápido. | | | | | |
| 8 | La app me resultó muy engorrosa de usar. | | | | | |
| 9 | Me sentí con mucha confianza usando la app. | | | | | |
| 10 | Tuve que aprender muchas cosas antes de poder arrancar con la app. | | | | | |

### Cálculo del puntaje

1. Afirmaciones impares (1, 3, 5, 7 y 9): respuesta menos 1.
2. Afirmaciones pares (2, 4, 6, 8 y 10): 5 menos la respuesta.
3. Sumar los diez valores y multiplicar por 2,5. Da un puntaje de 0 a 100.

El promedio de referencia de SUS ronda 68. Con 10 personas o menos, el
puntaje sirve para comparar grupos y rondas, no como medida absoluta.

### Versión original en inglés, como referencia

1. I think that I would like to use this system frequently.
2. I found the system unnecessarily complex.
3. I thought the system was easy to use.
4. I think that I would need the support of a technical person to be able to
   use this system.
5. I found the various functions in this system were well integrated.
6. I thought there was too much inconsistency in this system.
7. I would imagine that most people would learn to use this system very
   quickly.
8. I found the system very cumbersome to use.
9. I felt very confident using the system.
10. I needed to learn a lot of things before I could get going with this
    system.

## Checklist de preparación

Antes de la ronda:

- [ ] Imprimir, por participante: lista del escenario 0, resumen y tickets del
      escenario 1, tarjetas del escenario 2, cuestionario SUS y planilla de
      observación.
- [ ] Preparar el usuario del escenario 2 y completar la hoja de respuestas con
      lo que muestra la app.
- [ ] Confirmar con qué arranca un usuario nuevo. En el código no encontramos
      categorías por defecto, así que debería arrancar sin cuentas, categorías
      ni tags.
- [ ] Probar el asistente por texto, nota de voz y modo en vivo con un usuario
      aparte, para no dejar conversaciones en los usuarios de la sesión.
- [ ] Decidir si el permiso de micrófono se concede antes o se deja que
      aparezca el pedido de Android. Si se concede antes, ese paso no se
      observa.
- [ ] Definir quién conduce y quién acompaña en cada sesión.

Antes de cada sesión:

- [ ] Usuario del escenario 0 limpio: tres cuentas con su saldo inicial, las
      categorías y ningún movimiento ni conversación con el asistente.
- [ ] Usuario vacío nuevo para el escenario 1.
- [ ] Usuario del escenario 2 sin cambios de la sesión anterior. Si alguien
      editó o cargó algo, volver a prepararlo.
- [ ] Usar usuarios con sesión iniciada, no cuentas locales. Las locales tienen
      un límite diario de uso del asistente más bajo.
- [ ] Android en español, batería cargada, no molestar activado y sin
      notificaciones de otras apps.
- [ ] Conexión estable.
- [ ] Grabador de audio probado.
- [ ] Planilla, lápiz y materiales impresos a mano.
