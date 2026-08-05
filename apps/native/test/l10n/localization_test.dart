import 'package:app/data/data.dart';
import 'package:app/l10n/app_localizations_en.dart';
import 'package:app/l10n/app_localizations_es.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/shared/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_US');
    await initializeDateFormatting('es_AR');
  });

  test('English and Spanish localize model-backed labels', () {
    final en = AppLocalizationsEn();
    final es = AppLocalizationsEs();

    expect(en.txnType(TxnType.expense), 'Expenses');
    expect(es.txnType(TxnType.expense), 'Gastos');
    expect(en.datePreset(DatePreset.thisMonth), 'This month');
    expect(es.datePreset(DatePreset.thisMonth), 'Este mes');
  });

  test('Spanish local-account labels describe an on-device account', () {
    final es = AppLocalizationsEs();

    expect(es.localAccount, 'Cuenta local');
    expect(es.withoutAccount, 'Cuenta local');
  });

  test('existing default dashboard titles follow the active locale', () {
    final en = AppLocalizationsEn();
    final es = AppLocalizationsEs();

    expect(en.dashboardTitle('Gastos del mes'), 'Monthly expenses');
    expect(es.dashboardTitle('Monthly expenses'), 'Gastos del mes');
  });

  test('auto-generated transaction names follow the active locale', () {
    final en = AppLocalizationsEn();
    final es = AppLocalizationsEs();

    // The canonical persisted values are the Spanish ones the backend writes.
    expect(en.transactionName('Ajuste de saldo'), 'Balance adjustment');
    expect(es.transactionName('Ajuste de saldo'), 'Ajuste de saldo');
    expect(en.transactionName('Balance inicial'), 'Initial balance');
    expect(es.transactionName('Balance inicial'), 'Balance inicial');

    // User-typed names pass through untouched.
    expect(en.transactionName('Coffee'), 'Coffee');
    expect(es.transactionName('Café'), 'Café');
  });

  test('dates and money use locale-specific separators and ordering', () {
    final date = DateTime(2026, 7, 10);

    expect(formatNumericDate(date, 'en_US'), '7/10/2026');
    expect(formatNumericDate(date, 'es_AR'), '10/7/2026');
    expect(formatMoney(123456, 'USD', locale: 'en_US'), contains('1,234.56'));
    expect(formatMoney(123456, 'USD', locale: 'es_AR'), contains('1.234,56'));
  });
}
