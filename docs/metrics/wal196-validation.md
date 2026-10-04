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
