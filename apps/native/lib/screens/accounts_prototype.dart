import 'package:app/components/account_icons.dart';
import 'package:app/components/account_list_tile.dart';
import 'package:app/components/color_picker.dart';
import 'package:app/components/grouped_card.dart';
import 'package:app/components/icon_picker.dart';
import 'package:app/components/transaction_row.dart';
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
class AccountDetailsSheet extends StatefulWidget {
  const AccountDetailsSheet({super.key, required this.account});

  final Account account;

  @override
  State<AccountDetailsSheet> createState() => _AccountDetailsSheetState();
}

class _AccountDetailsSheetState extends State<AccountDetailsSheet> {
  // Locally editable values — the controls mutate these. The mock list behind
  // the sheet is const, so edits live for the sheet's lifetime.
  late Color _color = widget.account.color;
  late IconData _icon = widget.account.icon;
  late int _balanceCents = widget.account.balanceCents;
  late final TextEditingController _nameController = TextEditingController(
    text: widget.account.name,
  );

  // Edit mode is toggled by the pencil action: only then do the name field and
  // color swatch appear and the icon tile become tappable.
  bool _editing = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _editColor() async {
    final picked = await showColorPickerDialog(context, selected: _color);
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

  Future<void> _adjustBalance() async {
    // TextFormField with initialValue owns and disposes its own controller —
    // a manually-disposed local controller crashes when the dialog closes.
    var text = (_balanceCents / 100).toStringAsFixed(2);
    final picked = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ajustar saldo'),
          content: TextFormField(
            initialValue: text,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: InputDecoration(
              prefixText: '${widget.account.currency} ',
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => text = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                final value = double.tryParse(text.replaceAll(',', '.'));
                Navigator.of(
                  dialogContext,
                ).pop(value == null ? null : (value * 100).round());
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
    if (picked != null) setState(() => _balanceCents = picked);
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
        decoration: const InputDecoration(
          isDense: true,
          labelText: 'Nombre',
          border: OutlineInputBorder(),
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
  /// 2dp seam to the balance hero (focal amount + currency). Large radius lands
  /// only on the group's four outer corners; the seam is minimal so the two
  /// cards read as a single rounded block.
  Widget _buildIdentityGroup(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isNegative = _balanceCents < 0;

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
                        formatMoney(_balanceCents, widget.account.currency),
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
                    widget.account.currency,
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
            onPressed: _adjustBalance,
            size: M3EButtonSize.md,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Ajustar saldo'),
          ),
        ),
        const SizedBox(width: 8),
        M3EButton(
          onPressed: () => setState(() => _editing = !_editing),
          style: _editing ? M3EButtonStyle.filled : M3EButtonStyle.tonal,
          size: M3EButtonSize.md,
          tooltip: _editing ? 'Listo' : 'Editar',
          semanticLabel: _editing ? 'Listo' : 'Editar',
          child: Icon(_editing ? Icons.check_rounded : Icons.edit_outlined),
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

  /// Recent transactions, rendered with the shared [TransactionRow] used by the
  /// activity view. The date label rides along as the row's description.
  Widget _buildTransactions(BuildContext context) {
    final txs = widget.account.transactions;
    final symbol = currencyPrefix(widget.account.currency).trim();
    return Column(
      children: [
        for (var i = 0; i < txs.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          TransactionRow(
            title: txs[i].title,
            amountCents: txs[i].amountCents,
            dateCheck: true,
            description: txs[i].date,
            currencySymbol: symbol,
            onTap: () {},
          ),
        ],
      ],
    );
  }
}
