import '../models/pantry_item.dart';

class ExpiryNotice {
  final int id;
  final DateTime date;
  final String body;
  const ExpiryNotice(this.id, this.date, this.body);
  String get signature => '${date.year}-${date.month}-${date.day}-${date.hour}:$body';
}

/// Até 60 resumos (abaixo do limite de 64 notificações pendentes do iOS).
/// Datas civis evitam erros de duração em mudanças de horário de verão.
List<ExpiryNotice> planExpiryNotices(
  List<PantryItem> items,
  DateTime now, {
  int warningDays = 7,
  int reminderHour = 9,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final days = <DateTime, List<PantryItem>>{};
  final span = warningDays.clamp(1, 30);
  final hour = reminderHour.clamp(0, 23);

  for (final item in items) {
    if (item.quantity <= 0 || item.expiryDate == null) continue;
    final expiry = item.expiryDate!;
    final end = DateTime(expiry.year, expiry.month, expiry.day);
    for (var offset = span; offset >= 0; offset--) {
      final day = DateTime(end.year, end.month, end.day - offset);
      if (day.isBefore(today)) continue;
      days.putIfAbsent(day, () => []).add(item);
    }
  }
  final dates = days.keys.toList()..sort();
  return dates.take(60).map((day) {
    final products = days[day]!
      ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
    final names = products.take(3).map((item) {
      final expiry = item.expiryDate!;
      final sameDay = expiry.year == day.year &&
          expiry.month == day.month &&
          expiry.day == day.day;
      return '${item.name} (${sameDay ? 'vence hoje' : 'vence ${expiry.day}/${expiry.month}'})';
    }).join(', ');
    final extra =
        products.length > 3 ? ' e mais ${products.length - 3}' : '';
    return ExpiryNotice(
      int.parse(
          '${day.year}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}'),
      DateTime(day.year, day.month, day.day, hour),
      '$names$extra. Toque para ver receitas e aproveitar sua despensa.',
    );
  }).toList();
}
