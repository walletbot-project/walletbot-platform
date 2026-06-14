import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/data/data.dart';

/// The hard-coded v1 dashboard (Phase 1 — no editing/persistence yet). Once
/// saved filters + the `dashboardWidgets` table land (Phase 3), this becomes
/// the seed for a new user's layout instead of the rendered source.
///
/// NOTE: the monetary tiles are scoped to `ARS` — the app's de-facto default
/// currency (`screens/create_account.dart`). This is a placeholder until the
/// currency scope is user-driven; sums for users without ARS transactions read
/// as 0.
const List<DashboardWidgetSpec> defaultDashboardWidgets = [
  BalanceCardWidgetSpec(
    title: 'Saldo total (ARS)',
    currency: 'ARS',
    width: DashboardWidth.full,
  ),
  StatWidgetSpec(
    title: 'Gastos del mes',
    aggregation: StatAggregation.sum,
    filter: TransactionFilter(
      types: {TxnType.expense},
      datePreset: DatePreset.thisMonth,
      currency: 'ARS',
    ),
  ),
  StatWidgetSpec(
    title: 'Ingresos del mes',
    aggregation: StatAggregation.sum,
    filter: TransactionFilter(
      types: {TxnType.income},
      datePreset: DatePreset.thisMonth,
      currency: 'ARS',
    ),
  ),
  StatWidgetSpec(
    title: 'Movimientos',
    aggregation: StatAggregation.count,
    filter: TransactionFilter(datePreset: DatePreset.thisMonth),
  ),
  TransactionListWidgetSpec(
    title: 'Movimientos recientes',
    filter: TransactionFilter(),
    limit: 5,
  ),
];
