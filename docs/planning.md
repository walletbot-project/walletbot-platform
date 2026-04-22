# WalletBot — Planificación 3 Meses

## Visión general

WalletBot es una app para registrar y seguir gastos personales de forma simple. La propuesta central es poder hacerlo hablando, como si le contaras a alguien qué gastaste, sin complicarse con formularios.

La solución incluye:
- Asistente conversacional por voz en tiempo real (Gemini Live API)
- Interfaz visual simple para registro manual
- App móvil Flutter (producto principal) + app web
- Backend Convex con sincronización en tiempo real

---

## Etapa 1 — Fundaciones (Semanas 1–4)

Objetivo: infraestructura sólida, flujo end-to-end de transacciones manuales funcional.

### Epic 1: Infraestructura y Setup

- Como desarrollador, quiero tener un schema Convex con las tablas users, accounts, transactions, categories y tags definidas, para poder construir las features de la app sobre una base de datos estructurada.
  - Tal vez tengamos que hablar mas como queremos modelar los datos, si hacerlo como un ledger / libro diario, double-entry accounting.
- Como desarrollador, quiero tener helpers de autorización que verifiquen el ownership de los datos por usuario, para que ningún usuario pueda acceder a información ajena.
  - setear librería de auth
  - armar middleware para las funciones de Convex para checkear el usuario, si puede acceder a cierto recurso, etc
- Como desarrollador, quiero que cada PR pase validaciones automáticas de lint, typecheck y formato, para mantener la calidad del código sin esfuerzo manual.
- Como desarrollador quiere una estructura de páginas modular con ruteo. (react-router y el que sea en Flutter).

### Epic 2: Gestion de Usuarios

- Como usuario, quiero poder registrarme e iniciar sesión con Google o con email y contraseña, para acceder a mis datos de forma segura. (Mobile y webapp).
- Como usuario, deberia poder cambiar o reestablecer contraseña.
- Como usuario, deberia poder subir una foto de perfil.
- Como usuario, deberia poder ingresar a la cuenta usando biometria.
- Como usuario, deberia poder cambiar el email de mi cuenta.
- Como usuario, quiero poder eliminar mi usuario.

### Epic 3: Gestión de Cuentas
- Como usuario, quiero poder crear cuentas de distintos tipos (efectivo, banco, tarjeta), para reflejar cómo organizo mi dinero en la vida real.
- Como usuario, quiero tener la posibilidad de poner mi balance inicial al momento de crear una cuenta.
  - Deberia haber una pantalla donde te pregunte todas las cuentas que queres agregar, sus balances iniciales y poder subirlo todo de una en vez de cuenta por cuenta.
- Como usuario, quiero asignar una moneda por defecto, y de no ser especificada otra, que mis cuentas usen esa moneda.
- Como usuario, quiero ver el balance actualizado de cada cuenta, para saber cuánto dinero tengo disponible en cada una en todo momento.
- Como usuario, quiero editar o eliminar una cuenta existente, para mantener mi lista de cuentas organizada y actualizada.

### Epic 4: Registro Manual de Transacciones

- Como usuario, quiero registrar un gasto o ingreso indicando cuenta, monto, fecha y titulo/descripción, para llevar un historial detallado de mis movimientos.
- Como usuario, quiero editar o eliminar una transacción ya registrada, para corregir errores sin perder el historial.
- Como usuario, quiero ver un listado paginado de mis transacciones con filtros por fecha y cuenta, para encontrar fácilmente movimientos pasados.

### Epic 5: Categorías y Etiquetas
- Como usuario, quiero organizar mis transacciones en categorías y subcategorías, para entender en qué rubros gasto más.
- Como usuario, quiero agregar etiquetas libres a una transacción, para clasificarla con criterios propios que van más allá de las categorías fijas.
- Como usuario, quiero crear, editar y eliminar mis propias categorías, para personalizar la organización según mis hábitos.
- Como usuario nuevo, quiero tener categorías pre-cargadas al registrarme, para poder empezar a registrar gastos sin configuración previa.

---

## Etapa 2 — Producto Completo (Semanas 5–8)

**Objetivo:** flujos avanzados, multi-moneda, dashboard, sincronización robusta.

### Epic 5: Transferencias y Multi-moneda
- Como usuario, quiero registrar una transferencia entre dos de mis cuentas, para reflejar movimientos de dinero sin que aparezcan como gasto o ingreso.
- Como usuario, quiero transferir dinero entre cuentas de distinta moneda usando el tipo de cambio del momento, para que los balances queden correctos automáticamente.
- Como usuario, quiero ver mi balance total expresado en una moneda base de mi elección, para tener una vista consolidada de mi patrimonio.

### Epic 6: Búsqueda, Filtros y Organización Avanzada
- Como usuario, quiero filtrar mis transacciones por categoría, cuenta, tag, rango de fecha y monto, para encontrar movimientos específicos rápidamente.
- Como usuario, quiero buscar transacciones por texto libre en la descripción, para recuperar un gasto aunque no recuerde la categoría exacta.
- Como usuario, quiero guardar combinaciones de filtros como vistas favoritas, para acceder con un clic a los reportes que uso habitualmente.

### Epic 7: Dashboard y Analytics
- Como usuario, quiero ver un gráfico de mis gastos por categoría en un período determinado, para entender en qué estoy gastando más.
- Como usuario, quiero ver la evolución de mis gastos a lo largo del tiempo en un gráfico de línea, para identificar tendencias y meses atípicos.
- Como usuario, quiero ver el balance de cada cuenta y un total consolidado en la pantalla principal, para tener un resumen de mi situación financiera al abrir la app.

### Epic 8: Persistencia Local y Sincronización (Flutter)
- Como usuario mobile, quiero poder registrar transacciones sin conexión a internet, para no perder datos cuando no tengo señal.
- Como usuario mobile, quiero que mis datos se sincronicen automáticamente con el servidor cuando recupero la conexión, para que nada se pierda ni se duplique.
- Como usuario que usa la app en varios dispositivos, quiero que los cambios hechos en uno se reflejen en los demás en tiempo real, para siempre ver información actualizada.

---

## Etapa 3 — Asistente de Voz (Semanas 9–12)

**Objetivo:** integración con Gemini Live funcional end-to-end, flujo conversacional completo en web y Flutter.

> **Nota de arquitectura:** se optó por Gemini Live API directamente (WebSocket bidireccional a Google) en lugar de un worker propio. Esto simplifica la arquitectura y elimina la necesidad de manejar infraestructura de audio en servidor.

### Epic 9: Backend de Tools (prerequisito crítico)
- Como asistente de voz, quiero poder crear una transacción real en la base de datos cuando el usuario me lo indique por voz, para que los datos persistan y no se pierdan al cerrar la sesión.
- Como asistente de voz, quiero poder listar las transacciones del usuario con filtros cuando me los pida, para responderle con información real y actualizada.
- Como asistente de voz, quiero poder listar las cuentas del usuario, para ofrecerle opciones válidas al registrar una transacción o consultar un balance.
- Como desarrollador, quiero que cada tool verifique que el usuario autenticado solo accede a sus propios datos, para que la capa de voz no sea un vector de acceso no autorizado.

### Epic 10: Integración LLM — Refinamiento
- Como usuario, quiero que el asistente conozca mis cuentas y categorías al inicio de cada sesión, para poder decir "gasté en el supermercado" sin tener que aclarar cuenta ni categoría explícitamente.
- Como usuario, quiero que el asistente me pida confirmación antes de ejecutar acciones que no se pueden deshacer fácilmente, para no registrar transacciones erróneas por malentendidos.
- Como usuario, quiero poder consultar mi balance total o por cuenta con voz, para obtener un resumen financiero sin abrir ningún menú.
- Como usuario, quiero poder pedir un resumen de gastos de la semana o del mes hablando, para entender rápidamente cómo voy sin navegar por la app.

### Epic 11: UI de Voz en Flutter
- Como usuario mobile, quiero activar el asistente de voz con un botón y hablar naturalmente, para registrar gastos mientras camino o conduzco sin tocar la pantalla.
- Como usuario mobile, quiero ver en pantalla qué entendió el asistente y qué acción tomó, para confirmar que el registro fue correcto.
- Como usuario mobile, quiero escuchar la respuesta del asistente por audio, para completar el flujo sin mirar la pantalla.
- Como usuario mobile, quiero que la app me indique claramente si hubo un error de conexión o no me entendió, para saber cuándo tengo que repetir lo que dije.

### Epic 12: UI de Voz Web — Polish
- Como usuario web, quiero ver un historial legible de la conversación con el asistente durante la sesión, para poder revisar qué registré sin buscar en el listado de transacciones.
- Como usuario web, quiero ver una confirmación inline cada vez que el asistente registra una acción, para tener feedback inmediato sin depender del log técnico actual.
- Como usuario mobile que usa la versión web, quiero que la interfaz de voz se adapte a pantallas pequeñas, para poder usarla cómodamente desde el celular.

---

## Resumen por semana

| Semana | Etapa | Foco principal |
|--------|-------|---------------|
| 1–2 | 1 | Schema Convex, auth refinado, gestión de cuentas |
| 3–4 | 1 | Transacciones manuales, categorías y tags |
| 5–6 | 2 | Multi-moneda, transferencias, búsqueda |
| 7–8 | 2 | Dashboard, offline sync Flutter |
| 9–10 | 3 | Backend tools reales, tool definitions ampliadas |
| 11–12 | 3 | UI de voz Flutter, polish UI de voz web |

---

## Dependencias y riesgos

- El flujo de voz end-to-end depende directamente de que el backend de tools esté implementado (Epic 9 es prerequisito de Epics 10–12).
- El soporte offline de Flutter (Epic 8) es técnicamente complejo — si hay riesgo de delay, puede moverse a post-MVP.
- La elección de modelo LLM puede evaluarse en paralelo desde la semana 5 (pruebas de concepto sin UI) para no bloquear la Etapa 3.
- Convex Workflows debería evaluarse si el procesamiento de tool calls crece en complejidad (múltiples pasos, side effects asincrónicos).
