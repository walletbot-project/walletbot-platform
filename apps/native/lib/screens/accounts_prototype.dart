import 'package:app/components/account_list_tile.dart';
import 'package:app/components/grouped_card.dart';
import 'package:app/shared/money.dart';
import 'package:flutter/material.dart';
import 'package:m3e_buttons/m3e_buttons.dart';

/// Mock account model shaped after the real backend fields:
/// name, icon, color accent, ISO currency, plus computed balance/income/expense.
/// All monetary values are in cents (matching the backend `amount` convention).
class Account {
  const Account({
    required this.name,
    required this.icon,
    required this.color,
    required this.currency,
    required this.balanceCents,
    required this.incomeCents,
    required this.expenseCents,
    this.transactions = _sampleTransactions,
  });

  final String name;
  final IconData icon;
  final Color color; // visual accent (backend `color` hex)
  final String currency; // ISO code: USD, ARS, EUR, GBP
  final int balanceCents; // computed balance, can be negative
  final int incomeCents; // total inflows (ingresos)
  final int expenseCents; // total outflows (egresos)
  final List<Transaction> transactions; // most-recent first
}

/// A single account movement. `amountCents` is signed: negative = expense.
class Transaction {
  const Transaction({
    required this.title,
    required this.date,
    required this.amountCents,
    required this.icon,
  });

  final String title;
  final String date; // pre-formatted short label, e.g. '27 may'
  final int amountCents;
  final IconData icon;
}

/// Shared mock movements reused across accounts for the prototype.
const List<Transaction> _sampleTransactions = [
  Transaction(
    title: 'Sueldo',
    date: '25 may',
    amountCents: 540000,
    icon: Icons.payments_rounded,
  ),
  Transaction(
    title: 'Supermercado',
    date: '24 may',
    amountCents: -8450,
    icon: Icons.shopping_cart_rounded,
  ),
  Transaction(
    title: 'Café',
    date: '24 may',
    amountCents: -1200,
    icon: Icons.local_cafe_rounded,
  ),
  Transaction(
    title: 'Transporte',
    date: '23 may',
    amountCents: -2300,
    icon: Icons.directions_bus_rounded,
  ),
  Transaction(
    title: 'Suscripción',
    date: '22 may',
    amountCents: -999,
    icon: Icons.subscriptions_rounded,
  ),
];

const List<Account> _mockAccounts = [
  Account(
    name: 'Cuenta Corriente',
    icon: Icons.account_balance_rounded,
    color: Color(0xFF3B82F6),
    currency: 'USD',
    balanceCents: 325040,
    incomeCents: 540000,
    expenseCents: 214960,
  ),
  Account(
    name: 'Ahorros',
    icon: Icons.savings_rounded,
    color: Color(0xFF14B8A6),
    currency: 'USD',
    balanceCents: 1298000,
    incomeCents: 1500000,
    expenseCents: 202000,
  ),
  Account(
    name: 'Efectivo',
    icon: Icons.payments_rounded,
    color: Color(0xFFF59E0B),
    currency: 'ARS',
    balanceCents: 14275,
    incomeCents: 50000,
    expenseCents: 35725,
  ),
  Account(
    name: 'Tarjeta de Crédito',
    icon: Icons.credit_card_rounded,
    color: Color(0xFFEF4444),
    currency: 'USD',
    balanceCents: -54018,
    incomeCents: 0,
    expenseCents: 54018,
  ),
  Account(
    name: 'Fondo de Viajes',
    icon: Icons.flight_takeoff_rounded,
    color: Color(0xFF6366F1),
    currency: 'EUR',
    balanceCents: 201500,
    incomeCents: 250000,
    expenseCents: 48500,
  ),
  Account(
    name: 'Inversiones',
    icon: Icons.trending_up_rounded,
    color: Color(0xFF8B5CF6),
    currency: 'GBP',
    balanceCents: 843022,
    incomeCents: 900000,
    expenseCents: 56978,
  ),
];

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuentas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openAccountSheet(_mockAccounts[0]),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
        itemCount: _mockAccounts.length,
        separatorBuilder: (_, _) => const SizedBox(height: kGroupSpacing),
        itemBuilder: (context, index) {
          final account = _mockAccounts[index];
          return AccountListTile(
            name: account.name,
            icon: account.icon,
            color: account.color,
            balanceCents: account.balanceCents,
            currency: account.currency,
            borderRadius: groupedRadius(index, _mockAccounts.length),
            onTap: () => _openAccountSheet(account),
          );
        },
      ),
    );
  }

  /// Opens the account details as a draggable, scrollable modal sheet.
  void _openAccountSheet(Account account) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true, // let the sheet grow taller than half-screen
      showDragHandle: true,
      builder: (_) => AccountDetailsSheet(account: account),
    );
  }
}

/// Draggable, scrollable modal sheet showing an account's details.
class AccountDetailsSheet extends StatelessWidget {
  const AccountDetailsSheet({super.key, required this.account});

  final Account account;

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

  /// Identity + balance as one cohesive M3 Expressive containment group: a
  /// color-washed identity hero (icon, name, color swatch) joined by the shared
  /// 2dp seam to the balance hero (focal amount + currency). Large radius lands
  /// only on the group's four outer corners; the seam is minimal so the two
  /// cards read as a single rounded block.
  Widget _buildIdentityGroup(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isNegative = account.balanceCents < 0;

    return Column(
      children: [
        // Identity hero — tinted by the account's accent so the whole block
        // carries the account color. Holds the icon, name, plus a discrete
        // color swatch as a trailing accent.
        Material(
          color: account.color.withValues(alpha: 0.14),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(kGroupOuterRadius),
            bottom: Radius.circular(kGroupInnerRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Expressive rounded-square icon tile — shape variety against
                // the circular avatars used elsewhere on the sheet.
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: account.color.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: Icon(account.icon, size: 30, color: account.color),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    account.name,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                // Discrete color swatch — the editable "color" attribute.
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: account.color,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: kGroupSpacing),
        // Balance hero — the focal number; currency rides along as a pill.
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
                        'SALDO',
                        style: textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatMoney(account.balanceCents, account.currency),
                        style: textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isNegative ? colors.error : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                    account.currency,
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
  /// "adjust balance" action paired with edit and a destructive delete. Each
  /// button carries the M3E spring radius-squish on press.
  Widget _buildActions(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: M3EFilledButton.tonalIcon(
            onPressed: () {},
            size: M3EButtonSize.md,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Ajustar saldo'),
          ),
        ),
        const SizedBox(width: 8),
        M3EButton(
          onPressed: () {},
          style: M3EButtonStyle.tonal,
          size: M3EButtonSize.md,
          tooltip: 'Editar',
          semanticLabel: 'Editar',
          child: const Icon(Icons.edit_outlined),
        ),
        const SizedBox(width: 8),
        M3EButton(
          onPressed: () {},
          size: M3EButtonSize.md,
          tooltip: 'Eliminar',
          semanticLabel: 'Eliminar',
          decoration: M3EButtonDecoration.styleFrom(
            backgroundColor: colors.errorContainer,
            foregroundColor: colors.onErrorContainer,
          ),
          child: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  /// "Last transactions" section header with a "view all" action.
  Widget _buildTransactionsHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text('Últimas transacciones', style: textTheme.titleMedium),
        ),
        TextButton(onPressed: () {}, child: const Text('Ver todas')),
      ],
    );
  }

  /// Transactions as an M3 expressive grouped-card list (same style as the
  /// accounts list: large outer corners, minimal inner seams, 2dp gaps).
  Widget _buildTransactions(BuildContext context) {
    final txs = account.transactions;
    return Column(
      children: [
        for (var i = 0; i < txs.length; i++) ...[
          if (i > 0) const SizedBox(height: kGroupSpacing),
          GroupedCard(
            borderRadius: groupedRadius(i, txs.length),
            onTap: () {},
            child: _TransactionTile(tx: txs[i], currency: account.currency),
          ),
        ],
      ],
    );
  }
}

/// Reusable transaction row content (icon, title + date, signed amount).
/// Designed to sit inside a [GroupedCard], matching the account tile layout.
class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx, required this.currency});

  final Transaction tx;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isExpense = tx.amountCents < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(tx.icon, size: 20, color: colors.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.title, style: textTheme.bodyLarge),
                Text(
                  tx.date,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Signed amount; expenses use the error color.
          Text(
            formatMoney(tx.amountCents, currency),
            style: textTheme.titleSmall?.copyWith(
              color: isExpense ? colors.error : null,
            ),
          ),
        ],
      ),
    );
  }
}
