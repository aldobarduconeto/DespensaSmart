class MonthlyConsumption {
  final Map<String, Map<String, double>> byUnit = {};
  final int days;
  MonthlyConsumption(Iterable<Map<String, dynamic>> events, DateTime month,
      {DateTime? now})
      : days = _days(month, now ?? DateTime.now()) {
    for (final event in events) {
      if (event['type'] != 'consume') continue;
      final date = DateTime.tryParse(event['date'] as String? ?? '')?.toLocal();
      if (date == null || date.year != month.year || date.month != month.month)
        continue;
      final amount = (event['amount'] as num).toDouble();
      final unit = event['unit'] as String? ?? 'unidade não informada';
      final name = event['name'] as String? ?? event['key'] as String;
      final products = byUnit.putIfAbsent(unit, () => {});
      products[name] = (products[name] ?? 0) + amount;
    }
  }
  static int _days(DateTime month, DateTime now) =>
      month.year == now.year && month.month == now.month
          ? now.day
          : DateTime(month.year, month.month + 1, 0).day;
  List<String> extremes(String unit, {required bool most}) {
    final products = byUnit[unit]!;
    final value = products.values
        .reduce((a, b) => most ? (a > b ? a : b) : (a < b ? a : b));
    return products.keys
        .where((name) => (products[name]! - value).abs() < 1e-9)
        .toList()
      ..sort();
  }

  double dailyAverage(String unit) =>
      byUnit[unit]!.values.fold<double>(0, (a, b) => a + b) / days;
}
