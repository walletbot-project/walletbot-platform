import 'package:app/components/category_icons.dart';
import 'package:app/components/color_picker.dart';
import 'package:app/components/color_utils.dart';
import 'package:app/components/icon_picker.dart';
import 'package:app/data/data.dart';
import 'package:app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Name + icon presets, mirroring the account creation suggestions.
List<({String label, IconData icon})> _nameSuggestions(AppLocalizations l10n) =>
    [
      (label: l10n.groceries, icon: Icons.shopping_cart_rounded),
      (label: l10n.transport, icon: Icons.directions_bus_rounded),
      (label: l10n.services, icon: Icons.receipt_long_rounded),
    ];

class CreateCategoryScreen extends StatefulWidget {
  const CreateCategoryScreen({super.key, this.onClose});

  /// Embedded (split pane) mode: when set, the screen never pops its route —
  /// exits report here instead, and an explicit close button is shown.
  final VoidCallback? onClose;

  @override
  State<CreateCategoryScreen> createState() => _CreateCategoryScreenState();
}

class _CreateCategoryScreenState extends State<CreateCategoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  Color _color = categoryDefaultColor;

  /// [_color] as painted in the current theme (see [readableAccent]); the
  /// stored value stays the raw pick.
  Color get _paintedColor =>
      readableAccent(_color, Theme.of(context).brightness);
  IconData _icon = categoryDefaultIcon;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _applySuggestion(({String label, IconData icon}) suggestion) {
    final name = suggestion.label;
    _nameController.text = name;
    _nameController.selection = TextSelection.collapsed(offset: name.length);
    setState(() => _icon = suggestion.icon);
  }

  Future<void> _pickIcon() async {
    final picked = await showIconPickerDialog(
      context,
      selected: _icon,
      options: categoryIconOptions,
      accent: _color,
    );
    if (picked != null) setState(() => _icon = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final description = _descriptionController.text.trim();

    setState(() => _saving = true);
    try {
      await context.read<AppRepositories>().categories.create(
        name: _nameController.text.trim(),
        description: description.isEmpty ? null : description,
        color: colorToHex(_color),
        icon: categoryIconName(_icon),
      );
      if (mounted) _close();
    } catch (e, st) {
      debugPrint('Error creating category: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.categoryCreateFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Exits the screen: reports to [CreateCategoryScreen.onClose] when embedded
  /// in the split pane, pops the route otherwise.
  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Embedded there is no route to pop, so no back button appears on its
        // own — offer an explicit close instead.
        leading: widget.onClose == null
            ? null
            : IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: _close,
                icon: const Icon(Icons.close_rounded),
              ),
        title: Text(context.l10n.newCategory),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              context.l10n.suggestions,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in _nameSuggestions(context.l10n))
                  ActionChip(
                    avatar: Icon(s.icon),
                    label: Text(s.label),
                    onPressed: () => _applySuggestion(s),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.l10n.nameRequiredLabel,
                hintText: context.l10n.categoryNameExample,
                border: const OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.l10n.enterName
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.l10n.descriptionOptional,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.iconAndColor,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tappable icon tile, tinted with the selected accent.
                InkWell(
                  onTap: _pickIcon,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _paintedColor.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: Icon(_icon, size: 28, color: _paintedColor),
                  ),
                ),
                const SizedBox(width: 16),
                // Inline accent swatches.
                Expanded(
                  child: ColorPicker(
                    selected: _color,
                    options: colorOptions,
                    onChanged: (color) => setState(() => _color = color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.l10n.createCategory),
            ),
          ],
        ),
      ),
    );
  }
}
