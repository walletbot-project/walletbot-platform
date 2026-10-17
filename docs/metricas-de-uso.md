## Recolección y análisis de métricas de uso

### Cómo funciona la recolección

Wallet Bot registra eventos de uso desde dos lugares: las apps (nativa y web) y el propio backend. Cada evento se guarda un instante en un búfer temporal del backend y se envía enseguida a Grafana Cloud. Los tableros leen de Grafana. Convex solo guarda los eventos hasta que se exportan.

Fijamos criterios para que los números sean confiables:

- **Un evento es una medición.** Cada alta, log-in, movimiento o sesión genera exactamente un registro con su hora. Contar registros equivale a contar eventos, sin estimaciones ni decimales.
- **Los números respetan el rango elegido.** Si el equipo cambia el selector de tiempo del tablero, el conteo cambia con él.
- **No se guardan datos personales ni de cardinalidad abierta.** No exportamos identificadores de usuario ni el contenido de lo que el usuario carga. El consumo por usuario usa un identificador anonimizado y estable, solo para los 20 con mayor consumo. Las etiquetas permitidas están declaradas en un catálogo, y el sistema rechaza cualquier valor que no esté en él.
- **Medimos en el momento real del evento.** Por ejemplo, una sesión de voz se cuenta cuando se abre la sesión. No se cuenta cuando se pide el token, porque eso también pasa en cada reconexión y al precargar la pantalla de voz. Contar ahí habría inflado el número.

### Qué medimos

| Qué | Para qué |
|---|---|
| Cuentas creadas, por método de autenticación | Saber cuánta gente se suma y por qué vía se registra |
| Cuentas totales registradas | Ver el tamaño de la base de usuarios |
| Log-ins, por método de autenticación y plataforma | Ver cuánta gente vuelve y desde dónde (nativa o web) |
| Movimientos creados, por tipo | Saber cuánto se usa la app para lo que importa: registrar gastos e ingresos |
| Movimientos creados por el agente frente a los cargados a mano | Medir cuánto del uso viene de la propuesta central: cargar un gasto hablando |
| Sesiones de voz abiertas, nuevas o retomadas | Saber cuánto se usa la voz y cuántas conversaciones se continúan |
| Costo del asistente por sesión, por modelo y por modo (texto, voz o híbrido) | Controlar cuánto cuesta cada modelo y modo |
| Consumo mensual por tipo de cuenta (local o remota) | Detectar usuarios con consumo atípico |

Las sesiones de voz hoy solo las emite la app nativa.

### Qué hicimos

- Instrumentamos los eventos de negocio: altas de cuenta, log-ins, movimientos y sesiones del asistente. Cada uno lleva solo las etiquetas necesarias: método de autenticación, plataforma, tipo de movimiento y origen (formulario o agente).
- Medimos el costo del asistente y lo separamos por modelo y por modo. Así podemos comparar los modelos de lenguaje que probamos. También medimos el consumo mensual por tipo de cuenta, con un resumen que se actualiza cada pocas horas.
- Armamos el tablero principal en Grafana, con filtros por entorno (producción o desarrollo) y por modelo. Está versionado en el repositorio (`docs/dashboards/`), así que cualquiera del equipo puede importarlo. Para evitar errores al editarlo, hay un validador automático.

### Cómo está organizado el tablero

| Sección | Qué responde |
|---|---|
| Cuentas de usuario | ¿Cuántas cuentas se crean y cuántas personas inician sesión, y por qué método y plataforma? |
| Sesiones del agente | ¿Cuántas sesiones de voz se abren, y cuántas son conversaciones retomadas? |
| Uso de IA | ¿Cuánto cuesta el asistente, por modelo y modo, y qué cuentas consumen más? |
| Creación de movimientos | ¿Cuántos movimientos se cargan, de qué tipo y qué parte crea el agente? |
| Salud operativa | ¿Fallan las sincronizaciones o las herramientas del asistente, y por qué? |
| Latencia (p50/p95/p99) | ¿Qué tan rápido responden la sincronización y el asistente? |

Las dos últimas secciones se explican en el apartado siguiente.

### Cómo leer estos números

Estas métricas dan una señal de tendencia. No son contabilidad. El costo del asistente es una estimación, no lo que factura el proveedor. Además, el envío de métricas todavía no exige autenticación, un riesgo que aceptamos a propósito (R-011 y R-023 en `docs/riesgos.md`). Por eso no las usamos para reportes externos. Sirven para decidir qué mejorar y para comparar períodos entre sí.

### Qué aporta al producto

Sin estas métricas no había forma de saber si la gente usa el asistente por voz. Tampoco sabíamos cuánto cuesta cada modelo ni qué parte de los movimientos carga el agente. Ahora el equipo puede responder esas preguntas con datos, en un solo tablero.
