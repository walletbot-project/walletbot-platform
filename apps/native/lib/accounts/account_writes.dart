import '../database.dart';
import '../utils/random_ids.dart';

String _normalizeAccountName(String value) => value.trim().toLowerCase();

Future<Account> createLocalAccount(
  AppDatabase db, {
  required String name,
  required String currency,
}) async {
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) {
    throw ArgumentError('Account name is required');
  }

  final existing = await (db.select(
    db.accounts,
  )..where((t) => t.archived.equals(false))).get();
  final normalizedName = _normalizeAccountName(trimmedName);
  for (final account in existing) {
    if (_normalizeAccountName(account.name) == normalizedName &&
        account.currency == currency) {
      throw ArgumentError('Account with that name and currency already exists');
    }
  }

  final id = newUuid();
  await db.insertAccount(id: id, name: trimmedName, currency: currency);
  return (db.select(db.accounts)..where((t) => t.id.equals(id))).getSingle();
}
