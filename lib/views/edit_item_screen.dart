import 'package:flutter/material.dart';
import '../models/pantry_item.dart';
import '../services/validation_service.dart';
import '../services/date_formatter.dart';
import '../constants/categories.dart';
import 'widgets/liquid_glass.dart';

class EditItemScreen extends StatefulWidget {
  final PantryItem item;
  const EditItemScreen({super.key, required this.item});

  @override
  State<EditItemScreen> createState() => _EditItemScreenState();
}

class _EditItemScreenState extends State<EditItemScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late String _unit;
  late String _category;
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.name);
    _quantityController =
        TextEditingController(text: widget.item.quantity.toString());
    _unit = widget.item.unit;
    _category = widget.item.category;
    _expiryDate = widget.item.expiryDate;
  }

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
      firstDate: DateTime(today.year - 15),
      lastDate: DateTime(today.year + 15),
      helpText: 'Selecione a validade',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );
    if (picked != null && mounted) setState(() => _expiryDate = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(widget.item.copyWith(
      name: _nameController.text.trim(),
      quantity:
          double.parse(_quantityController.text.trim().replaceAll(',', '.')),
      unit: _unit,
      expiryDate: _expiryDate,
      clearExpiryDate: _expiryDate == null,
      category: _category,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LiquidGlassAppBar(title: Text('Editar item')),
      body: LiquidGlassBackground(
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                LiquidGlassCard(
                  padding: const EdgeInsets.all(20),
                  borderRadius: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nome do item',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Ex.: arroz, feijão, tomate',
                          prefixIcon: Icon(Icons.edit),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Digite o nome do ingrediente'
                                : null,
                      ),
                      const SizedBox(height: 20),
                      Text('Categoria',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
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
                      Text('Quantidade',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
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
                          ]),
                      const SizedBox(height: 20),
                      Text('Validade',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _selectExpiryDate,
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(_expiryDate == null
                              ? 'Adicionar data de validade (opcional)'
                              : 'Vence em ${DateFormatter.format(_expiryDate!)}'),
                          style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16)),
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
                  icon: const Icon(Icons.save),
                  label: const Text('Salvar alterações'),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
