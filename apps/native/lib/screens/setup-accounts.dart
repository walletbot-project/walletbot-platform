import 'package:app/components/currency-chip-button.dart';
import 'package:app/database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

// ── Suggestions ──────────────────────────────────────────────────────────────

const _suggestions = [
  (label: 'Efectivo', icon: Icons.payments_rounded),
  (label: 'Banco', icon: Icons.account_balance_rounded),
  (label: 'Tarjeta', icon: Icons.credit_card_rounded),
];

// ── Row data model ────────────────────────────────────────────────────────────

/// Mutable data for a single account row in the setup screen.
class _AccountEntry {
  _AccountEntry({String? name})
    : nameController = TextEditingController(text: name ?? ''),
      balanceController = TextEditingController(),
      currency = 'ARS';

  final TextEditingController nameController;
  final TextEditingController balanceController;
  String currency;

  void dispose() {
    nameController.dispose();
    balanceController.dispose();
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// Lets the user create several accounts and their optional initial balances
/// in a single step.  Nothing is written to the database until the user taps
/// "Confirmar".
///
/// Entry points:
///  - HomeScreen banner when the user has no accounts yet.
///  - AccountsScreen "⋮ → Configuración inicial" hidden menu.
class SetupAccountsScreen extends StatefulWidget {
  const SetupAccountsScreen({super.key});

  @override
  State<SetupAccountsScreen> createState() => _SetupAccountsScreenState();
}

class _SetupAccountsScreenState extends State<SetupAccountsScreen> {
  final List<_AccountEntry> _entries = [_AccountEntry()];
  bool _saving = false;

  @override
  void dispose() {
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  // ── Entry management ─────────────────────────────────────────────────────────

  void _addEntry({String? name}) {
    setState(() => _entries.add(_AccountEntry(name: name)));
  }

  void _removeEntry(int index) {
    setState(() {
      _entries[index].dispose();
      _entries.removeAt(index);
      // Always keep at least one empty row.
      if (_entries.isEmpty) _entries.add(_AccountEntry());
    });
  }

  void _updateCurrency(int index, String currency) {
    setState(() => _entries[index].currency = currency);
  }

  // ── Submit ────────────────────────────────────────────────────────────────────

  Future<void> _confirm() async {
    // Collect valid entries (non-empty name), skipping blank rows silently.
    final toCreate = <({String name, String currency, BigInt? amount})>[];

    for (final entry in _entries) {
      final name = entry.nameController.text.trim();
      if (name.isEmpty) continue;

      BigInt? amount;
      final rawBalance = entry.balanceController.text.trim();
      if (rawBalance.isNotEmpty) {
        final parsed = double.tryParse(rawBalance.replaceAll(',', '.'));
        if (parsed == null || parsed < 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Balance inválido para "$name"')),
            );
          }
          return;
        }
        amount = BigInt.from((parsed * 100).round());
      }

      toCreate.add((name: name, currency: entry.currency, amount: amount));
    }

    if (toCreate.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá al menos una cuenta')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = context.read<AppDatabase>();
      await db.transaction(() async {
        for (final item in toCreate) {
          final accountId = const Uuid().v4();
          await db.insertAccount(
            id: accountId,
            name: item.name,
            currency: item.currency,
          );
          if (item.amount != null) {
            final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
            await db.insertTransaction(
              id: const Uuid().v4(),
              type: 'balance_adjustment',
              name: 'Balance inicial',
              status: 'cleared',
              date: now,
              accountId: accountId,
              categoryId: '',
              amount: item.amount!,
              currency: item.currency,
              balanceAfter: item.amount!,
            );
          }
        }
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      debugPrint('Error creating accounts: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al crear las cuentas')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                const SliverAppBar.large(title: Text('Configurar cuentas')),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sugerencias',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final s in _suggestions)
                              ActionChip(
                                avatar: Icon(s.icon),
                                label: Text(s.label),
                                onPressed: _saving
                                    ? null
                                    : () => _addEntry(name: s.label),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, i) => _SetupRow(
                      key: ObjectKey(_entries[i]),
                      nameController: _entries[i].nameController,
                      balanceController: _entries[i].balanceController,
                      currency: _entries[i].currency,
                      onCurrencyChanged: (c) => _updateCurrency(i, c),
                      onDelete: _saving ? null : () => _removeEntry(i),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  sliver: SliverToBoxAdapter(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : () => _addEntry(),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar cuenta'),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Confirm bar ───────────────────────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                onPressed: _saving ? null : _confirm,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirmar'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Row widget ────────────────────────────────────────────────────────────────

class _SetupRow extends StatelessWidget {
  const _SetupRow({
    super.key,
    required this.nameController,
    required this.balanceController,
    required this.currency,
    required this.onCurrencyChanged,
    required this.onDelete,
  });

  final TextEditingController nameController;
  final TextEditingController balanceController;
  final String currency;
  final ValueChanged<String> onCurrencyChanged;
  // Null while saving — disables the button.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Leading avatar — matches AccountsScreen style.
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(
                Icons.account_balance_wallet_rounded,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),

            // Name + currency/balance row.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Nombre de la cuenta',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      CurrencyChipButton(
                        currency: currency,
                        onChanged: onCurrencyChanged,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: balanceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Balance inicial (opc.)',
                            prefixText: '$currency ',
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Delete button.
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
              iconSize: 20,
              onPressed: onDelete,
              tooltip: 'Quitar',
            ),
          ],
        ),
      ),
    );
  }
}
