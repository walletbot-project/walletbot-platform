import 'package:app/components/category_icons.dart';
import 'package:app/components/color_picker.dart';
import 'package:app/components/color_utils.dart';
import 'package:app/components/icon_picker.dart';
import 'package:app/data/data.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Name + icon presets, mirroring the account creation suggestions.
const _nameSuggestions = [
  (label: 'Supermercado', icon: Icons.shopping_cart_rounded),
  (label: 'Transporte', icon: Icons.directions_bus_rounded),
  (label: 'Servicios', icon: Icons.receipt_long_rounded),
];

class CreateCategoryScreen extends StatefulWidget {
  const CreateCategoryScreen({super.key});

  @override
  State<CreateCategoryScreen> createState() => _CreateCategoryScreenState();
}

class _CreateCategoryScreenState extends State<CreateCategoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  Color _color = categoryDefaultColor;
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
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      debugPrint('Error creating category: $e\n$st');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva categoría')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Sugerencias', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in _nameSuggestions)
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
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                hintText: 'Ej: Supermercado, Transporte…',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresá un nombre' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Ícono y color',
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
                      color: _color.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: Icon(_icon, size: 28, color: _color),
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
                  : const Text('Crear categoría'),
            ),
          ],
        ),
      ),
    );
  }
}
