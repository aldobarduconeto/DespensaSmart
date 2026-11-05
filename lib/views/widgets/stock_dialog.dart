import 'package:flutter/material.dart';
import '../../models/pantry_item.dart';

Future<double?> showStockDialog(BuildContext context, PantryItem item,
        {required bool buying}) =>
    showDialog<double>(
      context: context,
      builder: (_) => _StockDialog(item: item, buying: buying),
    );

class ConsumptionSelection {
  const ConsumptionSelection({required this.amount, this.person});

  final double amount;
  final String? person;
}

Future<ConsumptionSelection?> showConsumptionDialog(
  BuildContext context,
  PantryItem item, {
  required List<String> familyMembers,
}) =>
    showDialog<ConsumptionSelection>(
      context: context,
      builder: (_) => _StockDialog(
        item: item,
        buying: false,
        familyMembers: familyMembers,
      ),
    );

class _StockDialog extends StatefulWidget {
  final PantryItem item;
  final bool buying;
  final List<String> familyMembers;
  const _StockDialog({
    required this.item,
    required this.buying,
    this.familyMembers = const [],
  });
  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(
      text: widget.buying ? '1' : '${widget.item.quantity}');
  String? _person;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(
        context,
        widget.familyMembers.isEmpty
            ? double.parse(_controller.text.trim().replaceAll(',', '.'))
            : ConsumptionSelection(
                amount: double.parse(
                    _controller.text.trim().replaceAll(',', '.')),
                person: _person,
              ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.buying
            ? 'Repor ${widget.item.name}'
            : 'Consumir ${widget.item.name}'),
        content: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _controller,
                autofocus: true,
                onFieldSubmitted: (_) => _submit(),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantidade (${widget.item.unit})',
                  helperText: widget.buying
                      ? 'A compra será somada ao estoque.'
                      : 'Disponível: ${widget.item.quantity} ${widget.item.unit}',
                ),
                validator: (value) {
                  final amount = double.tryParse(
                      (value ?? '').trim().replaceAll(',', '.'));
                  if (amount == null || !amount.isFinite || amount <= 0) {
                    return 'Informe uma quantidade maior que zero';
                  }
                  if (!widget.buying) {
                    try {
                      widget.item.quantityAfterConsuming(amount);
                    } on StateError {
                      return 'Quantidade maior que o estoque';
                    }
                  }
                  return null;
                },
              ),
              if (!widget.buying && widget.familyMembers.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _person,
                  decoration: const InputDecoration(
                    labelText: 'Quem usou?',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  items: widget.familyMembers
                      .map((person) => DropdownMenuItem(
                            value: person,
                            child: Text(person),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => _person = value),
                  validator: (value) =>
                      value == null ? 'Selecione quem usou o item' : null,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: _submit,
              child: Text(
                  widget.buying ? 'Confirmar compra' : 'Registrar consumo')),
        ],
      );
}
