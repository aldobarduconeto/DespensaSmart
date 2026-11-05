import 'package:flutter/material.dart';
import '../../models/pantry_item.dart';
import '../../models/purchase_line.dart';

Future<PurchaseLine?> showPurchaseDialog(BuildContext context, PantryItem item,
        {PurchaseLine? initial}) =>
    showDialog<PurchaseLine>(
        context: context,
        builder: (_) => _PurchaseDialog(item: item, initial: initial));

class _PurchaseDialog extends StatefulWidget {
  final PantryItem item;
  final PurchaseLine? initial;
  const _PurchaseDialog({required this.item, this.initial});
  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  final _form = GlobalKey<FormState>();
  late final _amount =
      TextEditingController(text: '${widget.initial?.amount ?? 1}');
  late final _price = TextEditingController(
      text: widget.initial == null
          ? ''
          : (widget.initial!.unitPriceCents / 100).toStringAsFixed(2));
  late final _discount = TextEditingController(
      text: ((widget.initial?.discountCents ?? 0) / 100).toStringAsFixed(2));
  double? _number(String? s) =>
      double.tryParse((s ?? '').trim().replaceAll(',', '.'));
  int _cents(TextEditingController c) => (_number(c.text)! * 100).round();
  @override
  void dispose() {
    _amount.dispose();
    _price.dispose();
    _discount.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label,
          {bool positive = false, bool discount = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: label),
              validator: (s) {
                final n = _number(s);
                if (n == null ||
                    !n.isFinite ||
                    n < 0 ||
                    (positive && n == 0) ||
                    n > 100000000) return 'Informe um valor válido';
                if (!positive &&
                    !RegExp(r'^\d+([.,]\d{1,2})?$').hasMatch(s!.trim()))
                  return 'Use até duas casas decimais';
                if (discount) {
                  final amount = _number(_amount.text);
                  final price = _number(_price.text);
                  if (amount != null &&
                      price != null &&
                      n * 100 > (amount * price * 100).round())
                    return 'Desconto maior que o valor dos produtos';
                }
                return null;
              }));
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.item.name),
          content: SingleChildScrollView(
              child: Form(
                  key: _form,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _field(_amount, 'Quantidade (${widget.item.unit})',
                        positive: true),
                    _field(_price, 'Preço por ${widget.item.unit} (R\$)'),
                    _field(_discount, 'Desconto total deste produto (R\$)',
                        discount: true),
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () {
                  if (!_form.currentState!.validate()) return;
                  Navigator.pop(
                      context,
                      PurchaseLine(
                          item: widget.item,
                          amount: _number(_amount.text)!,
                          unitPriceCents: _cents(_price),
                          discountCents: _cents(_discount)));
                },
                child: const Text('Salvar no carrinho'))
          ]);
}
