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
    WidgetType.balanceComparison => widgetTypeBalanceComparison,
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
    WidgetType.balanceComparison => widgetTypeBalanceComparison,
    null => widget,
  };

  /// Localizes the auto-generated names the app (and the backend) persist for
  /// balance-adjustment transactions. The stored value is a fixed cross-platform
  /// constant — `packages/backend/convex/v1/transactions/mutations.ts` writes
  /// `Ajuste de saldo` too — so it is mapped at render time rather than at write
  /// time. That keeps the synced wire value stable and localizes rows that were
  /// already persisted. User-typed names pass through untouched.
  ///
  /// [type] is the transaction's wire type ([TxnType.wire], the `type` column on
  /// `Transaction`). Only balance adjustments carry generated names, so every
  /// other type passes through verbatim: an expense a user literally named
  /// `Initial balance` keeps that name when the locale changes.
  ///
  /// Display only: never feed this through an editable field, or saving would
  /// persist the localized copy in place of the canonical name.
  String transactionName(String value, String type) {
    if (type != TxnType.balanceAdjustment.wire) return value;
    return switch (value) {
      'Ajuste de saldo' || 'Balance adjustment' => balanceAdjustment,
      'Balance inicial' || 'Initial balance' => initialBalance,
      _ => value,
    };
  }

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
