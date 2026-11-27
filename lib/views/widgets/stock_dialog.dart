import 'package:flutter/material.dart';
import '../../models/pantry_item.dart';

Future<double?> showStockDialog(
  BuildContext context,
  PantryItem item, {
  required bool buying,
}) =>
    showDialog<double>(
      context: context,
      builder: (_) => _StockDialog(item: item, buying: buying, returnDoubleOnly: true),
    );

class ConsumptionSelection {
  const ConsumptionSelection({
    required this.amount,
    this.person,
    this.isWaste = false,
    this.wasteReason,
  });

  final double amount;
  final String? person;
  final bool isWaste;
  final String? wasteReason;
}

Future<ConsumptionSelection?> showConsumptionDialog(
  BuildContext context,
  PantryItem item, {
  List<String> familyMembers = const [],
}) =>
    showDialog<ConsumptionSelection>(
      context: context,
      builder: (_) => _StockDialog(
        item: item,
        buying: false,
        familyMembers: familyMembers,
        returnDoubleOnly: false,
      ),
    );

class _StockDialog extends StatefulWidget {
  final PantryItem item;
  final bool buying;
  final List<String> familyMembers;
  final bool returnDoubleOnly;

  const _StockDialog({
    required this.item,
    required this.buying,
    this.familyMembers = const [],
    this.returnDoubleOnly = false,
  });

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  static const _wasteReasons = [
    'Vencido',
    'Estragou / Azedou',
    'Sobra não aproveitada',
    'Embalagem danificada',
    'Outro motivo',
  ];

  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(
      text: widget.buying ? '1' : '${widget.item.quantity}');
  String? _person;
  bool _isWaste = false;
  String _wasteReason = 'Vencido';

  @override
  void initState() {
    super.initState();
    if (!widget.buying && widget.item.isExpired()) {
      _isWaste = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      final amount = double.parse(_controller.text.trim().replaceAll(',', '.'));
      if (widget.returnDoubleOnly) {
        Navigator.pop(context, amount);
      } else {
        Navigator.pop(
          context,
          ConsumptionSelection(
            amount: amount,
            person: _person,
            isWaste: _isWaste,
            wasteReason: _isWaste ? _wasteReason : null,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(
        widget.buying
            ? 'Repor ${widget.item.name}'
            : (_isWaste ? 'Descartar ${widget.item.name}' : 'Consumir ${widget.item.name}'),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.buying) ...[
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.restaurant_outlined, size: 18),
                      label: Text('Consumo'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text('Descarte / Perda'),
                    ),
                  ],
                  selected: {_isWaste},
                  onSelectionChanged: (set) => setState(() => _isWaste = set.first),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _controller,
                autofocus: true,
                onFieldSubmitted: (_) => _submit(),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantidade (${widget.item.unit})',
                  helperText: widget.buying
                      ? 'A compra será somada ao estoque.'
                      : (_isWaste
                          ? 'Quantidade que será descartada.'
                          : 'Disponível: ${widget.item.quantity} ${widget.item.unit}'),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final amount = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
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
              if (!widget.buying && _isWaste) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _wasteReason,
                  decoration: const InputDecoration(
                    labelText: 'Motivo do descarte',
                    prefixIcon: Icon(Icons.help_outline_rounded),
                    border: OutlineInputBorder(),
                  ),
                  items: _wasteReasons
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _wasteReason = val);
                  },
                ),
              ],
              if (!widget.buying && !_isWaste && widget.familyMembers.isNotEmpty) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _person,
                  decoration: const InputDecoration(
                    labelText: 'Quem consumiu?',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                    border: OutlineInputBorder(),
                  ),
                  items: widget.familyMembers
                      .map((person) => DropdownMenuItem(
                            value: person,
                            child: Text(person),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => _person = value),
                  validator: (value) => value == null ? 'Selecione quem usou o item' : null,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: _isWaste
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: _submit,
          child: Text(
            widget.buying
                ? 'Confirmar compra'
                : (_isWaste ? 'Registrar descarte' : 'Registrar consumo'),
          ),
        ),
      ],
    );
  }
}
