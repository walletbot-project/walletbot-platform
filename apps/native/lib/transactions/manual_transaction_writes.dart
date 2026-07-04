import 'package:drift/drift.dart';

import '../database.dart';
import '../tags/tag_writes.dart';
import '../utils/random_ids.dart';

enum ManualTransactionKind { income, expense, transfer }

class ManualTransactionInput {
  const ManualTransactionInput({
    required this.kind,
    required this.name,
    this.description,
    required this.date,
    required this.accountId,
    required this.categoryId,
    required this.amount,
    this.destinationAccountId,
    this.destinationAmount,
    this.exchangeRate,
    this.tags = const [],
  });

  final ManualTransactionKind kind;
  final String name;
  final String? description;
  final DateTime date;
  final String accountId;
  final String categoryId;
  final double amount;
  final String? destinationAccountId;
  final double? destinationAmount;
  final double? exchangeRate;
  final List<LocalTagDraft> tags;
}

BigInt _parseAmountToCents(double value) {
  if (!value.isFinite) {
    throw ArgumentError('Invalid amount');
  }
  return BigInt.from((value * 100).round());
}

Future<String> createManualTransaction(
  AppDatabase db,
  ManualTransactionInput input,
) async {
  final trimmedName = input.name.trim();
  if (trimmedName.isEmpty) {
    throw ArgumentError('Transaction title is required');
  }
  if (input.amount <= 0) {
    throw ArgumentError('Amount must be greater than 0');
  }

  final account =
      await (db.select(db.accounts)..where(
            (t) => t.id.equals(input.accountId) & t.archived.equals(false),
          ))
          .getSingleOrNull();
  if (account == null) {
    throw ArgumentError('Account not found');
  }

  final category =
      await (db.select(db.categories)..where(
            (t) => t.id.equals(input.categoryId) & t.archived.equals(false),
          ))
          .getSingleOrNull();
  if (category == null) {
    throw ArgumentError('Category not found');
  }

  Account? destination;
  BigInt? destinationAmountCents;
  if (input.kind == ManualTransactionKind.transfer) {
    final destinationId = input.destinationAccountId;
    if (destinationId == null || destinationId.isEmpty) {
      throw ArgumentError('Destination account is required');
    }
    if (destinationId == input.accountId) {
      throw ArgumentError('Source and destination accounts must differ');
    }
    destination =
        await (db.select(db.accounts)..where(
              (t) => t.id.equals(destinationId) & t.archived.equals(false),
            ))
            .getSingleOrNull();
    if (destination == null) {
      throw ArgumentError('Destination account not found');
    }

    final sameCurrency = account.currency == destination.currency;
    final destinationAmount = input.destinationAmount ?? input.amount;
    if (!sameCurrency && input.destinationAmount == null) {
      throw ArgumentError(
        'Cross-currency transfers require destination amount',
      );
    }
    if (destinationAmount <= 0) {
      throw ArgumentError('Destination amount must be greater than 0');
    }
    destinationAmountCents = _parseAmountToCents(destinationAmount);
  }

  final id = newUuid();
  final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
  final date = BigInt.from(input.date.millisecondsSinceEpoch);
  final amount = _parseAmountToCents(input.amount);

  await db.transaction(() async {
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: id,
            type: input.kind.name,
            name: trimmedName,
            description: Value(
              input.description?.trim().isEmpty == true
                  ? null
                  : input.description?.trim(),
            ),
            status: 'cleared',
            date: date,
            accountId: account.id,
            categoryId: category.id,
            amount: amount,
            currency: account.currency,
            toAccountId: destination != null
                ? Value(destination.id)
                : const Value.absent(),
            toAmount: destinationAmountCents != null
                ? Value(destinationAmountCents)
                : const Value.absent(),
            toCurrency: destination != null
                ? Value(destination.currency)
                : const Value.absent(),
            exchangeRate: input.exchangeRate != null
                ? Value(input.exchangeRate)
                : const Value.absent(),
            dateConfirmed: const Value(true),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );

    for (final draft in input.tags) {
      final tag = await ensureLocalTag(db, draft);
      await db
          .into(db.transactionTags)
          .insert(
            TransactionTagsCompanion.insert(
              id: '${id}__${tag.id}',
              transactionId: id,
              tagId: tag.id,
              createdAt: now,
              updatedAt: now,
              dirty: const Value(true),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  });

  return id;
}
