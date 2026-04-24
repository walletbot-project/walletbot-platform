# WalletBot — Estado Actual del Proyecto

> Última actualización: 2026-04-22

---

## Resumen ejecutivo

El proyecto tiene una base técnica sólida: autenticación funcionando, infraestructura de voz con Gemini Live implementada end-to-end en web, y el tooling del monorepo configurado. Sin embargo, la capa de datos (schema Convex, queries, mutations) está vacía, por lo que las tools del agente de voz retornan mocks y no persisten nada. El siguiente paso crítico es implementar el modelo de datos.

---

## Estado por capa

### Backend (`packages/backend/convex/`)

| Componente | Estado | Notas |
|-----------|--------|-------|
| Auth (Google OAuth) | ✓ Completo | better-auth v1.5.6, Google OAuth configurado |
| Auth (email/password) | ✗ Deshabilitado | Desactivado en la config actual |
| Schema Convex | ✗ Pendiente | `convex/schema.ts` está vacío — no hay tablas definidas |
| Queries | ✗ Pendiente | No hay ninguna query implementada |
| Mutations | ✗ Pendiente | No hay ninguna mutation implementada |
| Autorización (user-scoped) | ✗ Pendiente | No hay checks de ownership sobre datos |
| Token para Gemini Live | ✓ Completo | `convex/live/actions.ts` — genera token de 30 min con tools + system prompt |
| Crons | — | Archivo placeholder vacío |

**Tablas que faltan definir:**
- `accounts` — cuentas del usuario (tipo, moneda, nombre)
- `transactions` — gastos, ingresos, transferencias
- `categories` — categorías jerárquicas
- `tags` — etiquetas libres

---

### Web App (`apps/web/`)

| Componente | Estado | Notas |
|-----------|--------|-------|
| Estructura del proyecto | ✓ Completo | Vite + React 19 + Tailwind v4 + shadcn (base-ui) |
| Routing y layouts | ✓ Completo | React Router 7, layouts de auth y root |
| Auth guards | ✓ Completo | `AuthGuard` y `PublicGuard` funcionando |
| Página de login | ✓ Completo | Google OAuth, UX básica |
| UI de voz (home) | ✓ Completo | Panel con connect/disconnect, mute, mic level, device selector, event log |
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

### Flutter App (`apps/native/`)

| Componente | Estado | Notas |
|-----------|--------|-------|
| Scaffold | ✓ Existe | Flutter 3.11+ con estructura básica |
| Integración con Convex | ✗ Pendiente | No conectado al backend |
| Auth | ✗ Pendiente | Sin pantallas de login |
| Pantallas de la app | ✗ Pendiente | Solo el counter demo por defecto |
| UI de voz | ✗ Pendiente | Sin implementar |
| Persistencia local (SQLite) | ✗ Pendiente | Sin implementar |

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
    → Convex persiste/lee datos del usuario
    → Retorna resultado real a Gemini
```

---

## Próximos pasos recomendados

1. **Definir schema Convex** — tablas `accounts`, `transactions`, `categories`, `tags` con índices apropiados
2. **Implementar queries y mutations básicas** — con autorización por userId
3. **Reemplazar mocks** en `lib/agent-tools/executors.ts` con llamadas reales a Convex
4. Con eso, el flujo de voz queda funcional end-to-end
5. Luego construir las pantallas de UI manual (transacciones, cuentas, dashboard)

---

## Tooling y entorno

| Herramienta | Versión / Config |
|------------|-----------------|
| pnpm | Workspace monorepo |
| TypeScript | ^6.0.2 |
| Convex | ^1.35.1 — deployment: `modest-rooster-105.convex.cloud` |
| better-auth | 1.5.6 |
| Biome | formatter/linter |
| Nix devenv | Configurado (`devenv.nix`) |

**Scripts principales:**
```bash
pnpm dev              # web + convex dev en paralelo
pnpm run typecheck    # TypeScript en todos los packages
pnpm run format       # Biome formatter
pnpm run lint         # ESLint (web)
```
