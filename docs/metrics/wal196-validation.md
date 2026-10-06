# WAL-196: validación del dashboard — 2026-10-04 UTC

Validado con `walletbot-metrics-doctor` y credencial de solo lectura. `origin/main` (`593f910`) ya es ancestro de esta rama. Consultas instantáneas con `$model=.*`, `$__range=7d`, `$__interval=1h`; snapshots mensuales con ventana fija de 25 h. No se validó el renderizado en Grafana.

| Scope | Panel | Estado | Series | Valores |
|---|---|---|---:|---|
| production | 1 | success | 1 | 33 |
| production | 3 | success | 0 | sin muestras |
| production | 4 | success | 1 | 0.0274095 |
| production | 7 | success | 1 | 1.2439702500000003 |
| production | 8 | success | 4 | 0.09426225, 0.3204015, 0.025416750000000005, 1.2439702500000003 |
| production | 10 | success | 0 | sin muestras |
| production | 12 | success | 1 | 5 |
| production | 17 | success | 1 | 5 |
| development-3 | 1 | success | 1 | 5 |
| development-3 | 3 | success | 1 | 0.02292825 |
| development-3 | 4 | success | 1 | 0.02292825 |
| development-3 | 7 | success | 0 | sin muestras |
| development-3 | 8 | success | 0 | sin muestras |
| development-3 | 10 | success | 0 | sin muestras |
| development-3 | 12 | success | 1 | 1 |
| development-3 | 17 | success | 1 | 1 |

## Interpretación

- Producción: 4 cuentas remotas representadas en el snapshot mensual; máximo USD 1.24397025. Las series sin `account_scope` se normalizan a `remote`.
- Producción: 5 muestras de costo en 7 días. El máximo por modelo de la última hora está vacío por falta de muestras recientes, no por error de PromQL.
- Development-3: 1 muestra de costo en 7 días; máximo USD 0.02292825. No hay snapshot mensual en las últimas 25 h.
- La búsqueda previa de `account_scope="local"` en 14 días no encontró muestras. En Convex de desarrollo `joyous-grouse-582`, `appUsers` no tenía documentos; los 24 samples recientes y 5 rollups consultados no eran locales. Esta observación no valida la emisión local en un backend desplegado con el PR.
- No se desplegó el backend ni se inyectaron métricas sintéticas. Pasaron los 10 tests de registro, ingestión, deduplicación, agrupación y export local de `localRegistration.test.ts` y `localUsage.test.ts`.
- Pasaron el validador de dashboard (4 filas, 16 paneles) y el formato. El dashboard publicado no se actualizó: su API devolvió HTTP 401 con la credencial disponible. Importar el JSON es un paso separado.
- Los snapshots exportan hasta 20 filas por tipo de cuenta; las sumas por cuenta/instalación pueden ser parciales y no representan facturación total.

## Verificación posterior en desarrollo: flujo local completo

Después de desplegar el backend del PR en `joyous-grouse-582` el 2026-10-04,
se repitió la prueba sobre una cuenta local preexistente y una cuenta creada
con la nueva versión. Las observaciones anteriores describen el estado previo
a ese despliegue; las siguientes completan la validación local pendiente.

| Comprobación | Resultado observado |
|---|---|
| Registro preexistente | Una identidad local, creada remotamente a las 19:43:49 (Argentina) al usar IA |
| Registro de cuenta nueva | Otra identidad local, registrada a las 19:46:19 |
| Relación padre-hijo | Dos `appUserId` diferentes y exactamente un `parentId` compartido |
| Consumo preexistente | 2 muestras / interacciones; USD 0.04632075 |
| Consumo nueva | 1 muestra / interacción; USD 0.02065575 |
| Integridad del padre | Coincide entre el registro, las muestras y los agregados de ambas cuentas |
| Grafana, cuenta preexistente | Snapshot de USD 0.04632075 con `account_scope=local` y hashes de cuenta/padre coincidentes |
| Export del snapshot | `exportStatus=exported`, `exportAttempts=0` |
| Datos financieros | Ninguna fila vinculada a las dos identidades en accounts, transactions, categories, recurrences, tags o transactionTags |

Se ejecutó `telemetry/actions:recordAgentMonthlyUsageNow` en desarrollo para
comprobar el snapshot sin esperar al cron de 6 horas. El snapshot comprobado en
Grafana corresponde a la cuenta preexistente; el consumo de la nueva se verificó
en Convex. No se desplegó producción ni se importó el dashboard publicado.

La auditoría financiera leyó las tablas completas: 10 cuentas financieras,
41 movimientos, 14 categorías, 0 recurrencias, 2 etiquetas y 6 relaciones entre
movimientos y etiquetas; ninguna pertenecía a esas identidades locales. Esto
verifica la ausencia de sincronización financiera en Convex, no implica que el
contexto necesario para usar IA nunca se envíe al proveedor de IA.

### Altas locales, independientes del uso de IA

La consulta siguiente devolvió **2** en `development-3`, en las últimas 24 horas:

```promql
sum(count_over_time(business_user_accounts_created_count_total{deployment_environment="development-3",auth_method="local"}[24h]))
```

En Convex se confirmaron dos eventos de alta exportados, a las 19:24:41 y
19:45:31 (Argentina). El panel existente **Altas de cuenta por método de
autenticación** muestra estos eventos con `auth_method=local`. Cuenta altas
reportadas en el entorno y período, no cuentas activas, instalaciones únicas
ni altas desde una versión determinada. La carga de una cuenta antigua no emite
una nueva alta; su registro posterior en `appUsers` tampoco. Al ser telemetría
best effort, un alta offline cuyo envío falla no queda garantizada en el conteo.

## Consultas ejecutadas

### production, panel 1

```promql
max(last_over_time(business_users_registered_total_count{deployment_environment="production"}[25h]))
```

### production, panel 3

```promql
max by (model, mode) (max_over_time(agent_session_cost_usd{deployment_environment="production",model=~".*"}[1h]))
```

### production, panel 4

```promql
max(max_over_time(agent_session_cost_usd{deployment_environment="production",model=~".*"}[7d]))
```

### production, panel 7

```promql
max by (account_scope) (sum by (account_scope, parent_hash, user_hash, month) (max by (account_scope, parent_hash, user_hash, month, model, mode) (last_over_time(agent_user_monthly_cost_usd{deployment_environment="production",model=~".*",account_scope=~"local|remote"}[25h]) or label_replace(last_over_time(agent_user_monthly_cost_usd{deployment_environment="production",model=~".*",account_scope=""}[25h]), "account_scope", "remote", "user_hash", ".*"))))
```

### production, panel 8

```promql
sum by (account_scope, parent_hash, user_hash, month) (max by (account_scope, parent_hash, user_hash, month, model, mode) (last_over_time(agent_user_monthly_cost_usd{deployment_environment="production",model=~".*",account_scope=~"local|remote"}[25h]) or label_replace(last_over_time(agent_user_monthly_cost_usd{deployment_environment="production",model=~".*",account_scope=""}[25h]), "account_scope", "remote", "user_hash", ".*")))
```

### production, panel 10

```promql
sum by (parent_hash, month) (max by (parent_hash, user_hash, month, model, mode) (last_over_time(agent_user_monthly_cost_usd{deployment_environment="production",model=~".*",account_scope="local"}[25h])))
```

### production, panel 12

```promql
sum by (cost_bucket) (count_over_time(agent_session_cost_bucket_count_total{deployment_environment="production",model=~".*"}[7d]))
```

### production, panel 17

```promql
sum(count_over_time(agent_session_cost_bucket_count_total{deployment_environment="production",model=~".*"}[7d]))
```

### development-3, panel 1

```promql
max(last_over_time(business_users_registered_total_count{deployment_environment="development-3"}[25h]))
```

### development-3, panel 3

```promql
max by (model, mode) (max_over_time(agent_session_cost_usd{deployment_environment="development-3",model=~".*"}[1h]))
```

### development-3, panel 4

```promql
max(max_over_time(agent_session_cost_usd{deployment_environment="development-3",model=~".*"}[7d]))
```

### development-3, panel 7

```promql
max by (account_scope) (sum by (account_scope, parent_hash, user_hash, month) (max by (account_scope, parent_hash, user_hash, month, model, mode) (last_over_time(agent_user_monthly_cost_usd{deployment_environment="development-3",model=~".*",account_scope=~"local|remote"}[25h]) or label_replace(last_over_time(agent_user_monthly_cost_usd{deployment_environment="development-3",model=~".*",account_scope=""}[25h]), "account_scope", "remote", "user_hash", ".*"))))
```

### development-3, panel 8

```promql
sum by (account_scope, parent_hash, user_hash, month) (max by (account_scope, parent_hash, user_hash, month, model, mode) (last_over_time(agent_user_monthly_cost_usd{deployment_environment="development-3",model=~".*",account_scope=~"local|remote"}[25h]) or label_replace(last_over_time(agent_user_monthly_cost_usd{deployment_environment="development-3",model=~".*",account_scope=""}[25h]), "account_scope", "remote", "user_hash", ".*")))
```

### development-3, panel 10

```promql
sum by (parent_hash, month) (max by (parent_hash, user_hash, month, model, mode) (last_over_time(agent_user_monthly_cost_usd{deployment_environment="development-3",model=~".*",account_scope="local"}[25h])))
```

### development-3, panel 12

```promql
sum by (cost_bucket) (count_over_time(agent_session_cost_bucket_count_total{deployment_environment="development-3",model=~".*"}[7d]))
```

### development-3, panel 17

```promql
sum(count_over_time(agent_session_cost_bucket_count_total{deployment_environment="development-3",model=~".*"}[7d]))
```
