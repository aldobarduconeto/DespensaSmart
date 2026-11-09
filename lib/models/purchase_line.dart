import 'pantry_item.dart';

String money(num value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
String quantity(num value) => value
    .toStringAsFixed(3)
    .replaceFirst(RegExp(r'\.?0+$'), '')
    .replaceAll('.', ',');

class PurchaseLine {
  final PantryItem item;
  final double amount;
  final int unitPriceCents;
  final int discountCents;
  const PurchaseLine(
      {required this.item,
      required this.amount,
      required this.unitPriceCents,
      required this.discountCents});
  int get grossCents => (amount * unitPriceCents).round();
  int get paidCents => grossCents - discountCents;
  void validate() {
    if (item.id == null ||
        !amount.isFinite ||
        amount <= 0 ||
        unitPriceCents < 0 ||
        discountCents < 0 ||
        discountCents > grossCents) {
      throw ArgumentError('Quantidade, preço ou desconto inválido');
    }
  }
}
