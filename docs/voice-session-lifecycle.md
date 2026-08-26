# Sesiones de chat y voz

## Contrato de lifecycle

Una sesión lógica comienza con la primera interacción de voz o texto y sólo
termina cuando el usuario ejecuta **End session**. Salir de la pantalla, un
`GoAway`, un error de red o el recambio periódico del WebSocket no terminan la
sesión.

- La pantalla puede desacoplarse; el comando Live permanece en el scope de la
  cuenta. Al desacoplarla se vacía inmediatamente el audio pendiente y la
  respuesta en curso queda registrada como interrumpida.
- `contextWindowCompression.slidingWindow` mantiene la sesión por encima del
  límite normal de contexto.
- La continuidad del contexto NO usa los resume handles de Gemini: tras un
  corte abrupto un handle deja de resumir en segundos y el server abre en
  silencio una sesión EN BLANCO (verificado contra la API en vivo,
  2026-08-21). Cada (re)conexión abre una sesión nueva y re-siembra el
  contexto desde el transcript del log local (`buildConversationSeed` en
  nativo, `apps/web/src/lib/voice-seed.ts` en web), enviado como primer
  `clientContent` con `turnComplete: false`. Los `sessionResumptionUpdate`
  siguen llegando y su timestamp alimenta el gate local de frescura de la
  sesión reanudable en nativo; el handle nunca se presenta al reconectar.
- Un `GoAway` programa el recambio antes del `timeLeft`; un cierre inesperado
  usa backoff exponencial (máximo 30 segundos). Esto aplica a ambos clientes:
  la web reconecta igual que el nativo desde el overhaul del agente (antes un
  socket caído terminaba la conversación web).
- Los mensajes generados durante un recambio se conservan en una cola acotada
  y se envían en orden después del seed.
- El token efímero es de un solo uso (`uses: 1`); cada intento de conexión
  resuelve un token fresco. Su `expireTime` se fija en 19 h 55 min (el máximo
  de la API es menor a 20 horas).
- Si el proceso es suspendido o terminado por el sistema operativo no es
  posible mantener un socket ejecutándose. La sesión queda `suspended` y se
  intenta resumir al volver a abrirla mientras el handle siga vigente.

Referencias de Gemini: [session management](https://ai.google.dev/gemini-api/docs/live-api/session-management),
[ephemeral tokens](https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens).

## Persistencia local

Drift es la fuente primaria del historial. Cada evento se agrega inmediatamente
a `voice_session_events`, con id, secuencia monotónica, timestamp, dirección,
modalidad, payload semántico y mensaje crudo de protocolo cuando existe.

Se registran, entre otros:

- lifecycle de conexión y errores;
- mensajes y deltas de transcripción de usuario/agente;
- modalidad de texto, voz, audio o tool;
- mute/unmute, attach/detach de pantalla, playback y send message;
- llamadas, resultados y cancelaciones de tools;
- `usageMetadata`, `GoAway`, resumption y mensajes no reconocidos;
- PCM de entrada y salida, íntegro, en columnas BLOB con MIME y tamaño.

El log local se escribe antes de intentar cualquier envío remoto. No hay
limpieza ni política de retención automática en este issue: eliminar datos sin
una política explícita rompería la expectativa de export completo.

## Envío al servidor

Sólo las cuentas remotas replican sesiones. La réplica usa un outbox separado
del sync financiero, en lotes idempotentes de hasta 50 eventos:

- el outbox comienza a drenarse al adjuntar la cuenta remota, sin esperar a que
  el usuario abra la pantalla de voz;
- se envían todos los eventos semánticos y los mensajes crudos saneados;
- los cambios de metadata de una sesión se envían incluso cuando no hay eventos
  nuevos pendientes;
- cada request queda ligado al id de la cuenta que originó el outbox y el
  servidor rechaza cualquier mismatch con el usuario autenticado;
- el ack de una sesión sólo limpia el outbox si no hubo otro write desde que se
  tomó el snapshot enviado;
- para PCM se envían MIME y cantidad de bytes, no el binario;
- un fallo no bloquea la conversación: los eventos quedan pendientes y se
  reintentan;
- las cuentas locales nunca envían sesiones al servidor.

El PCM queda sólo local porque su frecuencia y volumen exceden el perfil seguro
de documentos/transacciones de Convex. Esto no reduce el export local.

## Export

`VoiceSessionRepository.exportSessionJson` exporta una sesión;
`exportAllSessionsJson` exporta todo el historial. Sus variantes `*File`
escriben el JSON autocontenido y versionado en disco. No se agregó UI.

El export incluye metadata completa de la sesión y todos los eventos ordenados.
Los BLOB PCM se codifican en base64, por lo que el archivo conserva los bytes
originales sin pérdida. Los handles de resumption se incluyen en el export
local y no se replican al servidor.
