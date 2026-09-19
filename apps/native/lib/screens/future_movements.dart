import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/account_icons.dart';
import '../components/category_icons.dart';
import '../components/color_utils.dart';
import '../components/recurrence_summary.dart';
import '../components/transaction_row.dart';
import '../data/data.dart';
import '../data/queries/stream_utils.dart';
import '../data/recurrence.dart';
import '../database.dart';
import '../l10n/l10n.dart';
import '../shared/money.dart';

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
/// one. An open-ended series can be topped up from a movement's detail;
/// editing and deleting are still absent, because either one has to say
/// whether it means this occurrence or this one and the ones after it.
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
          label: context.l10n.accountIdentity(account.name),
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
          label: context.l10n.categoryIdentity(category.name),
          icon: categoryIconFromName(category.icon),
          color: colorFromHex(category.color, fallback: categoryDefaultColor),
        ),
      );
    }
    return identities;
  }

  void _openDetail(Transaction txn, _Payload payload) {
    // A pushed route sits above the account-scoped providers, so the
    // repositories have to be re-provided (the same instance) for the detail
    // to read the recurrence rule — see `_openManualAdd` in the home screen.
    final repos = context.read<AppRepositories>();
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Provider<AppRepositories>.value(
          value: repos,
          child: _FutureMovementDetailScreen(
            movement: txn,
            accounts: payload.accountsById,
            categories: payload.categoriesById,
          ),
        ),
      ),
    );
  }
}

/// One upcoming movement. Mirrors the web detail's receipt rows, plus the
/// top-up button for an open-ended series.
/// Signed cents: what the row shows and what its colour is picked from. An
/// expense leaves the account, so it reads negative.
int _signedCents(Transaction txn) {
  final amount = txn.amount.toInt();
  return switch (txn.type) {
    'expense' || 'transfer' => -amount.abs(),
    _ => amount.abs(),
  };
}

/// Which occurrences an edit or a delete applies to.
enum _RecurrenceScope { onlyThis, allFuture }

/// One upcoming movement. Mirrors the web detail's receipt rows, plus the
/// top-up button for an open-ended series.
///
/// Editing and deleting both ask the question a series forces: this
/// occurrence, or this one and the ones after it. Nothing is written until
/// that is answered — the scope is not a default the user can miss.
class _FutureMovementDetailScreen extends StatefulWidget {
  const _FutureMovementDetailScreen({
    required this.movement,
    required this.accounts,
    required this.categories,
  });

  final Transaction movement;
  final Map<String, Account> accounts;
  final Map<String, Category> categories;

  @override
  State<_FutureMovementDetailScreen> createState() =>
      _FutureMovementDetailScreenState();
}

class _FutureMovementDetailScreenState
    extends State<_FutureMovementDetailScreen> {
  late final Stream<RecurrenceSeries?> _series;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late DateTime _date;
  late String _accountId;
  late String _categoryId;

  /// Null until the user picks one: the stored cadence arrives with the
  /// series stream, not with the movement, so it is resolved at read time
  /// rather than copied into state during a build.
  RecurrenceFrequency? _frequency;
  int? _dayInterval;

  bool _editing = false;
  bool _busy = false;

  /// The movement as it stands, so an edit the user saved is reflected without
  /// having to pop back to the list. Null once it has been deleted.
  Transaction? _current;

  @override
  void initState() {
    super.initState();
    final movement = widget.movement;
    _current = movement;
    _series = context.read<AppRepositories>().transactions.watchSeries(
      movement.recurrenceId,
      occurrenceIndex: movement.recurrenceIndex,
    );
    _name = TextEditingController(text: movement.name);
    _description = TextEditingController(text: movement.description ?? '');
    _amount = TextEditingController(
      text: (movement.amount.toInt().abs() / 100).toStringAsFixed(2),
    );
    _date = DateTime.fromMillisecondsSinceEpoch(movement.date.toInt());
    _accountId = movement.accountId;
    _categoryId = movement.categoryId;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  /// Reports the count the *write* returned, not the one the button offered:
  /// the two only differ if the rule changed underneath, and in that case the
  /// write is the one telling the truth.
  Future<void> _addMore(String recurrenceId) async {
    setState(() => _busy = true);
    final l10n = context.l10n;
    _snack(l10n.addingMoreMovements);
    try {
      final added = await context
          .read<AppRepositories>()
          .transactions
          .addOccurrences(recurrenceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      // Zero means the rule stopped being extendable while we were asking —
      // deleted, or given an end date on another device. Nothing was written,
      // so say so rather than reporting a successful nothing.
      _snack(
        added == 0
            ? l10n.addMoreMovementsFailed
            : l10n.addedMoreMovements(added),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      _snack(l10n.addMoreMovementsFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The scope question. Returns null when the user backs out.
  ///
  /// [cadenceChanged] disables "this one only": a change of cadence cannot be
  /// confined to a single occurrence, because every later date is projected
  /// from the anchor.
  Future<_RecurrenceScope?> _askScope({
    required bool deleting,
    bool cadenceChanged = false,
  }) {
    final l10n = context.l10n;
    return showDialog<_RecurrenceScope>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(deleting ? l10n.deleteRecurring : l10n.editMovement),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              deleting
                  ? l10n.scopeDeleteDescription(
                      l10n.transactionName(
                        widget.movement.name,
                        widget.movement.type,
                      ),
                    )
                  : l10n.scopeEditDescription,
            ),
            if (cadenceChanged) ...[
              const SizedBox(height: 12),
              Text(
                l10n.scopeOnlyThisUnavailable,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        // Dismissive first, then the two scopes — the same order web uses, so
        // the muscle memory carries between platforms. A destructive choice
        // only recolours its label, per Material.
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            style: deleting ? _destructiveButtonStyle(context) : null,
            onPressed: cadenceChanged
                ? null
                : () => Navigator.of(context).pop(_RecurrenceScope.onlyThis),
            child: Text(l10n.scopeOnlyThis),
          ),
          TextButton(
            style: deleting ? _destructiveButtonStyle(context) : null,
            onPressed: () =>
                Navigator.of(context).pop(_RecurrenceScope.allFuture),
            child: Text(l10n.scopeAllFuture),
          ),
        ],
      ),
    );
  }

  ButtonStyle _destructiveButtonStyle(BuildContext context) =>
      TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 5),
      lastDate: DateTime(_date.year + 20),
    );
    if (picked == null) return;
    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (picked == null) return;
    setState(() {
      _date = DateTime(
        _date.year,
        _date.month,
        _date.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  /// The cadence on screen: what the user picked, else what the rule stores.
  RecurrenceFrequency? _effectiveFrequency(RecurrenceSeries? series) =>
      _frequency ??
      (series == null
          ? null
          : recurrenceFrequencyFromName(series.rule.frequency));

  int _effectiveDayInterval(RecurrenceSeries? series) =>
      _dayInterval ?? series?.rule.dayInterval ?? 15;

  /// The edited values, or null when they do not add up.
  ({String name, String? description, BigInt amount})? _validated() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack(context.l10n.titleRequired);
      return null;
    }
    final parsed = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) {
      _snack(context.l10n.amountGreaterThanZero);
      return null;
    }
    final description = _description.text.trim();
    return (
      name: name,
      description: description.isEmpty ? null : description,
      amount: BigInt.from((parsed * 100).round()),
    );
  }

  Future<void> _save(RecurrenceSeries? series) async {
    final movement = _current;
    if (movement == null) return;
    final valid = _validated();
    if (valid == null) return;

    // A one-off future movement has no series to scope over, so there is no
    // question to ask: both answers would mean the same thing.
    final scoped = movement.recurrenceId != null;

    final storedFrequency = series == null
        ? null
        : recurrenceFrequencyFromName(series.rule.frequency);
    final frequency = _effectiveFrequency(series);
    final dayInterval = _effectiveDayInterval(series);
    final cadenceChanged =
        series != null &&
        (frequency != storedFrequency ||
            (frequency == RecurrenceFrequency.customDays &&
                dayInterval != (series.rule.dayInterval ?? 0)));
    final anchorChanged =
        BigInt.from(_date.millisecondsSinceEpoch) != movement.date;

    final scope = scoped
        ? await _askScope(deleting: false, cadenceChanged: cadenceChanged)
        : _RecurrenceScope.onlyThis;
    if (scope == null || !mounted) return;

    setState(() => _busy = true);
    final l10n = context.l10n;
    final repos = context.read<AppRepositories>();
    final account = widget.accounts[_accountId];
    try {
      if (scope == _RecurrenceScope.allFuture &&
          (cadenceChanged || anchorChanged)) {
        // Re-cadencing or re-anchoring the tail is a split, not an update:
        // the occurrences before this one keep their own spacing.
        await repos.transactions.splitSeries(
          movement.id,
          frequency: frequency ?? storedFrequency!,
          dayInterval: dayInterval,
          date: BigInt.from(_date.millisecondsSinceEpoch),
          dateConfirmed: true,
          timeStatus: TransactionTimeStatus.confirmed,
          name: valid.name,
          description: valid.description,
          amountCents: valid.amount,
          accountId: _accountId,
          currency: account?.currency ?? movement.currency,
          categoryId: _categoryId,
        );
        if (!mounted) return;
        _snack(l10n.savedAllFuture);
        Navigator.of(context).pop();
        return;
      }

      if (scope == _RecurrenceScope.allFuture) {
        await repos.transactions.updateFuture(
          movement.id,
          name: Value(valid.name),
          description: Value(valid.description),
          amount: Value(valid.amount),
          accountId: Value(_accountId),
          currency: Value(account?.currency ?? movement.currency),
          categoryId: Value(_categoryId),
        );
      } else {
        await repos.transactions.update(
          movement.id,
          name: Value(valid.name),
          description: Value(valid.description),
          amount: Value(valid.amount),
          accountId: Value(_accountId),
          currency: Value(account?.currency ?? movement.currency),
          categoryId: Value(_categoryId),
          date: Value(BigInt.from(_date.millisecondsSinceEpoch)),
          dateConfirmed: const Value(true),
          timeStatus: const Value(TransactionTimeStatus.confirmed),
        );
      }
      final refreshed = await repos.transactions.getById(movement.id);
      if (!mounted) return;
      setState(() {
        _current = refreshed;
        _editing = false;
      });
      _snack(
        scope == _RecurrenceScope.onlyThis
            ? l10n.savedOnlyThis
            : l10n.savedAllFuture,
      );
    } catch (_) {
      if (mounted) _snack(l10n.activityUpdateFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final movement = _current;
    if (movement == null) return;
    // Same as saving: with no series behind it, "this one" and "this and the
    // ones after it" are the same movement.
    final scope = movement.recurrenceId != null
        ? await _askScope(deleting: true)
        : _RecurrenceScope.onlyThis;
    if (scope == null || !mounted) return;

    setState(() => _busy = true);
    final l10n = context.l10n;
    final repos = context.read<AppRepositories>();
    try {
      if (scope == _RecurrenceScope.allFuture) {
        await repos.transactions.deleteFuture(movement.id);
      } else {
        await repos.transactions.delete(movement.id);
      }
      if (!mounted) return;
      _snack(
        scope == _RecurrenceScope.onlyThis
            ? l10n.deletedOnlyThis
            : l10n.deletedAllFuture,
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(l10n.activityDeleteFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final movement = _current ?? widget.movement;

    // One StreamBuilder for the whole body, not one per consumer: the series
    // stream is single-subscription (`combineLatest2`), so a second listener
    // throws "Stream has already been listened to".
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? context.l10n.editMovement : context.l10n.detail),
        actions: [
          if (!_editing)
            IconButton(
              tooltip: context.l10n.edit,
              onPressed: _busy ? null : () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_outlined),
            ),
          IconButton(
            tooltip: context.l10n.delete,
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<RecurrenceSeries?>(
          stream: _series,
          builder: (context, snapshot) {
            final series = snapshot.data;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: _editing
                  ? _editFields(context, movement, series)
                  : _readRows(context, movement, series),
            );
          },
        ),
      ),
    );
  }

  /// The receipt: label and value on one line, right-aligned.
  List<Widget> _readRows(
    BuildContext context,
    Transaction movement,
    RecurrenceSeries? series,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final date = DateTime.fromMillisecondsSinceEpoch(movement.date.toInt());
    final description = movement.description;
    final signedCents = _signedCents(movement);
    return [
      Center(
        child: Column(
          children: [
            Text(
              context.l10n.transactionName(movement.name, movement.type),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              formatMoney(signedCents, movement.currency),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                // The same green the rest of the app gives an inflow
                // (`TransactionRow`, the Activity detail, the summary card).
                color: signedCents > 0
                    ? Colors.green.shade600
                    : colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _FrequencyRow(
        series: series,
        label: series == null
            ? null
            : recurrenceFrequencyLabel(context, series),
        trailing: series == null ? null : recurrenceReachLabel(context, series),
      ),
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
        value: widget.accounts[movement.accountId]?.name ?? '—',
      ),
      _DetailRow(
        icon: Icons.sell_rounded,
        label: context.l10n.category,
        value: widget.categories[movement.categoryId]?.name ?? '—',
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
      _TopUpSection(series: series, adding: _busy, onAddMore: _addMore),
    ];
  }

  /// The form: each label above its control, every control the full width.
  ///
  /// Deliberately a different shape from the receipt above. A right-aligned
  /// value reads well when it is text, and badly when it is a dropdown or a
  /// text box squeezed into the same slot.
  List<Widget> _editFields(
    BuildContext context,
    Transaction movement,
    RecurrenceSeries? series,
  ) {
    final frequency = _effectiveFrequency(series);
    final dayInterval = _effectiveDayInterval(series);
    return [
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: context.l10n.titlePlaceholder,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: context.l10n.amount,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      if (series != null)
        _DetailField(
          label: context.l10n.frequency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<RecurrenceFrequency>(
                value: frequency,
                isExpanded: true,
                onChanged: (value) {
                  if (value != null) setState(() => _frequency = value);
                },
                items: [
                  for (final value in RecurrenceFrequency.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_frequencyOptionLabel(context, value)),
                    ),
                ],
              ),
              if (frequency == RecurrenceFrequency.customDays)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Text(context.l10n.recurrenceRepeatEvery),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 72,
                        child: TextFormField(
                          initialValue: '$dayInterval',
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (raw) {
                            final parsed = int.tryParse(raw);
                            if (parsed != null && parsed >= 1) {
                              setState(() => _dayInterval = parsed);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(context.l10n.recurrenceDaysUnit),
                    ],
                  ),
                ),
            ],
          ),
        ),
      _DetailField(
        label: context.l10n.date,
        child: _ChangeRow(
          value: formatNumericDate(_date, context.localeName),
          onPressed: _pickDate,
        ),
      ),
      _DetailField(
        label: context.l10n.time,
        child: _ChangeRow(
          value: MaterialLocalizations.of(
            context,
          ).formatTimeOfDay(TimeOfDay.fromDateTime(_date)),
          onPressed: _pickTime,
        ),
      ),
      _DetailField(
        label: context.l10n.account,
        child: _EntityDropdown<Account>(
          value: _accountId,
          entities: widget.accounts,
          nameOf: (a) => '${a.name} · ${a.currency}',
          onChanged: (next) => setState(() => _accountId = next),
        ),
      ),
      _DetailField(
        label: context.l10n.category,
        child: _EntityDropdown<Category>(
          value: _categoryId,
          entities: widget.categories,
          nameOf: (c) => c.name,
          onChanged: (next) => setState(() => _categoryId = next),
        ),
      ),
      _DetailField(
        label: context.l10n.description,
        child: TextField(
          controller: _description,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: context.l10n.descriptionPlaceholder,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _busy ? null : () => _save(series),
        child: Text(context.l10n.saveChanges),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _busy ? null : _cancelEditing,
        child: Text(context.l10n.cancel),
      ),
    ];
  }

  /// The cadence options, as the form offers them: `customDays` keeps its
  /// generic "Cada X días" here because the interval has its own field.
  String _frequencyOptionLabel(
    BuildContext context,
    RecurrenceFrequency value,
  ) => switch (value) {
    RecurrenceFrequency.daily => context.l10n.recurrenceDaily,
    RecurrenceFrequency.weekly => context.l10n.recurrenceWeekly,
    RecurrenceFrequency.monthly => context.l10n.recurrenceMonthly,
    RecurrenceFrequency.yearly => context.l10n.recurrenceYearly,
    RecurrenceFrequency.customDays => context.l10n.recurrenceCustomDays,
  };

  /// Drops the edits and puts the fields back to what is stored, so reopening
  /// the form does not resume an abandoned one.
  void _cancelEditing() {
    final movement = _current ?? widget.movement;
    setState(() {
      _editing = false;
      _name.text = movement.name;
      _description.text = movement.description ?? '';
      _amount.text = (movement.amount.toInt().abs() / 100).toStringAsFixed(2);
      _date = DateTime.fromMillisecondsSinceEpoch(movement.date.toInt());
      _accountId = movement.accountId;
      _categoryId = movement.categoryId;
      _frequency = null;
      _dayInterval = null;
    });
  }
}

/// A form field: its label above it, in small caps, and the control below at
/// full width. The demo's shape (wal-153) — a right-aligned slot works for a
/// receipt and fights anything you can type into.
class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// A read-only value with the button that changes it — for the pickers, which
/// have no inline editor.
class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.value, required this.onPressed});

  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(value)),
        TextButton(onPressed: onPressed, child: Text(context.l10n.change)),
      ],
    );
  }
}

/// A full-width dropdown over the user's accounts or categories.
class _EntityDropdown<T> extends StatelessWidget {
  const _EntityDropdown({
    required this.value,
    required this.entities,
    required this.nameOf,
    required this.onChanged,
  });

  final String value;
  final Map<String, T> entities;
  final String Function(T) nameOf;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: entities.containsKey(value) ? value : null,
      isExpanded: true,
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
      items: [
        for (final entry in entities.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(nameOf(entry.value), overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}

/// The cadence row, with how far the series reaches beside it. Absent for a
/// one-off movement, and while the series is still loading.
class _FrequencyRow extends StatelessWidget {
  const _FrequencyRow({
    required this.series,
    required this.label,
    required this.trailing,
  });

  final RecurrenceSeries? series;
  final String? label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    if (series == null || label == null) return const SizedBox.shrink();
    return _DetailRow(
      icon: Icons.repeat_rounded,
      label: context.l10n.frequency,
      value: label,
      trailing: trailing,
    );
  }
}

/// The "add N more" affordance, or nothing at all.
///
/// Only an open-ended series can be topped up. One with an end date is already
/// complete, and running past a boundary the user set on purpose would be
/// editing the rule rather than extending it.
class _TopUpSection extends StatelessWidget {
  const _TopUpSection({
    required this.series,
    required this.adding,
    required this.onAddMore,
  });

  final RecurrenceSeries? series;
  final bool adding;
  final Future<void> Function(String recurrenceId) onAddMore;

  @override
  Widget build(BuildContext context) {
    final rule = series?.rule;
    if (rule == null || rule.endDate != null) return const SizedBox.shrink();
    final frequency = recurrenceFrequencyFromName(rule.frequency);
    if (frequency == null) return const SizedBox.shrink();

    final count = recurrenceHorizon(
      frequency,
      dayInterval: rule.dayInterval ?? 1,
    ).count;

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: adding ? null : () => onAddMore(rule.id),
            child: Text(
              adding
                  ? context.l10n.addingMoreMovements
                  : context.l10n.addMoreMovements(count),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.addMoreMovementsHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
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
    this.trailing,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final String value;

  /// A subdued note after the value, on the same line.
  final String? trailing;
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
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              trailing!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
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
