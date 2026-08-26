/// Money helpers shared by UI formatting and agent serialization.
/// Amounts are stored as int64 cents (BigInt) in the database.
library;

import 'package:intl/intl.dart';

/// Prefix for an ISO currency: symbol for EUR/GBP, ISO code otherwise (USD, ARS).
String currencyPrefix(String code) => switch (code) {
  'EUR' => '€',
  'GBP' => '£',
  _ => '$code ',
};

/// Formats signed cents as currency using the active UI locale.
String formatMoney(
  int cents,
  String currency, {
  String? locale,
  int decimalDigits = 2,
}) {
  return NumberFormat.currency(
    locale: locale,
    symbol: currencyPrefix(currency),
    decimalDigits: decimalDigits,
  ).format(cents / 100);
}

/// Converts a decimal user-facing amount to int64 cents as BigInt.
/// `12.5` → `1250`, `-3.07` → `-307`. Throws on NaN / infinity.
BigInt parseAmountToCents(num amount) {
  final value = amount.toDouble();
  if (value.isNaN || value.isInfinite) {
    throw FormatException('Invalid amount: $amount');
  }
  final cents = (value * 100).round();
  return BigInt.from(cents);
}

/// Cents → decimal double, the wire shape the agent protocol uses.
double centsToDouble(BigInt cents) => cents.toDouble() / 100;

/// Signed cents for display, by transaction type: expense is negative,
/// income / incoming transfer positive, balance adjustment as stored. Matches
/// [TransactionRow]'s color convention (positive → green). Shared by the
/// activity list and the dashboard transaction-list widget so the displayed
/// sign can never diverge between them.
int signedDisplayCents(String type, BigInt amount) {
  switch (type) {
    case 'expense':
      return -amount.abs().toInt();
    case 'income':
    case 'transfer':
      return amount.abs().toInt();
    case 'balance_adjustment':
      return amount.toInt();
    default:
      return amount.toInt();
  }
}

/// Formats absolute cents with thousands grouping: `123456` → `1,234.56`.
/// Sign and currency-symbol layout are the caller's concern (the transaction
/// row and the summary card place them differently).
String formatCentsUnsigned(int absCents, {String? locale}) =>
    NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 2,
    ).format(absCents / 100);

/// Formats a cross-currency exchange rate (a plain ratio, always >= 1) with
/// thousands grouping and 2 decimals: `1350.0` → `1,350.00`. Unlike the cents
/// helpers, the input is not divided by 100 — it is already a ratio.
String formatExchangeRate(double rate, {String? locale}) =>
    NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 2,
    ).format(rate);
