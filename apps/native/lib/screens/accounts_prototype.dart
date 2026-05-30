import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:m3e_buttons/m3e_buttons.dart';

/// Mock account model shaped after the real backend fields:
/// name, icon, color accent, ISO currency, plus computed balance/income/expense.
/// All monetary values are in cents (matching the backend `amount` convention).
class Account {
  const Account({
    required this.name,
    this.description,
    required this.icon,
    required this.color,
    required this.currency,
    required this.balanceCents,
    required this.incomeCents,
    required this.expenseCents,
    this.transactions = _sampleTransactions,
  });

  final String name;
  final String? description; // optional free-text note (subtitle + sheet)
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
    description: 'Cuenta principal para gastos del día a día.',
    icon: Icons.account_balance_rounded,
    color: Color(0xFF3B82F6),
    currency: 'USD',
    balanceCents: 325040,
    incomeCents: 540000,
    expenseCents: 214960,
  ),
  Account(
    name: 'Ahorros',
    description: 'Ahorros de largo plazo y fondo de emergencia.',
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
    description: 'Resumen y consumos de la tarjeta Visa.',
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

/// Prefix for an ISO currency: symbol for EUR/GBP, ISO code otherwise (USD, ARS).
String _currencyPrefix(String code) => switch (code) {
  'EUR' => '€',
  'GBP' => '£',
  _ => '$code ',
};

/// Formats cents as currency in es-AR style ('.' thousands, ',' decimals).
String formatMoney(int cents, String currency, {int decimalDigits = 2}) {
  return NumberFormat.currency(
    locale: 'es_AR',
    symbol: _currencyPrefix(currency),
    decimalDigits: decimalDigits,
  ).format(cents / 100);
}

// M3 expressive grouped-list shape tokens (shared by every card list).
const double _kGroupOuterRadius = 24; // first/last ends of a group
const double _kGroupInnerRadius = 4; // corners between adjacent cards
const double _kGroupSpacing = 2; // small separation between cards

/// Corner shape for the card at [index] within a group of [count]: large radius
/// on the outer ends of the group, minimal radius on the inner seams.
BorderRadius _groupedRadius(int index, int count) => BorderRadius.vertical(
  top: Radius.circular(index == 0 ? _kGroupOuterRadius : _kGroupInnerRadius),
  bottom: Radius.circular(
    index == count - 1 ? _kGroupOuterRadius : _kGroupInnerRadius,
  ),
);

/// A single card within an M3 expressive grouped list: card surface, injected
/// corner shape, optional tap ripple. Reused by every card list on this screen.
class GroupedCard extends StatelessWidget {
  const GroupedCard({
    super.key,
    required this.borderRadius,
    required this.child,
    this.onTap,
  });

  final BorderRadius borderRadius;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    );
  }
}

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
        separatorBuilder: (_, _) => const SizedBox(height: _kGroupSpacing),
        itemBuilder: (context, index) {
          final account = _mockAccounts[index];
          return CardLikeListTile(
            account: account,
            borderRadius: _groupedRadius(index, _mockAccounts.length),
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

/// A single account rendered as a Material 3 expressive card-like list tile.
/// Reusable: the shape and tap behavior are injected by the caller.
class CardLikeListTile extends StatelessWidget {
  const CardLikeListTile({
    super.key,
    required this.account,
    required this.borderRadius,
    this.onTap,
  });

  final Account account;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isNegative = account.balanceCents < 0;

    return GroupedCard(
      borderRadius: borderRadius,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            // Leading icon tinted with the account's accent color.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: account.color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(account.icon, size: 22, color: account.color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Balance: signed, with currency; negative balances use error color.
            Text(
              formatMoney(account.balanceCents, account.currency),
              style: textTheme.titleMedium?.copyWith(
                color: isNegative ? colors.error : null,
              ),
            ),
          ],
        ),
      ),
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
            _buildAccountHeader(context),
            const SizedBox(height: 28),
            _buildTransactionsHeader(context),
            const SizedBox(height: 8),
            _buildTransactions(context),
          ],
        );
      },
    );
  }

  /// Account identity, balance, and management actions as one cohesive M3
  /// Expressive containment card, color-washed by the account accent so the
  /// whole block carries the account's color. The header band pairs the accent
  /// icon tile with the edit and (destructive) delete actions; below, the name
  /// is prefixed by its editable color swatch and the description; a hairline
  /// divider then sets off the focal balance with its currency pill.
  Widget _buildAccountHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isNegative = account.balanceCents < 0;

    return Material(
      color: account.color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(_kGroupOuterRadius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header band: accent icon tile on the left, edit + delete on the
            // right as compact icon buttons (delete carries the error tone).
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: account.color.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Icon(account.icon, size: 28, color: account.color),
                ),
                const Spacer(),
                M3EButton(
                  onPressed: () {},
                  style: M3EButtonStyle.tonal,
                  size: M3EButtonSize.sm,
                  tooltip: 'Editar',
                  semanticLabel: 'Editar',
                  child: const Icon(Icons.edit_outlined, size: 20),
                ),
                const SizedBox(width: 8),
                M3EButton(
                  onPressed: () {},
                  size: M3EButtonSize.sm,
                  tooltip: 'Eliminar',
                  semanticLabel: 'Eliminar',
                  decoration: M3EButtonDecoration.styleFrom(
                    backgroundColor: colors.errorContainer,
                    foregroundColor: colors.onErrorContainer,
                  ),
                  child: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Name prefixed by its editable color swatch.
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: account.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
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
              ],
            ),
            // Description shown only when present.
            if (account.description != null) ...[
              const SizedBox(height: 6),
              Text(
                account.description!,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Divider(
              height: 1,
              thickness: 1,
              color: colors.outlineVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            // Focal balance with the currency riding along as a pill.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
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
          ],
        ),
      ),
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
          if (i > 0) const SizedBox(height: _kGroupSpacing),
          GroupedCard(
            borderRadius: _groupedRadius(i, txs.length),
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
