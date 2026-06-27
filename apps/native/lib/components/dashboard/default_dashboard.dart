import 'dart:convert';

import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/data/data.dart';

/// Writes the default v1 dashboard (saved filters + widgets) for a brand-new
/// user. Passed to `DashboardRepository.seedDefaultIfEmpty`, which runs it once
/// per device behind the empty-table + `dashboardSeeded` guard.
///
/// All rows use **deterministic ids** so two fresh devices seeding the same new
/// account concurrently produce identical rows — last-writer-wins merge then
/// converges instead of duplicating the layout.
///
/// NOTE: the monetary tiles are scoped to `ARS` — the app's de-facto default
/// currency (`screens/create_account.dart`). Placeholder until the currency
/// scope is user-driven; sums for users without ARS transactions read as 0.
Future<void> writeDefaultDashboardSeed(AppRepositories repos) async {
  const expenseFilterId = 'seed-flt-gastos-mes';
  const incomeFilterId = 'seed-flt-ingresos-mes';
  const monthFilterId = 'seed-flt-movimientos-mes';

  Future<void> seedFilter(String id, String name, TransactionFilter filter) =>
      repos.savedFilters.create(
        id: id,
        name: name,
        config: jsonEncode(filter.toCanonicalJson()),
      );

  await seedFilter(
    expenseFilterId,
    'Gastos del mes',
    const TransactionFilter(
      types: {TxnType.expense},
      datePreset: DatePreset.thisMonth,
      currency: 'ARS',
    ),
  );
  await seedFilter(
    incomeFilterId,
    'Ingresos del mes',
    const TransactionFilter(
      types: {TxnType.income},
      datePreset: DatePreset.thisMonth,
      currency: 'ARS',
    ),
  );
  await seedFilter(
    monthFilterId,
    'Movimientos del mes',
    const TransactionFilter(datePreset: DatePreset.thisMonth),
  );

  Future<void> seedWidget({
    required String id,
    required WidgetType type,
    required int position,
    required DashboardWidth width,
    required Map<String, Object?> options,
    String? filterId,
  }) => repos.dashboard.create(
    id: id,
    type: type.wire,
    filterId: filterId,
    position: position,
    width: width.wire,
    options: encodeWidgetOptions(options),
  );

  await seedWidget(
    id: 'seed-wgt-saldo',
    type: WidgetType.balance,
    position: 0,
    width: DashboardWidth.full,
    options: {'title': 'Saldo total (ARS)', 'currency': 'ARS'},
  );
  await seedWidget(
    id: 'seed-wgt-gastos',
    type: WidgetType.stat,
    filterId: expenseFilterId,
    position: 1,
    width: DashboardWidth.third,
    options: {'title': 'Gastos del mes', 'aggregation': 'sum'},
  );
  await seedWidget(
    id: 'seed-wgt-ingresos',
    type: WidgetType.stat,
    filterId: incomeFilterId,
    position: 2,
    width: DashboardWidth.third,
    options: {'title': 'Ingresos del mes', 'aggregation': 'sum'},
  );
  await seedWidget(
    id: 'seed-wgt-movimientos',
    type: WidgetType.stat,
    filterId: monthFilterId,
    position: 3,
    width: DashboardWidth.third,
    options: {'title': 'Movimientos', 'aggregation': 'count'},
  );
  await seedWidget(
    id: 'seed-wgt-recientes',
    type: WidgetType.list,
    position: 4,
    width: DashboardWidth.full,
    options: {'title': 'Movimientos recientes', 'limit': 5},
  );
}
