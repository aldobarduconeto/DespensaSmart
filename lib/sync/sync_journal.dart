import 'dart:convert';
import 'dart:math';
import '../models/pantry_item.dart';

String randomSyncId() {
  final random = Random.secure();
  return List.generate(24, (_) => random.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Histórico convergente: a união por ID é idempotente; consumo e compra
/// são operações, evitando sobrescrever alterações simultâneas de estoque.
class SyncJournal {
  final String device;
  int clock;
  final Map<String, Map<String, dynamic>> events;
  final Map<String, int> localIds;
  Map<String, PantryItem>? _materialized;
  SyncJournal(
      {String? device,
      this.clock = 0,
      Map<String, Map<String, dynamic>>? events,
      Map<String, int>? localIds})
      : device = device ?? randomSyncId(),
        events = events ?? {},
        localIds = localIds ?? {};

  factory SyncJournal.decode(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final journal = SyncJournal(
        device: data['device'] as String,
        clock: data['clock'] as int,
        localIds: Map<String, int>.from(data['ids'] as Map));
    journal.merge(data['events'] as List);
    return journal;
  }

  String encode() => jsonEncode({
        'device': device,
        'clock': clock,
        'ids': localIds,
        'events': events.values.toList()
      });

  static void validate(Map<String, dynamic> event) {
    final id = event['id'];
    final key = event['key'];
    final time = event['clock'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 160 ||
        key is! String ||
        key.isEmpty ||
        key.length > 240 ||
        time is! int ||
        time < 0 ||
        time > 9000000000000000 ||
        ![
          'add',
          'edit',
          'consume',
          'restock',
          'shopping',
          'delete',
          'family_member'
        ]
            .contains(event['type'])) {
      throw const FormatException('Alteração de sincronização inválida');
    }
    if (event['type'] == 'add' || event['type'] == 'edit') {
      final item =
          PantryItem.fromMap(Map<String, Object?>.from(event['item'] as Map));
      if (item.name.trim().isEmpty ||
          item.name.length > 200 ||
          !item.quantity.isFinite ||
          item.quantity < 0 ||
          item.unit.length > 40 ||
          item.category.length > 100) {
        throw const FormatException('Item inválido');
      }
    }
    if (event['type'] == 'consume' || event['type'] == 'restock') {
      final amount = event['amount'];
      if (amount is! num || !amount.isFinite || amount <= 0)
        throw const FormatException('Quantidade inválida');
      final expiry = event['expiry'];
      if (expiry != null &&
          (expiry is! String || DateTime.tryParse(expiry) == null))
        throw const FormatException('Validade inválida');
    }
    if (event['type'] == 'shopping' && event['value'] is! bool)
      throw const FormatException('Lista inválida');
    if (event['date'] != null &&
        (event['date'] is! String ||
            DateTime.tryParse(event['date']) == null)) {
      throw const FormatException('Data inválida');
    }
    if (event['type'] == 'family_member' &&
        (event['person'] is! String ||
            (event['person'] as String).trim().isEmpty ||
            (event['person'] as String).length > 50 ||
            event['active'] is! bool ||
            !key.startsWith('family:'))) {
      throw const FormatException('Pessoa da casa inválida');
    }
    if (event['person'] != null &&
        (event['type'] != 'consume' && event['type'] != 'family_member' ||
            event['person'] is! String ||
            (event['person'] as String).trim().isEmpty ||
            (event['person'] as String).length > 50)) {
      throw const FormatException('Pessoa responsável inválida');
    }
    if (event['receipt'] != null) {
      final price = event['unitPriceCents'];
      final discount = event['discountCents'];
      if (event['type'] != 'restock' ||
          event['receipt'] is! String ||
          event['date'] == null ||
          event['name'] is! String ||
          event['unit'] is! String ||
          price is! int ||
          price < 0 ||
          discount is! int ||
          discount < 0 ||
          discount > ((event['amount'] as num) * price).round()) {
        throw const FormatException('Compra inválida');
      }
    }
  }

  bool merge(List<dynamic> incoming) {
    if (incoming.length > 20000)
      throw const FormatException('Histórico muito grande');
    final additions = <String, Map<String, dynamic>>{};
    for (final raw in incoming) {
      final event = Map<String, dynamic>.from(raw as Map);
      validate(event);
      final id = event['id'] as String;
      // Um ID identifica conteúdo imutável. Conflitos são rejeitados.
      final existing = events[id] ?? additions[id];
      if (existing != null && _canonical(existing) != _canonical(event)) {
        throw const FormatException('Identificador de alteração conflitante');
      }
      if (existing == null) additions[id] = event;
    }
    if (events.length + additions.length > 20000)
      throw const FormatException('Limite de histórico atingido');
    if (additions.isNotEmpty) _materialized = null;
    events.addAll(additions);
    for (final event in additions.values) {
      clock = max(clock, event['clock'] as int);
    }
    return additions.isNotEmpty;
  }

  bool get hasFamilyMemberEvents =>
      events.values.any((event) => event['type'] == 'family_member');

  List<String> familyMembers() {
    final ordered = events.values
        .where((event) => event['type'] == 'family_member')
        .toList()
      ..sort((a, b) {
        final order = (a['clock'] as int).compareTo(b['clock'] as int);
        return order != 0
            ? order
            : (a['id'] as String).compareTo(b['id'] as String);
      });
    final members = <String, String>{};
    for (final event in ordered) {
      final key = (event['person'] as String).toLowerCase();
      if (event['active'] == true) {
        members[key] = event['person'] as String;
      } else {
        members.remove(key);
      }
    }
    return members.values.toList()..sort();
  }

  static String _canonical(Map<String, dynamic> value) {
    Object? sort(Object? v) {
      if (v is Map)
        return {
          for (final k in v.keys.map((e) => e.toString()).toList()..sort())
            k: sort(v[k])
        };
      if (v is List) return v.map(sort).toList();
      return v;
    }

    return jsonEncode(sort(value));
  }

  void append(String type, String key,
      [Map<String, dynamic> payload = const {}]) {
    final next = clock + 1;
    merge([
      {
        'id': '$device:$next',
        'clock': next,
        'key': key,
        'type': type,
        ...payload
      }
    ]);
  }

  Map<String, PantryItem> materialize() {
    if (_materialized != null) return _materialized!;
    final ordered = events.values.toList()
      ..sort((a, b) {
        final order = (a['clock'] as int).compareTo(b['clock'] as int);
        return order != 0
            ? order
            : (a['id'] as String).compareTo(b['id'] as String);
      });
    final items = <String, PantryItem>{};
    for (final event in ordered) {
      final key = event['key'] as String;
      final current = items[key];
      switch (event['type']) {
        case 'add':
          items.putIfAbsent(
              key,
              () => PantryItem.fromMap(
                  Map<String, Object?>.from(event['item'] as Map)));
          break;
        case 'edit':
          if (current != null)
            items[key] = PantryItem.fromMap(
                Map<String, Object?>.from(event['item'] as Map));
          break;
        case 'consume':
          if (current != null) {
            final remainder =
                current.quantity - (event['amount'] as num).toDouble();
            final quantity =
                remainder <= current.quantity.abs() * 1e-12 ? 0.0 : remainder;
            items[key] = current.copyWith(
                quantity: quantity,
                inShoppingList: quantity == 0 || current.inShoppingList);
          }
          break;
        case 'restock':
          if (current != null) {
            final quantity =
                current.quantity + (event['amount'] as num).toDouble();
            if (!quantity.isFinite)
              throw const FormatException('Estoque fora do limite');
            items[key] = current.copyWith(
                quantity: quantity,
                inShoppingList: false,
                expiryDate: event['expiry'] == null
                    ? null
                    : DateTime.parse(event['expiry'] as String),
                clearExpiryDate: event['expiry'] == null);
          }
          break;
        case 'shopping':
          if (current != null)
            items[key] =
                current.copyWith(inShoppingList: event['value'] as bool);
          break;
        case 'delete':
          items.remove(key);
          break;
        case 'family_member':
          break;
      }
    }
    var nextId = localIds.values.fold<int>(0, max);
    for (final key in items.keys) {
      localIds.putIfAbsent(key, () => ++nextId);
      final item = items[key]!;
      items[key] = item.copyWith(id: localIds[key]);
    }
    return _materialized = Map.unmodifiable(items);
  }
}
