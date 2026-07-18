import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/data/data.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

extension BuildContextLocalizations on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  String get localeName => Localizations.localeOf(this).toLanguageTag();
}

extension LocalizedModelLabels on AppLocalizations {
  String txnType(TxnType value) => switch (value) {
    TxnType.expense => expenses,
    TxnType.income => incomes,
    TxnType.transfer => transfers,
    TxnType.balanceAdjustment => balanceAdjustments,
  };

  String txnTypeSingular(TxnType value) => switch (value) {
    TxnType.expense => expense,
    TxnType.income => income,
    TxnType.transfer => transfer,
    TxnType.balanceAdjustment => balanceAdjustment,
  };

  String txnStatus(TxnStatus value) => switch (value) {
    TxnStatus.pending => pending,
    TxnStatus.cleared => cleared,
  };

  String datePreset(DatePreset value) => switch (value) {
    DatePreset.today => today,
    DatePreset.thisWeek => thisWeek,
    DatePreset.thisMonth => thisMonth,
    DatePreset.lastMonth => lastMonth,
    DatePreset.thisYear => thisYear,
  };

  String accountDirection(AccountDirection value) => switch (value) {
    AccountDirection.source => source,
    AccountDirection.destination => destination,
    AccountDirection.either => either,
  };

  String tagMatch(TagMatch value) => switch (value) {
    TagMatch.any => matchAny,
    TagMatch.all => matchAll,
  };

  String dashboardWidgetType(WidgetType value) => switch (value) {
    WidgetType.stat => widgetTypeStat,
    WidgetType.list => widgetTypeList,
    WidgetType.balance => widgetTypeBalance,
    WidgetType.chart => widgetTypeChart,
  };

  String statAggregation(StatAggregation value) => switch (value) {
    StatAggregation.sum => aggregationSum,
    StatAggregation.net => aggregationNet,
    StatAggregation.count => aggregationCount,
  };

  String breakdownGroupBy(BreakdownGroupBy value) => switch (value) {
    BreakdownGroupBy.category => groupCategory,
    BreakdownGroupBy.account => groupAccount,
    BreakdownGroupBy.month => groupMonth,
  };

  String breakdownChartKind(BreakdownChartKind value) => switch (value) {
    BreakdownChartKind.pie => chartPie,
    BreakdownChartKind.bar => chartBar,
    BreakdownChartKind.line => chartLine,
  };

  String dashboardFallbackType(WidgetType? value) => switch (value) {
    WidgetType.stat => valueWidget,
    WidgetType.list => listWidget,
    WidgetType.balance => balanceWidget,
    WidgetType.chart => chartWidget,
    null => widget,
  };

  String dashboardTitle(String value) => switch (value) {
    'Gastos del mes' || 'Monthly expenses' => defaultExpensesMonth,
    'Ingresos del mes' || 'Monthly income' => defaultIncomeMonth,
    'Movimientos del mes' || 'Monthly transactions' => defaultMovementsMonth,
    'Saldo total (ARS)' || 'Total balance (ARS)' => defaultTotalBalanceArs,
    'Movimientos' || 'Transactions' => defaultMovements,
    'Movimientos recientes' || 'Recent transactions' => defaultRecentMovements,
    _ => value,
  };
}

String formatShortDate(DateTime date, String localeName) =>
    DateFormat.MMMd(localeName).format(date);

String formatNumericDate(DateTime date, String localeName) =>
    DateFormat.yMd(localeName).format(date);

String formatWeekday(DateTime date, String localeName) =>
    DateFormat.EEEE(localeName).format(date);

String formatMonthYear(DateTime date, String localeName) =>
    DateFormat.yMMM(localeName).format(date);

String formatDateRange(DateTime start, DateTime end, String localeName) =>
    '${formatNumericDate(start, localeName)} – '
    '${formatNumericDate(end, localeName)}';
