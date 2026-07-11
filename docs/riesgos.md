# Registro de riesgos

Actualizado: 2026-07-11

Este documento mantiene los riesgos actuales del proyecto en un formato liviano.
La idea es revisarlo al cierre de cada iteración o cuando una decisión técnica
cambie la probabilidad, el impacto o la mitigación de un riesgo.

## Criterios

- Probabilidad: Baja, Media, Alta.
- Impacto: Bajo, Medio, Alto, Crítico.
- ID: identificador estable para referenciar riesgos en issues, PRs o reuniones.
- Prioridad: orden relativo de importancia actual; puede cambiar sin cambiar el
  ID del riesgo.
- Mantener cada mitigación como una acción concreta y verificable.
- Si un riesgo deja de aplicar, moverlo a una sección de riesgos cerrados en
  lugar de borrarlo.

## Riesgos actuales

| Prioridad | ID | Riesgo | Categoría | Probabilidad | Impacto | Mitigación |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | R-001 | El modo de voz interpreta mal un gasto, ingreso o transferencia y registra datos incorrectos. | Producto / IA | Media | Alto | Mostrar visualmente los movimientos detectados y pedir confirmación antes de guardarlos. |
| 2 | R-005 | El usuario no detecta o no puede corregir fácilmente registros creados por la conversación. | UX / Calidad de datos | Alta | Medio | Priorizar pantallas de revisión y edición rápida, incluir estados claros para acciones pendientes/confirmadas y permitir deshacer o corregir el último movimiento. |
| 3 | R-006 | No tener una estimación clara del consumo de tokens en features clave vuelve inviable la app por costos o límites de uso. | Costos / IA | Media | Alto | Medir consumo real por flujo crítico, definir presupuestos por sesión o usuario y evaluar estrategias de reducción antes de escalar el uso. |
| 4 | R-007 | Cambios en el modelo de pricing del modelo de IA utilizado dejan a la app fuera de mercado. | Costos / Dependencias externas | Media | Alto | Monitorear cambios de pricing, mantener alternativas de proveedor o modelo evaluadas y definir umbrales de costo por usuario que disparen una revisión de producto. |
| 5 | R-003 | Cambios en APIs externas de voz, IA, Better Auth o Convex rompen flujos principales. | Dependencias externas | Media | Medio | Encapsular integraciones detrás de helpers propios, fijar versiones compatibles, documentar variables requeridas y mantener un flujo manual de smoke test para login, voz y persistencia. Nueva dependencia `fl_chart` (`^1.2.0`, gráfico de breakdown del home) fijada por versión y aislada en `breakdown_chart_widget.dart`; sólo renderiza datos locales (no agrega superficie de red ni de sync). El gate de versión de cliente (`GET /v1/config`, `minSupportedVersion`) permite bloquear la sincronización de clientes incompatibles ante un cambio de contrato manteniendo el uso offline (ver `packages/backend/convex/config/helpers.ts`), y los RPC públicos propios consumidos por los clientes están aislados bajo `v1/` sin aliases heredados (ver `docs/client-api-versioning.md`). |
| 6 | R-002 | Se exponen datos financieros personales por errores de autorización, logging o configuración de entorno. | Seguridad / Privacidad | Baja | Crítico | Requiere más análisis específico de privacidad y seguridad; mientras tanto, derivar siempre el usuario desde la sesión server-side y evitar logs con datos financieros sensibles. |
| 7 | R-004 | La app web y la app nativa divergen en experiencia de usuario. | UX | Media | Bajo | Definir criterios compartidos para los flujos principales y revisar paridad visual y funcional en cada feature que toque movimientos, cuentas o categorías. Divergencia activa conocida: el home dashboard (widgets + filtros guardados) existe sólo en nativo; la home web sigue siendo placeholder (paridad pendiente, ver `docs/home-dashboard.md`). |
| 8 | R-008 | Un write path nuevo en la app nativa escribe a la base local sin respetar el contrato de sync (`dirty`/`updatedAt`/tombstones) y los cambios no sincronizan o se pierden por LWW. | Técnico / Sync | Baja | Alto | Mantener todas las escrituras detrás de `lib/data/` (refactor 2026-06-11): repositorios con contrato único, tests unitarios del contrato (`test/data/`), CI de analyze+test para la app nativa y gate de revisión "ningún `db.into/update/delete` fuera de `lib/data/` y `lib/sync/`". Las nuevas tablas `savedFilters`/`dashboardWidgets` (home dashboard) siguen el mismo contrato vía `SavedFilterRepository`/`DashboardRepository` y están cubiertas por `write_contract_test.dart`. Gate de versión de cliente aplicado en **ambos lados**: además del gate cliente (`_SyncStarter` lee `syncAllowed`), `v1/sync/mutations:push` y `v1/sync/queries:pull` validan `appVersion`/`platform` contra `minSupportedVersion` en el servidor (`config/helpers.ts:isClientSupported`) y devuelven `{ ok: false, error: 'client_outdated' }`; el motor de sync se detiene y el cliente pasa al aviso de actualización obligatoria. Así un cliente viejo o manipulado que falla/omite el fetch de config (y queda fail-open) igual no puede sincronizar un wire incompatible. |
| 9 | R-009 | Una URL de backend fija embebida en la app nativa deja inutilizables las instalaciones existentes si el deployment de Convex cambia (plan gratuito, sin dominio propio para el backend). | Técnico / Operaciones | Baja | Alto | Capa de bootstrap L0: la app resuelve la URL del backend desde un JSON estático estable (`BOOTSTRAP_URL`) al iniciar, con fallback a la caché del último valor bueno y luego al valor embebido (falla abierta, no bloquea el arranque). Las URLs recibidas se validan como `https` con host no vacío antes de aplicarse o cachearse, para que una respuesta comprometida/MITM no pueda redirigir el WebSocket ni los POST de `/auth/refresh` (que llevan el token de sesión) a otro host. Ver `apps/native/lib/app_config/bootstrap.dart`. |
