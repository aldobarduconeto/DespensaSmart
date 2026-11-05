import 'package:flutter/material.dart';
import '../models/pantry_item.dart';
import '../services/app_settings_service.dart';
import '../services/validation_service.dart';
import '../services/date_formatter.dart';
import '../constants/categories.dart';
import 'widgets/liquid_glass.dart';

class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  late String _unit = AppSettingsService.instance.defaultUnit;
  late String _category = AppSettingsService.instance.defaultCategory;
  DateTime? _expiryDate;

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _selectExpiryDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? today,
      firstDate: today,
      lastDate: DateTime(today.year + 15),
      helpText: 'Selecione a validade',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );
    if (picked != null && mounted) setState(() => _expiryDate = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(PantryItem(
      name: _nameController.text.trim(),
      quantity:
          double.parse(_quantityController.text.trim().replaceAll(',', '.')),
      unit: _unit,
      expiryDate: _expiryDate,
      category: _category,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const LiquidGlassAppBar(title: Text('Adicionar item')),
      body: LiquidGlassBackground(
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                LiquidGlassCard(
                  prominent: true,
                  padding: const EdgeInsets.all(22),
                  borderRadius: 26,
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(
                          Icons.inventory_2_outlined,
                          size: 32,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'O que tem na sua despensa?',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Cadastre apenas os itens que você realmente possui.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                LiquidGlassCard(
                  padding: const EdgeInsets.all(20),
                  borderRadius: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nome do item',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        autofocus: true,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Ex.: arroz, feijão, tomate',
                          prefixIcon: Icon(Icons.search),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Digite o nome do ingrediente'
                                : null,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Categoria',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.category)),
                        items: AppConstants.categories
                            .map((cat) =>
                                DropdownMenuItem(value: cat, child: Text(cat)))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _category = value);
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Quantidade',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _quantityController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration:
                                  const InputDecoration(hintText: '1'),
                              validator: ValidationService.validateQuantity,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 4,
                            child: DropdownButtonFormField<String>(
                              initialValue: _unit,
                              decoration:
                                  const InputDecoration(labelText: 'Unidade'),
                              items: AppConstants.units
                                  .map((unit) => DropdownMenuItem(
                                      value: unit, child: Text(unit)))
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _unit = value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Validade',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _selectExpiryDate,
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(
                            _expiryDate == null
                                ? 'Adicionar data de validade (opcional)'
                                : 'Vence em ${DateFormatter.format(_expiryDate!)}',
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      if (_expiryDate != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => setState(() => _expiryDate = null),
                            icon: const Icon(Icons.close),
                            label: const Text('Remover validade'),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: const Text('Salvar na despensa'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
