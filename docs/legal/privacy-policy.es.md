# Wallet Bot — Política de Privacidad

**Fecha de entrada en vigencia:** 6 de agosto de 2026
**Última actualización:** 6 de agosto de 2026

> Esta Política de Privacidad se publica en español y en inglés. Para los consumidores residentes en la República Argentina, la versión en español es el texto jurídicamente operativo y prevalece en caso de discrepancia. Para los demás usuarios prevalece la versión en inglés, siendo la versión en español una traducción de cortesía.

## 1. Quiénes somos

Wallet Bot ("**Wallet Bot**", el "**Servicio**", "**nosotros**") es una aplicación de registro de gastos personales, disponible como aplicación móvil/nativa y como aplicación web en `https://app.walletbot.live`.

El responsable de la base de datos en los términos de la Ley N° 25.326 de Protección de los Datos Personales es:

- **Responsable:** Tomás Cichero
- **Domicilio:** Estanislao del Campo 1260, B1604ADH Florida Oeste, Provincia de Buenos Aires, Argentina
- **Contacto para asuntos de privacidad:** support@walletbot.live

## 2. Alcance

Esta Política describe qué datos personales recolectamos a través de las aplicaciones nativas y web de Wallet Bot, con qué finalidad, con quién los compartimos, por cuánto tiempo los conservamos y qué derechos tiene usted sobre ellos. Forma parte de nuestros Términos y Condiciones y debe leerse junto con ellos.

Al crear una cuenta, usted declara haber leído esta Política y presta su consentimiento **libre, expreso e informado** al tratamiento aquí descripto, incluida la transferencia internacional descripta en la Sección 8. La entrega de sus datos personales es voluntaria; sin embargo, sin una dirección de correo electrónico (o un inicio de sesión de terceros) no podemos crearle una cuenta en línea. Como alternativa, puede usar la aplicación en **modo local** (ver Sección 16), en cuyo caso sus registros financieros permanecen en su dispositivo y no nos son enviados (la aplicación sí envía los datos de uso y diagnóstico descriptos en la Sección 3.4).

## 3. Datos que recolectamos

### 3.1 Datos de cuenta y perfil

- Dirección de correo electrónico y nombre para mostrar.
- Si se registra con correo y contraseña: su contraseña, almacenada únicamente como hash criptográfico. Nunca almacenamos ni podemos leer su contraseña en texto plano.
- Si inicia sesión con Google, Apple u otro proveedor de identidad soportado: su nombre, correo electrónico, URL de foto de perfil, el identificador de cuenta del proveedor y los tokens de autenticación emitidos por el proveedor.
- Estado de verificación del correo y tokens de verificación / restablecimiento de contraseña (de corta duración).

### 3.2 Datos financieros que usted ingresa

Wallet Bot es un registro de gastos de **carga manual**. Almacenamos los registros financieros que usted crea (o que el asistente de voz crea siguiendo sus instrucciones):

- Cuentas de dinero: las etiquetas que usted elige (por ejemplo, el nombre de un banco o billetera), moneda, descripción, color e ícono.
- Transacciones: tipo (gasto, ingreso, transferencia, ajuste de saldo), nombre/descripción (por ejemplo, un comercio), montos y monedas, fechas, estado, tipos de cambio en transferencias entre monedas y saldos resultantes.
- Categorías, etiquetas, filtros guardados y configuración del panel.

**No** nos conectamos con su banco. Nunca solicitamos, recibimos ni almacenamos credenciales bancarias, números de tarjeta, números de cuenta (CBU/CVU/IBAN) ni ningún otro medio de pago. Los nombres que usted da a sus cuentas son solo etiquetas de texto libre.

### 3.3 Datos del asistente de voz y conversaciones

Ver la Sección 5, que describe este tratamiento en detalle.

### 3.4 Datos técnicos y de seguridad

- **Sesiones web:** dirección IP y user-agent del navegador, almacenados junto con su sesión.
- **Inicios de sesión en la app nativa:** la cadena user-agent del dispositivo, almacenada con el registro de sesión (esto permite reconocer los dispositivos con sesión iniciada).
- **Solicitudes de sincronización:** plataforma (Android/iOS/macOS) y versión de la aplicación, usadas para exigir versiones mínimas soportadas.
- **Solicitudes de configuración:** plataforma, versión de la aplicación, idioma del dispositivo y un identificador de instalación aleatorio generado por la app (es deliberadamente un estado aleatorio de la aplicación, no un identificador de hardware). Estos valores se procesan para servir configuración remota y avisos de actualización, y no se almacenan en nuestra base de datos.
- Contadores de limitación de solicitudes (rate limiting) y registros de seguridad/errores, que pueden incluir direcciones de correo en eventos de fallo de entrega.
- **Analítica de uso:** eventos sobre cómo usa la aplicación (pantallas vistas, funciones utilizadas y datos de interacción similares), junto con información del dispositivo y de la aplicación (modelo del dispositivo, sistema operativo y su versión, versión de la aplicación, idioma) e identificadores aleatorios de instalación y de sesión generados por la app (no son identificadores de hardware ni publicitarios).
- **Datos de fallos y diagnóstico:** reportes de errores y fallos, incluidos stack traces, información del dispositivo y de la aplicación, y el estado de la app al momento del error. Los reportes de fallos no están destinados a incluir sus registros financieros, pero pueden contener incidentalmente fragmentos de los datos que se estaban procesando cuando ocurrió el error.

### 3.5 Registros de correos transaccionales

Cuando le enviamos un correo transaccional (verificación, restablecimiento de contraseña, confirmación de eliminación de cuenta), nuestro proveedor de envío de correo retiene temporalmente la dirección de destino, el asunto y el contenido del mensaje (ver Sección 9), junto con los eventos de entrega (entregado, rebotado, quejado).

## 4. Datos que NO recolectamos

- Sin conexión con bancos ni entidades financieras; sin credenciales bancarias ni de tarjetas.
- Sin geolocalización precisa ni aproximada.
- Sin acceso a sus contactos. Solo accedemos a sus archivos, fotos o cámara cuando usted explícitamente elige un archivo, comparte un archivo o toma una foto — nunca en segundo plano ni sin una acción suya.
- Sin identificadores publicitarios, sin redes de publicidad, sin rastreo de terceros.
- Sin número de teléfono, fecha de nacimiento ni documento de identidad.
- No vendemos ni alquilamos datos personales a nadie, ni los compartimos para publicidad de terceros.

## 5. Asistente de voz y procesamiento con inteligencia artificial

El asistente de voz de Wallet Bot es una función **opcional**. Le permite registrar gastos y consultar sus finanzas por voz o por chat de texto.

- El **acceso al micrófono** se solicita únicamente cuando usted inicia una sesión de voz, y puede denegarlo; el resto de la aplicación funciona sin él.
- Al iniciar una sesión, nuestro backend emite un **token de acceso de corta duración y de un solo uso**, y su dispositivo se conecta **directamente** al proveedor de inteligencia artificial de la sesión: la API Gemini Live de Google (Google LLC) o la API de OpenAI (OpenAI, L.L.C.). El audio de su micrófono se transmite desde su dispositivo hacia ese proveedor; **el audio en crudo nunca pasa por nuestros servidores ni se almacena en ellos**.
- Las grabaciones de audio de una sesión se conservan **únicamente en su dispositivo** (app nativa). Nunca se suben a nuestros servidores; del audio solo se registra en el servidor el tipo y el tamaño de los segmentos.
- Almacenamos el **contenido de la conversación**: transcripciones de lo que usted dijo y de lo que respondió el asistente, las acciones que el asistente ejecutó ("tool calls" — por ejemplo, crear una transacción) con sus resultados, y metadatos de la sesión. Para cuentas con sesión iniciada este historial se sincroniza con nuestro backend; **las sesiones de voz de la aplicación web no se almacenan en nuestros servidores**; **las cuentas en modo local nunca suben su historial de voz**.
- Mientras una sesión está activa, el asistente puede **leer y modificar los datos financieros de su cuenta** (cuentas, saldos, transacciones, categorías, etiquetas, resúmenes) para ejecutar sus pedidos. Los datos que lee o escribe pasan a formar parte de la conversación procesada por el proveedor de inteligencia artificial.
- El proveedor de inteligencia artificial (Google u OpenAI) procesa el audio y el contenido de la conversación bajo sus propios términos de API aplicables. Configuramos las sesiones para usar credenciales efímeras de un solo uso.
- El historial de sesiones de voz se conserva por un **máximo de 12 meses** y también se elimina de inmediato si usted elimina su cuenta (Sección 9).
- El asistente puede cometer errores (interpretar mal montos, nombres o monedas). Revise los registros que crea; ver el descargo correspondiente en los Términos y Condiciones.

## 6. Finalidades del tratamiento

Tratamos sus datos personales para:

1. **Prestar y operar el Servicio** — crear su cuenta, almacenar y sincronizar sus registros financieros entre sus dispositivos y operar el asistente de voz cuando usted lo usa. Este tratamiento es necesario para la ejecución del contrato entre usted y nosotros (artículo 5°, inciso 2, apartado d, Ley 25.326).
2. **Autenticación y seguridad** — verificar su correo, proteger su cuenta, detectar y prevenir fraude y abuso, limitar solicitudes y revocar sesiones tras un restablecimiento de contraseña.
3. **Comunicaciones transaccionales** — correos estrictamente necesarios para el Servicio (verificación, restablecimiento de contraseña, eliminación de cuenta). **No enviamos correos de marketing**; si alguna vez los introducimos, serán estrictamente opcionales (opt-in) y con un mecanismo de baja funcional.
4. **Analítica y mejora del Servicio** — medir cómo se usa el Servicio y recolectar reportes de fallos y diagnóstico para detectar errores, mejorar la estabilidad y orientar mejoras del producto. También podremos analizar el contenido que usted ingresa, en forma agregada o disociada, para mejorar y desarrollar funciones del Servicio. No usamos estos datos con fines publicitarios.
5. **Cumplimiento legal** — responder a requerimientos legales válidos y ejercer o defender reclamos legales.

No usamos sus datos para decisiones automatizadas que produzcan efectos jurídicos o significativos sobre usted, ni construimos perfiles publicitarios.

**Consecuencias de no proporcionar los datos:** sin un correo/identidad no es posible crear una cuenta en línea; el modo local permanece disponible. Usted puede revocar su consentimiento en cualquier momento, sin efectos retroactivos, contactándonos o eliminando su cuenta.

## 7. Destinatarios: proveedores de servicios con los que compartimos datos

Compartimos datos personales únicamente con los encargados de tratamiento necesarios para operar el Servicio, bajo sus compromisos contractuales de protección de datos:

| Proveedor | Función | Datos involucrados |
|---|---|---|
| Convex, Inc. (EE. UU.) | Plataforma de backend y alojamiento de la base de datos | Todos los datos del lado del servidor descriptos en la Sección 3 |
| Google LLC (EE. UU.) | Inicio de sesión con Google; API Gemini Live (asistente de voz) | Datos de perfil del inicio de sesión; audio y contenido de conversaciones de voz/chat y los datos financieros que el asistente lee o escribe durante una sesión |
| OpenAI, L.L.C. (EE. UU.) | Proveedor de inteligencia artificial de chat y voz (asistente) | Audio y contenido de conversaciones de voz/chat y los datos financieros que el asistente lee o escribe durante una sesión |
| Apple Inc. (EE. UU.) | Inicio de sesión con Apple (cuando esté disponible) | Datos de perfil del inicio de sesión (nombre, correo electrónico, identificador de cuenta del proveedor) |
| Resend, Inc. (EE. UU.) | Envío de correos transaccionales | Dirección de correo del destinatario, nombre para mostrar, contenido del mensaje |
| Cloudflare, Inc. (EE. UU.) | Alojamiento / CDN de la aplicación web | Registros estándar de solicitudes web (dirección IP, user-agent) |
| Grafana Labs (EE. UU.) | Plataforma de observabilidad — almacenamiento de métricas de uso y eventos de diagnóstico | Eventos y métricas de uso/diagnóstico, incluidos identificadores aleatorios de instalación y de sesión, un identificador interno de usuario, versión de la aplicación y plataforma |
| Google LLC (EE. UU.) — Firebase | Analítica de uso y reportes de fallos (Firebase Analytics, Crashlytics) | Eventos de uso, información del dispositivo y de la aplicación, reportes de fallos/diagnóstico |

También podremos divulgar datos personales si así lo exige la ley, una orden judicial o una autoridad competente, o para proteger los derechos, la seguridad y la integridad de Wallet Bot, de nuestros usuarios o de terceros. Si el Servicio se transfiriera en el marco de una fusión, adquisición o venta de activos, sus datos podrán transferirse con él; le notificaremos antes de que sus datos queden sujetos a una política de privacidad distinta.

**Nunca** vendemos sus datos personales ni los compartimos para publicidad comportamental de terceros.

## 8. Transferencia internacional de datos

Nuestros proveedores almacenan y procesan los datos en los **Estados Unidos de América**. Conforme al derecho argentino (artículo 12, Ley 25.326), los Estados Unidos no es un país con niveles adecuados de protección de datos. Nos apoyamos en dos salvaguardas:

1. **Salvaguardas contractuales:** nuestros proveedores están obligados por acuerdos de tratamiento de datos que contienen compromisos de protección de datos.
2. **Su consentimiento expreso e informado:** al crear una cuenta y aceptar esta Política, usted consiente expresamente que sus datos personales sean transferidos a los Estados Unidos y almacenados allí bajo dichas salvaguardas.

Usted puede revocar este consentimiento en cualquier momento (sin efectos retroactivos) eliminando su cuenta, dado que el Servicio no puede operar sin sus proveedores de alojamiento.

## 9. Plazos de conservación

| Datos | Conservación |
|---|---|
| Datos de cuenta, perfil y financieros | Mientras exista su cuenta; se eliminan de forma definitiva al eliminar la cuenta |
| Sesiones y tokens de inicio de sesión | Hasta el cierre de sesión, revocación o expiración; se revocan todos al restablecer la contraseña y al eliminar la cuenta |
| Historial de sesiones de voz (transcripciones, acciones, metadatos) | Máximo **12 meses** desde su creación, luego se eliminan automáticamente; se eliminan de inmediato al eliminar la cuenta. Las grabaciones de audio existen solo en su dispositivo |
| Registros de correos transaccionales (en nuestro proveedor de correo) | Depuración automática: correos entregados/finalizados a los 7 días; no entregables/abandonados a los 30 días |
| Solicitudes de eliminación de cuenta (correo + hash del token de confirmación) | Se eliminan al completarse la eliminación; las solicitudes vencidas quedan sin validez y no pueden volver a usarse |
| Registro de seguridad posterior a la eliminación | Tras completarse la eliminación conservamos únicamente un identificador interno aleatorio de la cuenta y la fecha de eliminación, para que las credenciales emitidas a la cuenta eliminada no puedan volver a usarse jamás. Este registro no contiene nombre, correo ni datos financieros |
| Registros de seguridad y errores | Retención breve y rotativa en nuestra plataforma de backend |
| Datos de analítica de uso y de fallos/diagnóstico | Hasta **14 meses** (datos de analítica a nivel de usuario) y **90 días** (reportes de fallos), conforme a la configuración de retención de datos de Google Firebase |

## 10. Eliminación de cuenta

Usted puede eliminar su cuenta y todos los datos asociados en cualquier momento:

- **Desde la app:** Ajustes → Eliminar mi cuenta; o
- **Desde la web, sin la app instalada:** `https://app.walletbot.live/delete-account`.

Le enviamos por correo un enlace de confirmación (válido por 24 horas). Una vez confirmada, la eliminación comienza de inmediato y es **irreversible**: todos sus registros financieros, historial de voz, sesiones y datos de perfil se borran de forma permanente de nuestro backend, y sus datos de identidad se eliminan de nuestro sistema de autenticación. Lo que subsiste después se describe en la Sección 9.

La eliminación es del lado del servidor: los datos almacenados localmente en sus dispositivos (Sección 16) se eliminan cerrando sesión en cada dispositivo o desinstalando la aplicación.

## 11. Seguridad

Aplicamos medidas técnicas y organizativas alineadas con las recomendaciones de seguridad de la autoridad de control argentina (Resolución AAIP 47/2018), entre ellas:

- Cifrado en tránsito (TLS) para todas las conexiones.
- Contraseñas almacenadas únicamente como hashes criptográficos, nunca en texto plano.
- Credenciales de corta duración y de un solo uso para las sesiones de voz; tokens firmados y con expiración para la autenticación.
- Verificación de correo obligatoria; revocación de todas las sesiones al restablecer la contraseña; limitación de solicitudes y medidas anti-enumeración en los puntos sensibles.
- Almacenamiento de credenciales en el dispositivo dentro del almacenamiento seguro del sistema operativo (Keychain / Android Keystore).

Ningún sistema es perfectamente seguro. Si tomamos conocimiento de un incidente de seguridad que afecte sus datos personales, notificaremos a los usuarios afectados y a las autoridades competentes según corresponda a la naturaleza del incidente.

## 12. Sus derechos (Argentina)

Como titular de los datos, usted tiene, en forma gratuita, los derechos de **acceso, rectificación, actualización y supresión** de sus datos personales (artículos 14 a 16, Ley 25.326):

- **Acceso:** responderemos dentro de los 10 días corridos de recibida su solicitud. El acceso es gratuito a intervalos no inferiores a seis meses, salvo que se acredite un interés legítimo.
- **Rectificación, actualización y supresión:** se realizan dentro de los 5 días hábiles.
- **Revocación del consentimiento:** en cualquier momento, sin efectos retroactivos.

Para ejercer cualquier derecho, escriba a **support@walletbot.live** desde la dirección de correo asociada a su cuenta (podremos pedirle que verifique su identidad), use las opciones dentro de la aplicación o el flujo de eliminación autogestionado descripto en la Sección 10.

**El titular de los datos personales tiene la facultad de ejercer el derecho de acceso a los mismos en forma gratuita a intervalos no inferiores a seis meses, salvo que se acredite un interés legítimo al efecto, conforme lo establecido en el artículo 14, inciso 3 de la Ley N° 25.326.**

**LA AGENCIA DE ACCESO A LA INFORMACIÓN PÚBLICA, en su carácter de Órgano de Control de la Ley N° 25.326, tiene la atribución de atender las denuncias y reclamos que interpongan quienes resulten afectados en sus derechos por incumplimiento de las normas vigentes en materia de protección de datos personales.**

Puede contactar a la AAIP en `https://www.argentina.gob.ar/aaip`.

## 13. Sus derechos (Estados Unidos)

Extendemos los siguientes derechos a **todos los usuarios residentes en los Estados Unidos**, sin importar el estado:

- **Derecho a conocer / acceder** a la información personal que tenemos sobre usted y obtener una **copia portable**.
- **Derecho a corregir** información personal inexacta.
- **Derecho a eliminar** su información personal (Sección 10).
- **Derecho a optar por no participar de la "venta" o "compartición" de información personal ni de publicidad dirigida** — aclarando que **no vendemos ni compartimos información personal** según esos términos se definen en las leyes estatales de privacidad de EE. UU., ni hacemos publicidad dirigida.
- **Derecho a la no discriminación** por ejercer cualquiera de estos derechos.

Para ejercerlos, escriba a **support@walletbot.live** desde la dirección asociada a su cuenta; verificaremos la solicitud y responderemos dentro de los 45 días (prorrogables una vez cuando sea razonablemente necesario, con aviso). Los agentes autorizados pueden presentar solicitudes acreditando su autorización. Si denegamos una solicitud, usted puede apelar respondiendo a nuestra decisión, y responderemos la apelación.

## 14. Menores de edad

El Servicio está destinado a personas adultas y requiere tener **18 años o más**. No recolectamos a sabiendas datos personales de menores de 18 años y, en particular, de menores de 13 (COPPA, EE. UU.). Si tomamos conocimiento de que tenemos datos de una persona menor de 18 años, eliminaremos la cuenta y sus datos. Si usted cree que un menor nos proporcionó datos, contáctenos en support@walletbot.live.

## 15. Cookies y tecnologías similares (aplicación web)

La aplicación web puede utilizar cookies y almacenamiento del navegador similar para el funcionamiento del Servicio (por ejemplo, para mantener su sesión iniciada). **No** utilizamos cookies de terceros.

## 16. Datos almacenados en su dispositivo

La aplicación almacena sus datos localmente en su dispositivo para poder funcionar sin conexión. Si usa el **modo local** (sin cuenta en línea), sus datos permanecen exclusivamente en su dispositivo, nunca se nos transmiten y **no podemos recuperarlos** si el dispositivo se pierde (la aplicación sí envía los datos de uso y diagnóstico descriptos en la Sección 3.4). Cerrar sesión en una cuenta o desinstalar la aplicación elimina sus datos locales. Las funciones de respaldo de su sistema operativo pueden incluir datos de la aplicación según la configuración de su dispositivo, que está bajo su control.

## 17. Cambios a esta Política

Podremos actualizar esta Política a medida que el Servicio evolucione. Ante cambios sustanciales, se lo notificaremos a través del Servicio (por ejemplo, mediante un aviso en la aplicación) antes de que entren en vigencia o al momento de entrar en vigencia y, cuando el cambio lo requiera (por ejemplo, una nueva finalidad de tratamiento), le pediremos su consentimiento. La fecha de "Última actualización" en el encabezado refleja siempre la versión vigente. Si usted no está de acuerdo con un cambio, puede eliminar su cuenta.

## 18. Contacto

- **Solicitudes de privacidad y protección de datos:** support@walletbot.live
- **Responsable:** Tomás Cichero, Estanislao del Campo 1260, B1604ADH Florida Oeste, Provincia de Buenos Aires, Argentina
- **Autoridad de control (Argentina):** Agencia de Acceso a la Información Pública — `https://www.argentina.gob.ar/aaip`
