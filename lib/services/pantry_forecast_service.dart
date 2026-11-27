import '../models/pantry_item.dart';
import '../models/purchase_line.dart';

enum StockDepletionLevel {
  outOfStock,
  critical,
  warning,
  comfortable,
  untracked;

  String get label => switch (this) {
        StockDepletionLevel.outOfStock => 'Esgotado',
        StockDepletionLevel.critical => 'Crítico (menos de 3 dias)',
        StockDepletionLevel.warning => 'Atenção (acaba em breve)',
        StockDepletionLevel.comfortable => 'Estoque confortável',
        StockDepletionLevel.untracked => 'Sem histórico suficiente',
      };
}

class ItemDepletionForecast {
  const ItemDepletionForecast({
    required this.item,
    required this.dailyVelocity,
    required this.daysRemaining,
    required this.estimatedRunoutDate,
    required this.level,
    required this.totalConsumedInWindow,
  });

  final PantryItem item;
  final double dailyVelocity;
  final int? daysRemaining;
  final DateTime? estimatedRunoutDate;
  final StockDepletionLevel level;
  final double totalConsumedInWindow;

  String get badgeText {
    if (item.quantity <= 0) return 'Esgotado';
    if (daysRemaining == null) return 'Novo no estoque';
    if (daysRemaining! <= 0) return 'Acaba hoje!';
    if (daysRemaining == 1) return 'Dura ~1 dia';
    return 'Dura ~$daysRemaining dias';
  }

  String get velocityText {
    if (dailyVelocity <= 0) return 'Sem consumo recente';
    return '${quantity(dailyVelocity)} ${item.unit}/dia';
  }
}

class PantryForecastService {
  PantryForecastService._();
  static final instance = PantryForecastService._();

  // Calculation window in days (last 45 days gives a stable consumption velocity)
  static const int _historyWindowDays = 45;

  List<ItemDepletionForecast> calculateForecasts({
    required List<PantryItem> items,
    required List<Map<String, dynamic>> rawEvents,
  }) {
    final now = DateTime.now();
    final windowStart = now.subtract(const Duration(days: _historyWindowDays));

    // Aggregate consumption amounts and earliest/latest dates per product
    final consumedTotals = <String, double>{};
    final consumptionEvents = <String, List<DateTime>>{};

    for (var i = 0; i < rawEvents.length; i++) {
      final event = rawEvents[i];
      if (event['type'] != 'consume') continue;

      final dateStr = event['date'] as String?;
      if (dateStr == null || dateStr.isEmpty) continue;
      final date = DateTime.tryParse(dateStr)?.toLocal();
      if (date == null || date.isBefore(windowStart) || date.isAfter(now)) continue;

      final name = (event['name'] as String? ?? event['key'] as String? ?? '').trim().toLowerCase();
      if (name.isEmpty) continue;

      final amount = (event['amount'] as num?)?.toDouble() ?? 0.0;
      consumedTotals[name] = (consumedTotals[name] ?? 0.0) + amount;
      consumptionEvents.putIfAbsent(name, () => []).add(date);
    }

    final forecasts = <ItemDepletionForecast>[];

    for (final item in items) {
      final nameLower = item.name.trim().toLowerCase();
      final totalConsumed = consumedTotals[nameLower] ?? 0.0;
      final events = consumptionEvents[nameLower] ?? const [];

      if (item.quantity <= 0) {
        forecasts.add(ItemDepletionForecast(
          item: item,
          dailyVelocity: totalConsumed / _historyWindowDays,
          daysRemaining: 0,
          estimatedRunoutDate: now,
          level: StockDepletionLevel.outOfStock,
          totalConsumedInWindow: totalConsumed,
        ));
        continue;
      }

      if (totalConsumed <= 0 || events.isEmpty) {
        forecasts.add(ItemDepletionForecast(
          item: item,
          dailyVelocity: 0.0,
          daysRemaining: null,
          estimatedRunoutDate: null,
          level: StockDepletionLevel.untracked,
          totalConsumedInWindow: 0.0,
        ));
        continue;
      }

      // Calculate days between first and last recorded consumption in window
      final sortedDates = List<DateTime>.from(events)..sort();
      final spanDays = (now.difference(sortedDates.first).inDays + 1).clamp(3, _historyWindowDays);
      final velocity = totalConsumed / spanDays;

      if (velocity <= 0.00001) {
        forecasts.add(ItemDepletionForecast(
          item: item,
          dailyVelocity: 0.0,
          daysRemaining: null,
          estimatedRunoutDate: null,
          level: StockDepletionLevel.untracked,
          totalConsumedInWindow: totalConsumed,
        ));
        continue;
      }

      final days = (item.quantity / velocity).floor();
      final runoutDate = now.add(Duration(days: days));

      final StockDepletionLevel level;
      if (days <= 3) {
        level = StockDepletionLevel.critical;
      } else if (days <= 7) {
        level = StockDepletionLevel.warning;
      } else {
        level = StockDepletionLevel.comfortable;
      }

      forecasts.add(ItemDepletionForecast(
        item: item,
        dailyVelocity: velocity,
        daysRemaining: days,
        estimatedRunoutDate: runoutDate,
        level: level,
        totalConsumedInWindow: totalConsumed,
      ));
    }

    forecasts.sort((a, b) {
      // Prioritize out of stock, then critical, then warning
      final aWeight = _levelWeight(a.level);
      final bWeight = _levelWeight(b.level);
      if (aWeight != bWeight) return aWeight.compareTo(bWeight);
      final aDays = a.daysRemaining ?? 99999;
      final bDays = b.daysRemaining ?? 99999;
      return aDays.compareTo(bDays);
    });

    return forecasts;
  }

  int _levelWeight(StockDepletionLevel level) => switch (level) {
        StockDepletionLevel.outOfStock => 0,
        StockDepletionLevel.critical => 1,
        StockDepletionLevel.warning => 2,
        StockDepletionLevel.comfortable => 3,
        StockDepletionLevel.untracked => 4,
      };
}
