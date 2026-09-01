import 'package:app/components/transaction_row.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/shared/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The cadence descriptors we surface in the mock. Kept local so the screen
/// doesn't depend on the form's private recurrence enum.
enum RecurrenceFrequencyLabel { daily, weekly, monthly, yearly, customDays }

String _frequencyLabel(BuildContext context, RecurrenceFrequencyLabel value) {
  switch (value) {
    case RecurrenceFrequencyLabel.daily:
      return context.l10n.recurrenceDaily;
    case RecurrenceFrequencyLabel.weekly:
      return context.l10n.recurrenceWeekly;
    case RecurrenceFrequencyLabel.monthly:
      return context.l10n.recurrenceMonthly;
    case RecurrenceFrequencyLabel.yearly:
      return context.l10n.recurrenceYearly;
    case RecurrenceFrequencyLabel.customDays:
      return context.l10n.recurrenceCustomDays;
  }
}

/// The scope a recurring edit/delete applies to.
enum RecurrenceScope { onlyThis, allFuture }

class _AccountOption {
  const _AccountOption(this.name, this.color, this.icon);
  final String name;
  final Color color;
  final IconData icon;
}

const _accountOptions = <_AccountOption>[
  _AccountOption(
    'Banco Nación',
    Color(0xFF3B82F6),
    Icons.account_balance_rounded,
  ),
  _AccountOption('Efectivo', Color(0xFF22C55E), Icons.payments_rounded),
];

class _CategoryOption {
  const _CategoryOption(this.name, this.color, this.icon);
  final String name;
  final Color color;
  final IconData icon;
}

const _categoryOptions = <_CategoryOption>[
  _CategoryOption(
    'Suscripciones',
    Color(0xFFA855F7),
    Icons.subscriptions_rounded,
  ),
  _CategoryOption('Salud', Color(0xFFEF4444), Icons.favorite_rounded),
  _CategoryOption('Servicios', Color(0xFF0EA5E9), Icons.wifi_rounded),
  _CategoryOption('Vivienda', Color(0xFFF97316), Icons.home_rounded),
  _CategoryOption('Sueldo', Color(0xFF22C55E), Icons.work_rounded),
];

/// A single upcoming recurring movement. Backed by mock data — future movements
/// are not persisted yet (see docs/recurrency-design.md).
class _FutureMovement {
  const _FutureMovement({
    required this.id,
    required this.ruleId,
    required this.title,
    required this.amountCents,
    required this.currency,
    required this.date,
    required this.frequency,
    required this.accountIndex,
    required this.categoryIndex,
    this.dayInterval = 15,
    this.description,
  });

  final String id;

  /// Id of the rule that generated this occurrence, shared across all
  /// occurrences of the same series.
  final String ruleId;
  final String title;

  /// Signed cents: positive renders green (income), negative renders default.
  final int amountCents;
  final String currency;
  final DateTime date;
  final RecurrenceFrequencyLabel frequency;
  final int dayInterval;
  final String? description;
  final int accountIndex;
  final int categoryIndex;

  bool get isExpense => amountCents < 0;
  _AccountOption get account => _accountOptions[accountIndex];
  _CategoryOption get category => _categoryOptions[categoryIndex];

  _FutureMovement copyWith({
    String? title,
    int? amountCents,
    DateTime? date,
    RecurrenceFrequencyLabel? frequency,
    int? dayInterval,
    Object? description = _sentinel,
    int? accountIndex,
    int? categoryIndex,
  }) {
    return _FutureMovement(
      id: id,
      ruleId: ruleId,
      title: title ?? this.title,
      amountCents: amountCents ?? this.amountCents,
      currency: currency,
      date: date ?? this.date,
      frequency: frequency ?? this.frequency,
      dayInterval: dayInterval ?? this.dayInterval,
      description: description == _sentinel
          ? this.description
          : description as String?,
      accountIndex: accountIndex ?? this.accountIndex,
      categoryIndex: categoryIndex ?? this.categoryIndex,
    );
  }
}

const Object _sentinel = Object();

/// How many upcoming occurrences we materialize per rule in the mock.
const _occurrencesPerRule = 3;

class _MockRule {
  const _MockRule({
    required this.ruleId,
    required this.title,
    required this.amountCents,
    required this.firstInDays,
    required this.hour,
    required this.frequency,
    required this.accountIndex,
    required this.categoryIndex,
    this.dayInterval = 15,
    this.description,
  });

  final String ruleId;
  final String title;
  final int amountCents;
  final int firstInDays;
  final int hour;
  final RecurrenceFrequencyLabel frequency;
  final int accountIndex;
  final int categoryIndex;
  final int dayInterval;
  final String? description;
}

const _mockRules = <_MockRule>[
  _MockRule(
    ruleId: 'spotify',
    title: 'Spotify',
    amountCents: -550000,
    firstInDays: 2,
    hour: 9,
    frequency: RecurrenceFrequencyLabel.monthly,
    description: 'Suscripción mensual',
    accountIndex: 0,
    categoryIndex: 0,
  ),
  _MockRule(
    ruleId: 'gym',
    title: 'Gimnasio',
    amountCents: -1500000,
    firstInDays: 5,
    hour: 8,
    frequency: RecurrenceFrequencyLabel.monthly,
    description: 'Cuota mensual',
    accountIndex: 0,
    categoryIndex: 1,
  ),
  _MockRule(
    ruleId: 'rent',
    title: 'Alquiler',
    amountCents: -35000000,
    firstInDays: 10,
    hour: 9,
    frequency: RecurrenceFrequencyLabel.monthly,
    accountIndex: 1,
    categoryIndex: 3,
  ),
  _MockRule(
    ruleId: 'salary',
    title: 'Sueldo',
    amountCents: 120000000,
    firstInDays: 12,
    hour: 9,
    frequency: RecurrenceFrequencyLabel.monthly,
    description: 'Ingreso mensual',
    accountIndex: 0,
    categoryIndex: 4,
  ),
  _MockRule(
    ruleId: 'water',
    title: 'Agua',
    amountCents: -1800000,
    firstInDays: 21,
    hour: 11,
    frequency: RecurrenceFrequencyLabel.customDays,
    dayInterval: 60,
    description: 'Servicio bimestral',
    accountIndex: 0,
    categoryIndex: 2,
  ),
];

/// The date [steps] cadences after [anchor]. `steps == 0` returns the anchor.
/// Used both to materialize a rule's occurrences and to re-project the future
/// ones when an anchor occurrence moves.
DateTime _stepDate(
  DateTime anchor,
  RecurrenceFrequencyLabel frequency,
  int dayInterval,
  int steps,
) {
  switch (frequency) {
    case RecurrenceFrequencyLabel.monthly:
      return DateTime(
        anchor.year,
        anchor.month + steps,
        anchor.day,
        anchor.hour,
        anchor.minute,
      );
    case RecurrenceFrequencyLabel.yearly:
      return DateTime(
        anchor.year + steps,
        anchor.month,
        anchor.day,
        anchor.hour,
        anchor.minute,
      );
    case RecurrenceFrequencyLabel.weekly:
      return DateTime(
        anchor.year,
        anchor.month,
        anchor.day + 7 * steps,
        anchor.hour,
        anchor.minute,
      );
    case RecurrenceFrequencyLabel.daily:
      return DateTime(
        anchor.year,
        anchor.month,
        anchor.day + steps,
        anchor.hour,
        anchor.minute,
      );
    case RecurrenceFrequencyLabel.customDays:
      return DateTime(
        anchor.year,
        anchor.month,
        anchor.day + dayInterval * steps,
        anchor.hour,
        anchor.minute,
      );
  }
}

/// The date of the [index]-th occurrence of a rule, stepping by its cadence.
DateTime _occurrenceDate(DateTime now, _MockRule rule, int index) {
  final anchor = DateTime(
    now.year,
    now.month,
    now.day + rule.firstInDays,
    rule.hour,
  );
  return _stepDate(anchor, rule.frequency, rule.dayInterval, index);
}

List<_FutureMovement> _mockMovements() {
  final now = DateTime.now();
  return [
    for (final rule in _mockRules)
      for (var i = 0; i < _occurrencesPerRule; i++)
        _FutureMovement(
          id: '${rule.ruleId}-$i',
          ruleId: rule.ruleId,
          title: rule.title,
          amountCents: rule.amountCents,
          currency: 'ARS',
          date: _occurrenceDate(now, rule, i),
          frequency: rule.frequency,
          dayInterval: rule.dayInterval,
          description: rule.description,
          accountIndex: rule.accountIndex,
          categoryIndex: rule.categoryIndex,
        ),
  ];
}

class FutureMovementsScreen extends StatefulWidget {
  const FutureMovementsScreen({super.key});

  @override
  State<FutureMovementsScreen> createState() => _FutureMovementsScreenState();
}

class _FutureMovementsScreenState extends State<FutureMovementsScreen> {
  late List<_FutureMovement> _movements = _mockMovements();

  String _sectionLabel(BuildContext context, DateTime day, DateTime today) {
    final diff = today.difference(day).inDays;
    if (diff == 0) return context.l10n.today;
    if (diff == 1) return context.l10n.yesterday;
    if (diff > 1 && diff < 7) return formatWeekday(day, context.localeName);
    return formatNumericDate(day, context.localeName);
  }

  Future<void> _openDetail(_FutureMovement original) async {
    final result = await Navigator.of(context).push<_DetailResult>(
      MaterialPageRoute(
        builder: (_) => _FutureMovementDetailScreen(movement: original),
      ),
    );
    if (result == null || !mounted) return;

    // "This and future": affects this occurrence plus later ones of the same
    // rule, compared against the occurrence's ORIGINAL date.
    bool isLaterInSameRule(_FutureMovement m) =>
        m.ruleId == original.ruleId && m.date.isAfter(original.date);

    switch (result) {
      case _SaveResult(:final movement, :final scope):
        // The edited occurrence becomes the new anchor; later occurrences of
        // the rule are re-projected from it, so moving a monthly movement to
        // the 18th shifts the rest to the 18th (and weekly/custom recalculate
        // the following ones from the new date).
        final laterSorted = scope == RecurrenceScope.allFuture
            ? (_movements.where(isLaterInSameRule).toList()
                ..sort((a, b) => a.date.compareTo(b.date)))
            : <_FutureMovement>[];
        final stepById = <String, int>{
          for (var i = 0; i < laterSorted.length; i++) laterSorted[i].id: i + 1,
        };
        setState(() {
          _movements = [
            for (final m in _movements)
              if (m.id == movement.id)
                movement
              else if (stepById.containsKey(m.id))
                m.copyWith(
                  title: movement.title,
                  amountCents: movement.amountCents,
                  frequency: movement.frequency,
                  dayInterval: movement.dayInterval,
                  description: movement.description,
                  accountIndex: movement.accountIndex,
                  categoryIndex: movement.categoryIndex,
                  date: _stepDate(
                    movement.date,
                    movement.frequency,
                    movement.dayInterval,
                    stepById[m.id]!,
                  ),
                )
              else
                m,
          ];
        });
        _showSnack(
          scope == RecurrenceScope.onlyThis
              ? 'Cambios aplicados a este movimiento'
              : 'Cambios aplicados a este y los futuros',
        );
      case _DeleteResult(:final scope):
        setState(() {
          _movements = _movements
              .where(
                (m) =>
                    m.id != original.id &&
                    !(scope == RecurrenceScope.allFuture &&
                        isLaterInSameRule(m)),
              )
              .toList();
        });
        _showSnack(
          scope == RecurrenceScope.onlyThis
              ? 'Movimiento eliminado'
              : 'Movimiento y sus futuros eliminados',
        );
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final movements = [..._movements]
      ..sort((left, right) => left.date.compareTo(right.date));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final children = <Widget>[
      _InfoBanner(text: context.l10n.futureMovementsInfo),
      const SizedBox(height: 8),
    ];

    if (movements.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(48),
          child: Center(child: Text(context.l10n.noFutureMovements)),
        ),
      );
    } else {
      DateTime? currentDay;
      for (final movement in movements) {
        final day = DateTime(
          movement.date.year,
          movement.date.month,
          movement.date.day,
        );
        if (currentDay == null || day != currentDay) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                _sectionLabel(context, day, today),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
          currentDay = day;
        }
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TransactionRow(
              title: movement.title,
              amountCents: movement.amountCents,
              currency: movement.currency,
              dateCheck: true,
              description: _descriptionFor(context, movement),
              visualIdentities: _visualIdentitiesFor(context, movement),
              onTap: () => _openDetail(movement),
            ),
          ),
        );
      }
      children.add(const SizedBox(height: 24));
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.futureMovements)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 8),
          children: children,
        ),
      ),
    );
  }

  String? _descriptionFor(BuildContext context, _FutureMovement movement) {
    final parts = [
      _frequencyLabel(context, movement.frequency),
      if (movement.description != null && movement.description!.isNotEmpty)
        movement.description!,
    ];
    return parts.join(' · ');
  }

  List<TransactionRowVisualIdentity> _visualIdentitiesFor(
    BuildContext context,
    _FutureMovement movement,
  ) {
    return [
      TransactionRowVisualIdentity(
        type: TransactionRowVisualIdentityType.account,
        label: 'Cuenta: ${movement.account.name}',
        icon: movement.account.icon,
        color: movement.account.color,
      ),
      TransactionRowVisualIdentity(
        type: TransactionRowVisualIdentityType.category,
        label: 'Categoría: ${movement.category.name}',
        icon: movement.category.icon,
        color: movement.category.color,
      ),
      TransactionRowVisualIdentity(
        type: TransactionRowVisualIdentityType.time,
        label: MaterialLocalizations.of(
          context,
        ).formatTimeOfDay(TimeOfDay.fromDateTime(movement.date)),
        icon: Icons.schedule_outlined,
        color: Colors.transparent,
      ),
    ];
  }
}

// ── Detail / edit / delete screen ───────────────────────────────────────

sealed class _DetailResult {
  const _DetailResult();
}

class _SaveResult extends _DetailResult {
  const _SaveResult(this.movement, this.scope);
  final _FutureMovement movement;
  final RecurrenceScope scope;
}

class _DeleteResult extends _DetailResult {
  const _DeleteResult(this.scope);
  final RecurrenceScope scope;
}

class _FutureMovementDetailScreen extends StatefulWidget {
  const _FutureMovementDetailScreen({required this.movement});

  final _FutureMovement movement;

  @override
  State<_FutureMovementDetailScreen> createState() =>
      _FutureMovementDetailScreenState();
}

class _FutureMovementDetailScreenState
    extends State<_FutureMovementDetailScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _amountController;
  late final TextEditingController _dayIntervalController;

  bool _editing = false;
  late DateTime _date;
  late RecurrenceFrequencyLabel _frequency;
  late int _accountIndex;
  late int _categoryIndex;

  @override
  void initState() {
    super.initState();
    final m = widget.movement;
    _titleController = TextEditingController(text: m.title);
    _descriptionController = TextEditingController(text: m.description ?? '');
    _amountController = TextEditingController(
      text: (m.amountCents.abs() ~/ 100).toString(),
    );
    _dayIntervalController = TextEditingController(
      text: m.dayInterval.toString(),
    );
    _date = m.date;
    _frequency = m.frequency;
    _accountIndex = m.accountIndex;
    _categoryIndex = m.categoryIndex;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    _dayIntervalController.dispose();
    super.dispose();
  }

  Future<void> _toggleEditing() async {
    if (!_editing) {
      setState(() => _editing = true);
      return;
    }
    await _save();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showSnack('El título es obligatorio');
      return;
    }
    final magnitude = int.tryParse(_amountController.text.trim());
    if (magnitude == null || magnitude <= 0) {
      _showSnack('El monto debe ser mayor a 0');
      return;
    }

    final scope = await _showScopeDialog(
      title: 'Guardar cambios',
      description:
          '¿Aplicar los cambios solo a este movimiento o también a los futuros?',
      destructive: false,
    );
    if (scope == null || !mounted) return;

    final signedAmount = (widget.movement.isExpense ? -1 : 1) * magnitude * 100;
    final dayInterval = _frequency == RecurrenceFrequencyLabel.customDays
        ? (int.tryParse(_dayIntervalController.text.trim()) ?? 15)
        : widget.movement.dayInterval;

    final updated = widget.movement.copyWith(
      title: title,
      amountCents: signedAmount,
      date: _date,
      frequency: _frequency,
      dayInterval: dayInterval,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      accountIndex: _accountIndex,
      categoryIndex: _categoryIndex,
    );
    Navigator.of(context).pop(_SaveResult(updated, scope));
  }

  Future<void> _confirmDelete() async {
    final scope = await _showScopeDialog(
      title: 'Eliminar movimiento recurrente',
      description:
          '¿Querés eliminar "${widget.movement.title}" solo esta vez o también los futuros?',
      destructive: true,
    );
    if (scope == null || !mounted) return;
    Navigator.of(context).pop(_DeleteResult(scope));
  }

  Future<RecurrenceScope?> _showScopeDialog({
    required String title,
    required String description,
    required bool destructive,
  }) {
    return showDialog<RecurrenceScope>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        final style = destructive
            ? TextButton.styleFrom(foregroundColor: colors.error)
            : null;
        return AlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(RecurrenceScope.onlyThis),
              style: style,
              child: const Text('Solo este movimiento'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(RecurrenceScope.allFuture),
              style: style,
              child: const Text('Este y los futuros'),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
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
    if (picked == null || !mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final m = widget.movement;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Editar movimiento' : 'Detalle'),
        actions: [
          IconButton(
            tooltip: _editing ? 'Guardar' : 'Editar',
            onPressed: _toggleEditing,
            icon: Icon(_editing ? Icons.check_rounded : Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _editing
                      ? TextField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'Título',
                            border: OutlineInputBorder(),
                          ),
                        )
                      : Text(
                          m.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                if (!_editing) ...[
                  const SizedBox(width: 12),
                  Text(
                    formatMoney(m.amountCents, m.currency),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: m.amountCents > 0
                          ? Colors.green.shade600
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            if (_editing) ...[
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _DetailField(
              label: 'Frecuencia',
              child: _editing
                  ? _buildFrequencyEditor(context)
                  : Text(_frequencyText(context, m)),
            ),
            _DetailField(
              label: 'Fecha',
              child: _editing
                  ? _ChangeRow(
                      value: formatNumericDate(_date, context.localeName),
                      onPressed: _pickDate,
                    )
                  : Text(formatNumericDate(m.date, context.localeName)),
            ),
            _DetailField(
              label: 'Hora',
              child: _editing
                  ? _ChangeRow(
                      value: MaterialLocalizations.of(
                        context,
                      ).formatTimeOfDay(TimeOfDay.fromDateTime(_date)),
                      onPressed: _pickTime,
                    )
                  : Text(
                      MaterialLocalizations.of(
                        context,
                      ).formatTimeOfDay(TimeOfDay.fromDateTime(m.date)),
                    ),
            ),
            _DetailField(
              label: 'Cuenta',
              child: _editing ? _buildAccountEditor() : Text(m.account.name),
            ),
            _DetailField(
              label: 'Categoría',
              child: _editing ? _buildCategoryEditor() : Text(m.category.name),
            ),
            _DetailField(
              label: 'Descripción',
              child: _editing
                  ? TextField(
                      controller: _descriptionController,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Detalle opcional',
                        border: OutlineInputBorder(),
                      ),
                    )
                  : Text(
                      m.description?.isNotEmpty == true
                          ? m.description!
                          : 'Sin descripción',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _frequencyText(BuildContext context, _FutureMovement m) {
    final base = _frequencyLabel(context, m.frequency);
    if (m.frequency == RecurrenceFrequencyLabel.customDays) {
      return '$base (${m.dayInterval} días)';
    }
    return base;
  }

  Widget _buildFrequencyEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<RecurrenceFrequencyLabel>(
          value: _frequency,
          isExpanded: true,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _frequency = value);
          },
          items: [
            for (final value in RecurrenceFrequencyLabel.values)
              DropdownMenuItem(
                value: value,
                child: Text(_frequencyLabel(context, value)),
              ),
          ],
        ),
        if (_frequency == RecurrenceFrequencyLabel.customDays)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Text('Repetir cada'),
                const SizedBox(width: 12),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: _dayIntervalController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('días'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAccountEditor() {
    return DropdownButton<int>(
      value: _accountIndex,
      isExpanded: true,
      onChanged: (value) {
        if (value == null) return;
        setState(() => _accountIndex = value);
      },
      items: [
        for (var i = 0; i < _accountOptions.length; i++)
          DropdownMenuItem(value: i, child: Text(_accountOptions[i].name)),
      ],
    );
  }

  Widget _buildCategoryEditor() {
    return DropdownButton<int>(
      value: _categoryIndex,
      isExpanded: true,
      onChanged: (value) {
        if (value == null) return;
        setState(() => _categoryIndex = value);
      },
      items: [
        for (var i = 0; i < _categoryOptions.length; i++)
          DropdownMenuItem(value: i, child: Text(_categoryOptions[i].name)),
      ],
    );
  }
}

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
            style: TextStyle(
              fontSize: 12,
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

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.value, required this.onPressed});

  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(value)),
        TextButton(onPressed: onPressed, child: const Text('Cambiar')),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0x1A21C4B6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x6621C4B6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: Color(0xFF11796F),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 14, color: Color(0xFF11796F)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
