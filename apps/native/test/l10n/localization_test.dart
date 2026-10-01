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

  test('Spanish auth email-flow copy keeps the voseo tone', () {
    final es = AppLocalizationsEs();

    expect(es.forgotPassword, '¿Olvidaste tu contraseña?');
    expect(es.verifyEmailTitle, 'Verificá tu correo');
    expect(es.verifyEmailDone, 'Ya verifiqué');
    expect(es.backToSignIn, 'Volver a iniciar sesión');
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
    const adjustment = 'balance_adjustment';

    // The canonical persisted values are the Spanish ones the backend writes.
    expect(
      en.transactionName('Ajuste de saldo', adjustment),
      'Balance adjustment',
    );
    expect(
      es.transactionName('Ajuste de saldo', adjustment),
      'Ajuste de saldo',
    );
    expect(
      en.transactionName('Balance inicial', adjustment),
      'Initial balance',
    );
    expect(
      es.transactionName('Balance inicial', adjustment),
      'Balance inicial',
    );

    // User-typed names pass through untouched.
    expect(en.transactionName('Coffee', adjustment), 'Coffee');
    expect(es.transactionName('Café', adjustment), 'Café');
  });

  test('only balance adjustments have their name localized', () {
    final en = AppLocalizationsEn();
    final es = AppLocalizationsEs();

    // A user-entered name that collides with a generated one is never
    // rewritten, because non-adjustment types carry no generated names.
    for (final type in const ['expense', 'income', 'transfer']) {
      expect(en.transactionName('Ajuste de saldo', type), 'Ajuste de saldo');
      expect(es.transactionName('Initial balance', type), 'Initial balance');
      expect(en.transactionName('Balance inicial', type), 'Balance inicial');
      expect(
        es.transactionName('Balance adjustment', type),
        'Balance adjustment',
      );
    }
  });

  test('the Activity detail speaks both languages', () {
    final en = AppLocalizationsEn();
    final es = AppLocalizationsEs();

    // This receipt was hardcoded Spanish until WAL-174. Asserting the pairs
    // differ catches the usual regression: a key added to `app_es.arb` and
    // copied verbatim into `app_en.arb`.
    final pairs = <String, String>{
      en.detail: es.detail,
      en.editActivity: es.editActivity,
      en.activityGone: es.activityGone,
      en.estimatedDate: es.estimatedDate,
      en.estimatedTime: es.estimatedTime,
      en.sourceAccount: es.sourceAccount,
      en.destinationAccount: es.destinationAccount,
      en.noCategory: es.noCategory,
      en.noTags: es.noTags,
      en.balanceUnavailable: es.balanceUnavailable,
      en.change: es.change,
      en.invalidAmount: es.invalidAmount,
      en.noOtherAccount: es.noOtherAccount,
      en.amountNotEditable: es.amountNotEditable,
      en.activityUpdateFailed: es.activityUpdateFailed,
      en.activityDeleteTitle: es.activityDeleteTitle,
      en.activityDeleteFailed: es.activityDeleteFailed,
    };
    for (final entry in pairs.entries) {
      expect(entry.key, isNot(entry.value), reason: entry.key);
    }

    expect(en.activityDeleteConfirm('Rent'), contains('Rent'));
    expect(es.activityDeleteConfirm('Alquiler'), contains('Alquiler'));

    // The identity chips carried the label inline, accent and all — the
    // Spanish one was even spelled "Categoria".
    expect(en.accountIdentity('Cash'), 'Account: Cash');
    expect(es.accountIdentity('Efectivo'), 'Cuenta: Efectivo');
    expect(es.categoryIdentity('Comida'), 'Categoría: Comida');
  });

  test('dates and money use locale-specific separators and ordering', () {
    final date = DateTime(2026, 7, 10);

    expect(formatNumericDate(date, 'en_US'), '7/10/2026');
    expect(formatNumericDate(date, 'es_AR'), '10/7/2026');
    expect(formatMoney(123456, 'USD', locale: 'en_US'), contains('1,234.56'));
    expect(formatMoney(123456, 'USD', locale: 'es_AR'), contains('1.234,56'));
  });
}
