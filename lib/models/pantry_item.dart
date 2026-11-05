import '../constants/categories.dart';
import '../services/app_settings_service.dart';

class PantryItem {
  final int? id;
  final String name;
  final double quantity;
  final String unit;
  final DateTime? expiryDate;
  final String category;
  final bool inShoppingList;

  const PantryItem({
    this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    this.expiryDate,
    this.category = AppConstants.defaultCategory,
    this.inShoppingList = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name.trim(),
        'quantity': quantity,
        'unit': unit,
        'expiry_date': expiryDate?.toIso8601String(),
        'category': category,
        'in_shopping_list': inShoppingList ? 1 : 0,
      };

  factory PantryItem.fromMap(Map<String, Object?> map) {
    final expiryDateStr = map['expiry_date'] as String?;
    return PantryItem(
      id: map['id'] as int?,
      name: map['name'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      unit: map['unit'] as String,
      expiryDate:
          expiryDateStr != null ? DateTime.tryParse(expiryDateStr) : null,
      category: map['category'] as String? ?? AppConstants.defaultCategory,
      inShoppingList: (map['in_shopping_list'] as int? ?? 0) == 1,
    );
  }

  PantryItem copyWith({
    int? id,
    String? name,
    double? quantity,
    String? unit,
    DateTime? expiryDate,
    bool clearExpiryDate = false,
    String? category,
    bool? inShoppingList,
  }) =>
      PantryItem(
        id: id ?? this.id,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        expiryDate: clearExpiryDate ? null : expiryDate ?? this.expiryDate,
        category: category ?? this.category,
        inShoppingList: inShoppingList ?? this.inShoppingList,
      );

  double quantityAfterConsuming(double amount) {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Quantidade inválida');
    }
    final remaining = quantity - amount;
    final tolerance = quantity.abs() * 1e-12;
    if (remaining < -tolerance) {
      throw StateError('Quantidade maior que o estoque');
    }
    return remaining.abs() <= tolerance ? 0 : remaining;
  }

  bool isExpiringSoon({int? warningDays}) {
    if (expiryDate == null) return false;
    final limit = warningDays ?? AppSettingsService.instance.expiryWarningDays;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysUntilExpiry =
        DateTime(expiryDate!.year, expiryDate!.month, expiryDate!.day)
            .difference(today)
            .inDays;
    return daysUntilExpiry >= 0 && daysUntilExpiry <= limit;
  }

  bool isExpired() {
    if (expiryDate == null) return false;
    final now = DateTime.now();
    return expiryDate!.isBefore(DateTime(now.year, now.month, now.day));
  }
}
