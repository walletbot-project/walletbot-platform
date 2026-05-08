# WalletBot — Estado Actual del Proyecto

> Última actualización: 2026-05-08

---

## Resumen ejecutivo

El proyecto tiene una base técnica sólida: autenticación funcionando en web, infraestructura de voz con Gemini Live implementada end-to-end en web, schema Convex completamente definido con todas las tablas, y el schema local de Flutter con Drift también implementado con soporte de sincronización offline. Sin embargo, la capa de acceso a datos (queries, mutations) está vacía — el schema existe pero no hay ninguna función Convex que lea o escriba datos. Las tools del agente de voz siguen retornando mocks. El siguiente paso crítico es implementar queries y mutations en Convex.

---

## Estado por capa

### Backend (`packages/backend/convex/`)

| Componente | Estado | Notas |
|-----------|--------|-------|
| Auth (Google OAuth) | ✓ Completo | better-auth v1.5.6, Google OAuth configurado |
| Auth (email/password) | ✗ Deshabilitado | Desactivado en la config actual |
| Schema Convex | ✓ Completo | Todas las tablas definidas con índices en `convex/schema/` |
| Queries | ✗ Pendiente | No hay ninguna query implementada |
| Mutations | ✗ Pendiente | No hay ninguna mutation implementada |
| Autorización (user-scoped) | ✗ Pendiente | No hay checks de ownership sobre datos |
| Token para Gemini Live | ✓ Completo | `convex/live/actions.ts` — genera token de 30 min con tools + system prompt |
| Crons | — | Archivo placeholder vacío |

**Tablas definidas en `convex/schema/`:**
- `accounts` — cuentas del usuario (nombre, moneda, color, ícono, descripción, isArchived, timestamps, seq de sync)
- `transactions` — gastos, ingresos, transferencias, ajustes de balance; soporte multi-moneda con campos de transferencia opcionales
- `categories` — categorías con flag de archivado
- `tags` — etiquetas con soporte jerárquico (`parentId`)
- `transactionTags` — tabla join many-to-many (transacción ↔ tag)
- `syncCounters` — contador de secuencia por usuario (para sync offline)
- `tombstones` — registros de soft-delete para sincronización

---

### Web App (`apps/web/`)

| Componente | Estado | Notas |
|-----------|--------|-------|
| Estructura del proyecto | ✓ Completo | Vite + React 19 + Tailwind v4 + shadcn (base-ui) |
| Routing y layouts | ✓ Completo | React Router 7, layouts de auth y root |
| Auth guards | ✓ Completo | `AuthGuard` y `PublicGuard` funcionando |
| Página de login | ✓ Completo | Google OAuth, UX básica |
| UI de voz (home) | ✓ Completo | Panel con connect/disconnect, mute, mic level, device selector, event log con timestamps |
| WebSocket Gemini Live | ✓ Completo | `hooks/use-voice.ts` — audio worklet 16kHz entrada / 24kHz salida |
| Tool definitions (shared) | ✓ Completo | Zod schemas en `packages/shared`, adapter para Google AI |
| Tool executors (frontend) | ⚠ Mock | `lib/agent-tools/executors.ts` — retorna datos hardcodeados, no llama a Convex |
| Pantalla de transacciones | ✗ Pendiente | No existe |
| Pantalla de cuentas | ✗ Pendiente | No existe |
| Dashboard / analytics | ✗ Pendiente | No existe |
| Categorías y tags (UI) | ✗ Pendiente | No existe |

**Tools definidas (actualmente mockeadas):**
- `addTransaction(type, amount, description)`
- `listTransactions(type?)`
- `listAccounts()`

---

### Shared Package (`packages/shared/`)

| Componente | Estado | Notas |
|-----------|--------|-------|
| Tool definitions (Zod) | ✓ Completo | `addTransaction`, `listTransactions`, `listAccounts` |
| Adapter a Google AI schema | ✓ Completo | `zodToToolSchema()` convierte Zod → FunctionDeclaration |
| Tipos exportados | ✓ Completo | `ToolName`, `ToolArgs<T>`, `TOOL_DEFINITIONS`, `TOOL_MAP` |

---

### Flutter App (`apps/app/`)

| Componente | Estado | Notas |
|-----------|--------|-------|
| Scaffold + navegación | ✓ Completo | Bottom nav con 4 tabs (Home, Activity, Accounts, Settings), FAB para agregar |
| Auth gate | ✓ Completo | Muestra LoginScreen o AppMain según estado de auth |
| Login screen | ✓ Completo | Lista cuentas locales/remotas, switch de cuenta, "continuar sin cuenta" funcional |
| Google Sign-In | ✗ Pendiente | Botón existe pero muestra "not implemented yet" |
| Schema local (Drift) | ✓ Completo | Todas las tablas: accounts, transactions, categories, tags, transactionTags, syncState, tombstones. Flag `dirty` para sync. |
| Pantalla Home | ⚠ Stub | Esqueleto básico con menú de usuario, sin contenido real |
| Pantalla Activity | ✗ Stub | Placeholder solamente |
| Pantalla Add | ✗ Stub | Placeholder solamente |
| Integración con Convex | ✗ Pendiente | No hay cliente Convex ni lógica de sync |
| Lógica de sync offline | ✗ Pendiente | Schema preparado pero sync no implementado |
| UI de voz | ✗ Pendiente | Sin implementar |

---

## Flujo de voz — estado actual

El flujo ya existe pero está incompleto porque las tools no persisten datos:

```
Usuario habla
    → Audio 16kHz PCM → WebSocket → Gemini Live API
    → Gemini detecta intent → emite tool call (ej: addTransaction)
    → Frontend recibe tool call → ejecuta mock → retorna datos falsos
    → Gemini procesa resultado → responde por audio
    → Audio 24kHz PCM → speakers
```

**Lo que falta para cerrarlo:**
```
    → Frontend recibe tool call → llama a Convex mutation/query real
    → Convex persiste/lee datos del usuario (con autorización)
    → Retorna resultado real a Gemini
```

---

## Próximos pasos recomendados

### Prioridad alta (desbloquean todo lo demás)

1. **Implementar queries y mutations Convex** con autorización por userId — todas las entidades: accounts, transactions, categories, tags
   - Empezar por accounts y transactions (las más críticas para el flujo de voz)
   - Usar paginación en todas las queries de listado
   - Verificar `ctx.auth.getUserIdentity()` en cada función

2. **Reemplazar mocks** en `apps/web/src/lib/agent-tools/executors.ts` con llamadas reales a Convex
   - Con esto, el flujo de voz queda funcional end-to-end

### Prioridad media (completar Etapa 1)

3. **Pantallas web de UI manual** — transacciones, cuentas (no existe ninguna todavía)
4. **Categorías** — queries, mutations y UI web
5. **Google Sign-In en Flutter** — completar el OAuth flow
6. **Conectar Flutter a Convex** — cliente + sync básico

### Prioridad baja (Etapa 2+)

7. **Lógica de sync Flutter** — tablas y flag `dirty` ya existen, falta la lógica de sincronización bidireccional
8. **Dashboard y analytics** — gráficos, totales por cuenta
9. **Multi-moneda y transferencias**
10. **UI de voz en Flutter**

---

## Tooling y entorno

| Herramienta | Versión / Config |
|------------|-----------------|
| pnpm | Workspace monorepo |
| TypeScript | ^6.0.2 |
| Convex | ^1.35.1 — deployment: `modest-rooster-105.convex.cloud` |
| better-auth | 1.5.6 |
| Biome | formatter/linter |
| Flutter | 3.11+ con Drift ORM para SQLite local |
| Nix devenv | Configurado (`devenv.nix`) |

**Scripts principales:**
```bash
pnpm dev              # web + convex dev en paralelo
pnpm run typecheck    # TypeScript en todos los packages
pnpm run format       # Biome formatter
pnpm run lint         # ESLint (web)
```
