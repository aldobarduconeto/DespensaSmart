class ValidationService {
  static String? validateNotEmpty(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'Digite $fieldName';
    }
    return null;
  }

  static String? validateQuantity(String? value) {
    final quantity = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (quantity == null || !quantity.isFinite || quantity < 0) {
      return 'Informe uma quantidade igual ou maior que zero';
    }
    return null;
  }

  static String? validatePositiveNumber(String? value, String fieldName) {
    final number = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (number == null || !number.isFinite || number < 0) {
      return 'Informe um valor válido para $fieldName';
    }
    return null;
  }
}
