import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/account_icons.dart';
import '../components/category_icons.dart';
import '../components/color_utils.dart';
import '../components/transaction_row.dart';
import '../data/data.dart';
import '../data/queries/stream_utils.dart';
import '../database.dart';
import '../l10n/l10n.dart';

/// The upcoming side of Activity: the movements that exist but have not
/// happened yet.
///
/// There is nothing special about the rows — they are ordinary transactions
/// whose date sits past the occurrence cutoff (`lib/data/occurrence.dart`),
/// which is exactly why every read on the other side of that cutoff has to
/// exclude them. The user is never told a filter is involved; there are simply
/// two lists, one behind and one ahead.
///
/// Runs ascending, unlike Activity: the soonest movement is the interesting
/// one. Read-only for now — editing or deleting an occurrence has to say
/// whether it means this one or this one and the ones after it, and "the ones
/// after it" needs the recurrence rule that materialised them.
class FutureMovementsScreen extends StatefulWidget {
  const FutureMovementsScreen({super.key});

  @override
  State<FutureMovementsScreen> createState() => _FutureMovementsScreenState();
}

typedef _Payload = ({
  List<Transaction> movements,
  Map<String, Account> accountsById,
  Map<String, Category> categoriesById,
});

class _FutureMovementsScreenState extends State<FutureMovementsScreen> {
  late final Stream<_Payload> _stream;

  @override
  void initState() {
    super.initState();
    final repos = context.read<AppRepositories>();
    final entities = combineLatest2(
      repos.accounts.watchAll(includeArchived: true),
      repos.categories.watchAll(includeArchived: true),
      (List<Account> accounts, List<Category> categories) => (
        accountsById: {for (final a in accounts) a.id: a},
        categoriesById: {for (final c in categories) c.id: c},
      ),
    );
    _stream = combineLatest2(
      repos.transactions.watchUpcoming(),
      entities,
      (List<Transaction> movements, entityMaps) => (
        movements: movements,
        accountsById: entityMaps.accountsById,
        categoriesById: entityMaps.categoriesById,
      ),
    );
  }

  /// Ascending day sections. Activity labels the recent past ("today",
  /// "yesterday", a weekday); here every day is ahead, so a weekday name is
  /// only unambiguous within the coming week.
  String _sectionLabel(BuildContext context, DateTime day, DateTime today) {
    final diff = day.difference(today).inDays;
    if (diff == 0) return context.l10n.today;
    if (diff > 0 && diff < 7) return formatWeekday(day, context.localeName);
    return formatNumericDate(day, context.localeName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.futureMovements)),
      body: StreamBuilder<_Payload>(
        stream: _stream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final payload = snapshot.requireData;
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 80),
            children: [
              _InfoBanner(text: context.l10n.futureMovementsInfo),
              const SizedBox(height: 16),
              if (payload.movements.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 48,
                  ),
                  child: Text(
                    context.l10n.noFutureMovements,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ..._buildEntries(context, payload, today),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildEntries(
    BuildContext context,
    _Payload payload,
    DateTime today,
  ) {
    final widgets = <Widget>[];
    DateTime? currentDay;
    for (final txn in payload.movements) {
      final date = DateTime.fromMillisecondsSinceEpoch(txn.date.toInt());
      final day = DateTime(date.year, date.month, date.day);
      if (currentDay == null || day != currentDay) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: currentDay == null ? 0 : 16,
              bottom: 8,
            ),
            child: Text(
              _sectionLabel(context, day, today),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        );
        currentDay = day;
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TransactionRow(
            title: context.l10n.transactionName(txn.name, txn.type),
            amountCents: _signedCents(txn),
            currency: txn.currency,
            dateCheck: txn.dateConfirmed,
            description: txn.description,
            visualIdentities: _visualIdentitiesFor(context, txn, payload),
            onTap: () => _openDetail(txn, payload),
          ),
        ),
      );
    }
    return widgets;
  }

  int _signedCents(Transaction txn) {
    final amount = txn.amount.toInt();
    return switch (txn.type) {
      'expense' || 'transfer' => -amount.abs(),
      _ => amount.abs(),
    };
  }

  List<TransactionRowVisualIdentity> _visualIdentitiesFor(
    BuildContext context,
    Transaction txn,
    _Payload payload,
  ) {
    final identities = <TransactionRowVisualIdentity>[];
    final account = payload.accountsById[txn.accountId];
    if (account != null) {
      identities.add(
        TransactionRowVisualIdentity(
          type: TransactionRowVisualIdentityType.account,
          label: '${context.l10n.account}: ${account.name}',
          icon: accountIconFromName(account.icon),
          color: colorFromHex(account.color, fallback: accountDefaultColor),
        ),
      );
    }
    final category = payload.categoriesById[txn.categoryId];
    if (category != null) {
      identities.add(
        TransactionRowVisualIdentity(
          type: TransactionRowVisualIdentityType.category,
          label: '${context.l10n.category}: ${category.name}',
          icon: categoryIconFromName(category.icon),
          color: colorFromHex(category.color, fallback: categoryDefaultColor),
        ),
      );
    }
    return identities;
  }

  void _openDetail(Transaction txn, _Payload payload) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _FutureMovementDetailScreen(
          movement: txn,
          account: payload.accountsById[txn.accountId],
          category: payload.categoriesById[txn.categoryId],
        ),
      ),
    );
  }
}

/// One upcoming movement, read-only. Mirrors the web detail's receipt rows.
class _FutureMovementDetailScreen extends StatelessWidget {
  const _FutureMovementDetailScreen({
    required this.movement,
    required this.account,
    required this.category,
  });

  final Transaction movement;
  final Account? account;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final date = DateTime.fromMillisecondsSinceEpoch(movement.date.toInt());
    final description = movement.description;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.futureMovements)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Text(
              context.l10n.transactionName(movement.name, movement.type),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 24),
          _DetailRow(
            icon: Icons.calendar_month_rounded,
            label: context.l10n.date,
            value: formatNumericDate(date, context.localeName),
          ),
          _DetailRow(
            icon: Icons.schedule_outlined,
            label: context.l10n.time,
            value: MaterialLocalizations.of(
              context,
            ).formatTimeOfDay(TimeOfDay.fromDateTime(date)),
          ),
          _DetailRow(
            icon: Icons.account_balance_rounded,
            label: context.l10n.account,
            value: account?.name ?? '—',
          ),
          _DetailRow(
            icon: Icons.sell_rounded,
            label: context.l10n.category,
            value: category?.name ?? '—',
          ),
          _DetailRow(
            icon: Icons.notes_rounded,
            label: context.l10n.description,
            value: description == null || description.isEmpty
                ? context.l10n.noDescription
                : description,
            muted: description == null || description.isEmpty,
          ),
          const SizedBox(height: 8),
          Divider(color: colorScheme.outlineVariant),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: muted ? colorScheme.onSurfaceVariant : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // Theme tokens rather than the demo's fixed teal wash, which was unreadable
    // in dark mode. `secondaryContainer` is the scheme's informational surface
    // and carries its matching foreground in both brightnesses.
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
