import 'package:app/components/account_icons.dart';
import 'package:app/components/account_list_tile.dart';
import 'package:app/components/color_picker.dart';
import 'package:app/components/color_utils.dart';
import 'package:app/components/grouped_card.dart';
import 'package:app/components/icon_picker.dart';
import 'package:app/components/transaction_row.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/create_account.dart';
import 'package:app/shared/app_navigation.dart';
import 'package:app/shared/money.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:m3e_buttons/m3e_buttons.dart';
import 'package:provider/provider.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  void _openCreate(BuildContext context) {
    // Pushed routes sit above the account-scoped providers; re-provide them
    // so the new route keeps using the active account's data layer.
    final repos = context.read<AppRepositories>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Provider<AppRepositories>.value(
          value: repos,
          child: const CreateAccountScreen(),
        ),
      ),
    );
  }

  /// Opens the account details as a draggable, scrollable modal sheet. The
  /// sheet is a pushed route below the account-scoped providers, so the data
  /// layer and navigation controller are captured here and handed down.
  void _openAccountSheet(BuildContext context, Account account) {
    final repos = context.read<AppRepositories>();
    final nav = context.read<AppNavigation>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true, // let the sheet grow taller than half-screen
      showDragHandle: true,
      builder: (_) =>
          AccountDetailsSheet(account: account, repos: repos, nav: nav),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repos = context.read<AppRepositories>();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.accounts),
        actions: [
          IconButton(
            tooltip: context.l10n.newAccount,
            onPressed: () => _openCreate(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: StreamBuilder<List<Account>>(
        stream: repos.accounts.watchActive(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorBody(error: snapshot.error.toString());
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final accounts = snapshot.data ?? const <Account>[];
          if (accounts.isEmpty) {
            return _EmptyBody(onCreateTap: () => _openCreate(context));
          }
          return ListView.separated(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 96),
            itemCount: accounts.length,
            separatorBuilder: (_, _) => const SizedBox(height: kGroupSpacing),
            itemBuilder: (context, index) {
              final account = accounts[index];
              return _AccountTile(
                account: account,
                borderRadius: groupedRadius(index, accounts.length),
                onTap: () => _openAccountSheet(context, account),
              );
            },
          );
        },
      ),
    );
  }
}

/// One account in the list: the shared [AccountListTile] fed the account's
/// accent (color + icon resolved from their stored string form) and its live
/// balance.
class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.borderRadius,
    required this.onTap,
  });

  final Account account;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final repos = context.read<AppRepositories>();
    return StreamBuilder<BigInt>(
      stream: repos.accounts.watchBalanceCents(account.id),
      builder: (context, snapshot) {
        final balance = snapshot.data ?? BigInt.zero;
        return AccountListTile(
          name: account.name,
          icon: accountIconFromName(account.icon),
          color: colorFromHex(account.color, fallback: accountDefaultColor),
          balanceCents: balance.toInt(),
          currency: account.currency,
          borderRadius: borderRadius,
          onTap: onTap,
        );
      },
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.onCreateTap});

  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.noAccountsTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.noAccountsBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCreateTap,
            icon: const Icon(Icons.add),
            label: Text(context.l10n.createAccount),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 64, color: colors.error),
          const SizedBox(height: 16),
          Text(
            context.l10n.accountsLoadFailed,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            error,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Draggable, scrollable modal sheet showing an account's details. Edits to the
/// name, color and icon are committed on leaving edit mode; balance changes are
/// committed immediately as a balance adjustment.
class AccountDetailsSheet extends StatefulWidget {
  const AccountDetailsSheet({
    super.key,
    required this.account,
    required this.repos,
    required this.nav,
  });

  final Account account;
  final AppRepositories repos;
  final AppNavigation nav;

  @override
  State<AccountDetailsSheet> createState() => _AccountDetailsSheetState();
}

class _AccountDetailsSheetState extends State<AccountDetailsSheet> {
  // Locally editable identity values — the controls mutate these and they are
  // persisted on leaving edit mode.
  late Color _color = colorFromHex(
    widget.account.color,
    fallback: accountDefaultColor,
  );
  late IconData _icon = accountIconFromName(widget.account.icon);
  late final TextEditingController _nameController = TextEditingController(
    text: widget.account.name,
  );

  bool _editing = false;
  bool _saving = false;

  String get _accountId => widget.account.id;
  String get _currency => widget.account.currency;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _editColor() async {
    final picked = await showColorPickerDialog(
      context,
      selected: _color,
      options: colorOptions,
    );
    if (picked != null) setState(() => _color = picked);
  }

  Future<void> _editIcon() async {
    final picked = await showIconPickerDialog(
      context,
      selected: _icon,
      options: accountIconOptions,
      accent: _color,
    );
    if (picked != null) setState(() => _icon = picked);
  }

  /// Toggles edit mode. Entering just reveals the editors; leaving validates
  /// and persists name/color/icon.
  Future<void> _toggleEditing() async {
    if (!_editing) {
      setState(() => _editing = true);
      return;
    }
    await _saveIdentity();
  }

  Future<void> _saveIdentity() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack(context.l10n.nameCannotBeEmpty);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.repos.accounts.update(
        _accountId,
        name: Value(name),
        color: Value(colorToHex(_color)),
        icon: Value(accountIconName(_icon)),
      );
      if (!mounted) return;
      setState(() => _editing = false);
    } catch (e, st) {
      debugPrint('Error updating account: $e\n$st');
      _showSnack(context.l10n.accountSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _adjustBalance() async {
    final l10n = context.l10n;
    final current = await widget.repos.accounts.getBalanceCents(_accountId);
    if (!mounted) return;

    var text = (current.toInt() / 100).toStringAsFixed(2);
    final target = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        // TextFormField with initialValue owns and disposes its own controller —
        // a manually-disposed local controller crashes when the dialog closes.
        return AlertDialog(
          title: Text(context.l10n.adjustBalance),
          content: TextFormField(
            initialValue: text,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: InputDecoration(
              prefixText: '$_currency ',
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => text = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                final value = double.tryParse(text.replaceAll(',', '.'));
                Navigator.of(
                  dialogContext,
                ).pop(value == null ? null : (value * 100).round());
              },
              child: Text(context.l10n.save),
            ),
          ],
        );
      },
    );
    if (target == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.repos.transactions.addBalanceAdjustment(
        accountId: _accountId,
        balanceAfterCents: BigInt.from(target),
        currency: _currency,
      );
    } catch (e, st) {
      debugPrint('Error adjusting balance: $e\n$st');
      _showSnack(l10n.adjustBalanceFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(context.l10n.deleteAccount),
          content: Text(
            context.l10n.deleteAccountConfirmation(_nameController.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: colors.error),
              child: Text(context.l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.repos.accounts.archive(_accountId);
      if (!mounted) return;
      Navigator.of(context).pop(); // close the details sheet
    } catch (e, st) {
      debugPrint('Error archiving account: $e\n$st');
      if (mounted) setState(() => _saving = false);
      _showSnack(context.l10n.deleteAccountFailed);
    }
  }

  void _openAllTransactions() {
    Navigator.of(context).pop(); // close the sheet before switching tabs
    widget.nav.openActivityForAccount(_accountId);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // DraggableScrollableSheet lets the user drag the sheet between sizes while
    // its content scrolls; isScrollControlled on the modal enables the tall sizes.
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController, // wires drag-to-scroll to the sheet
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            _buildIdentityGroup(context),
            const SizedBox(height: 12),
            _buildActions(context),
            const SizedBox(height: 28),
            _buildTransactionsHeader(context),
            const SizedBox(height: 8),
            _buildTransactions(context),
          ],
        );
      },
    );
  }

  /// The account name: an inline text field while editing, plain text otherwise.
  Widget _buildName(TextTheme textTheme) {
    final style = textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600);
    if (_editing) {
      return TextField(
        controller: _nameController,
        style: style,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          isDense: true,
          labelText: context.l10n.name,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      );
    }
    return Text(
      _nameController.text,
      style: style,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Identity + balance as one cohesive M3 Expressive containment group: a
  /// color-washed identity hero (icon, name, color swatch) joined by the shared
  /// 2dp seam to the balance hero (focal amount + currency).
  Widget _buildIdentityGroup(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        // Identity hero — tinted by the account's accent so the whole block
        // carries the account color. Holds the icon, name, plus a discrete
        // color swatch as a trailing accent.
        Material(
          color: _color.withValues(alpha: 0.14),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(kGroupOuterRadius),
            bottom: Radius.circular(kGroupInnerRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Expressive rounded-square icon tile — tappable only while
                // editing, to change the icon.
                InkWell(
                  onTap: _editing ? _editIcon : null,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _color.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: Icon(_icon, size: 30, color: _color),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: _buildName(textTheme)),
                // Discrete color swatch — only shown while editing; tap to
                // change the account color.
                if (_editing) ...[
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: _editColor,
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _color,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: kGroupSpacing),
        // Balance hero — the focal number; currency rides along as a pill. The
        // amount is live: it re-emits as balance adjustments and synced
        // transactions land.
        GroupedCard(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(kGroupInnerRadius),
            bottom: Radius.circular(kGroupOuterRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.balance.toUpperCase(),
                        style: textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      StreamBuilder<BigInt>(
                        stream: widget.repos.accounts.watchBalanceCents(
                          _accountId,
                        ),
                        builder: (context, snapshot) {
                          final cents = (snapshot.data ?? BigInt.zero).toInt();
                          return Text(
                            formatMoney(
                              cents,
                              _currency,
                              locale: context.localeName,
                            ),
                            style: textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cents < 0 ? colors.error : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Currency pill.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _currency,
                    style: textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Account actions as Material 3 Expressive buttons: a prominent tonal
  /// "adjust balance" action paired with edit and a destructive delete.
  Widget _buildActions(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: M3EFilledButton.tonalIcon(
            onPressed: _saving ? null : _adjustBalance,
            size: M3EButtonSize.md,
            icon: const Icon(Icons.tune_rounded),
            label: Text(context.l10n.adjustBalance),
          ),
        ),
        const SizedBox(width: 8),
        M3EButton(
          onPressed: _saving ? null : _toggleEditing,
          style: _editing ? M3EButtonStyle.filled : M3EButtonStyle.tonal,
          size: M3EButtonSize.md,
          tooltip: _editing ? context.l10n.done : context.l10n.edit,
          semanticLabel: _editing ? context.l10n.done : context.l10n.edit,
          child: Icon(_editing ? Icons.check_rounded : Icons.edit_outlined),
        ),
        const SizedBox(width: 8),
        M3EButton(
          onPressed: _saving ? null : _confirmDelete,
          size: M3EButtonSize.md,
          tooltip: context.l10n.delete,
          semanticLabel: context.l10n.delete,
          decoration: M3EButtonDecoration.styleFrom(
            backgroundColor: colors.errorContainer,
            foregroundColor: colors.onErrorContainer,
          ),
          child: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  /// "Last transactions" section header with a "view all" action that opens the
  /// Activity tab filtered to this account.
  Widget _buildTransactionsHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            context.l10n.lastTransactions,
            style: textTheme.titleMedium,
          ),
        ),
        TextButton(
          onPressed: _openAllTransactions,
          child: Text(context.l10n.viewAll),
        ),
      ],
    );
  }

  /// The five most recent transactions for this account, rendered with the
  /// shared [TransactionRow]. Handles loading, error and empty states.
  Widget _buildTransactions(BuildContext context) {
    final symbol = currencyPrefix(_currency).trim();
    return StreamBuilder<List<Transaction>>(
      stream: widget.repos.transactions.watch(
        TransactionFilter(accountIds: {_accountId}),
        limit: 5,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              context.l10n.transactionsCouldNotLoad,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final txs = snapshot.data ?? const <Transaction>[];
        if (txs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              context.l10n.noTransactionsYet,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < txs.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              TransactionRow(
                title: context.l10n.transactionName(txs[i].name, txs[i].type),
                amountCents: _signedAmountCents(txs[i]),
                dateCheck: txs[i].dateConfirmed,
                description: _shortDate(context, txs[i].date),
                currencySymbol: symbol,
                onTap: () {},
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Signed cents for [TransactionRow]: positive renders green, negative renders
/// in the default text color. Mirrors the activity screen's convention.
int _signedAmountCents(Transaction t) {
  final amount = t.amount.toInt();
  switch (t.type) {
    case 'expense':
      return -amount.abs();
    case 'income':
    case 'transfer':
      return amount.abs();
    default: // balance_adjustment keeps its stored sign
      return amount;
  }
}

/// Compact `day month` label, e.g. `27 may`.
String _shortDate(BuildContext context, BigInt dateMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(dateMs.toInt());
  return formatShortDate(dt, context.localeName);
}
