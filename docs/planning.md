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

**Objetivo:** infraestructura sólida, flujo end-to-end de transacciones manuales funcional.

### Epic 1: Infraestructura y Setup
- Schema Convex: `users`, `accounts`, `transactions`, `categories`, `tags`
- Auth completo: Google OAuth + email/password via better-auth
- Índices, paginación y helpers de autorización
- CI/CD básico (lint, typecheck, format en PR)
- Definición de convenciones de código y documentación interna (DEVELOPMENT.md actualizados)

### Epic 2: Gestión de Cuentas
- CRUD de cuentas (efectivo, banco, tarjeta)
- Moneda por cuenta
- Balance calculado por cuenta
- UI en web y Flutter: pantalla de cuentas, creación, edición

### Epic 3: Registro Manual de Transacciones
- Crear/editar/eliminar gastos, ingresos
- Selección de cuenta, monto, fecha, descripción
- Lista de transacciones paginada con filtros básicos (fecha, cuenta)
- UI en web y Flutter

### Epic 4: Categorías y Etiquetas
- Categorías jerárquicas (categoría + subcategoría)
- Tags libres por transacción
- CRUD de categorías desde UI
- Categorías por defecto pre-cargadas

---

## Etapa 2 — Producto Completo (Semanas 5–8)

**Objetivo:** flujos avanzados, multi-moneda, dashboard, sincronización robusta.

### Epic 5: Transferencias y Multi-moneda
- Transferencias entre cuentas (mismo y distinto currency)
- Integración con API de tasas de cambio (e.g. Frankfurter)
- Conversión automática al registrar transferencias cross-currency
- Vista de balance total en moneda base del usuario

### Epic 6: Búsqueda, Filtros y Organización Avanzada
- Filtros por categoría, cuenta, tag, rango de fecha, monto
- Search index en Convex para búsqueda por descripción
- Vistas guardadas / filtros favoritos

### Epic 7: Dashboard y Analytics
- Resumen de gastos por categoría (gráficos de torta/barra)
- Evolución de gastos en el tiempo (gráfico de línea)
- Balance total y por cuenta
- Componentes reutilizables de charts (recharts en web / fl_chart en Flutter)

### Epic 8: Persistencia Local y Sincronización (Flutter)
- SQLite local con Drift o Isar
- Soporte offline: registrar transacciones sin conexión
- Sync bidireccional con Convex al reconectar
- Manejo de conflictos

---

## Etapa 3 — Asistente de Voz (Semanas 9–12)

**Objetivo:** integración con Gemini Live funcional end-to-end, flujo conversacional completo en web y Flutter.

> **Nota de arquitectura:** se optó por Gemini Live API directamente (WebSocket bidireccional a Google) en lugar de un worker propio. Esto simplifica la arquitectura y elimina la necesidad de manejar infraestructura de audio en servidor.

### Epic 9: Backend de Tools (prerequisito crítico)
- Implementar las internal actions/mutations que ejecutan las tools del agente:
  - `addTransaction` — crea una transacción en Convex
  - `listTransactions` — lista transacciones con filtros
  - `listAccounts` — lista cuentas del usuario
- Autorización: verificar que el usuario solo accede a sus propios datos
- Reemplazar los mocks actuales en `lib/agent-tools/executors.ts` con llamadas reales a Convex

### Epic 10: Integración LLM — Refinamiento
- Evaluación de modelos alternativos si fuera necesario (GPT-4o Realtime, otros)
- Ampliar tool definitions con operaciones adicionales:
  - `getBalance` — balance por cuenta o total
  - `getSummary` — resumen por período y agrupación
  - `addCategory`, `listCategories`
- Mejorar el system prompt con contexto dinámico (cuentas del usuario, categorías disponibles)
- Lógica de confirmación explícita para acciones destructivas o ambiguas

### Epic 11: UI de Voz en Flutter
- Grabación y streaming de audio en tiempo real
- Indicador visual de estado (escuchando / procesando / respondiendo)
- Feedback de texto del asistente en pantalla
- Reproducción de respuesta de audio (TTS del modelo)
- Estados de error y reconexión

### Epic 12: UI de Voz Web — Polish
- Mejorar UX del panel de voz existente (actualmente es un log de eventos crudos)
- Vista de historial de la sesión conversacional
- Confirmaciones inline para acciones ejecutadas por el agente
- Responsividad mobile

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
