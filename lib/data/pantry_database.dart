import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pantry_item.dart';
import '../models/purchase_line.dart';
import '../services/app_settings_service.dart';
import '../sync/sync_journal.dart';

class PantryDatabase {
  PantryDatabase._() : _storageKey = journalKey;
  @visibleForTesting
  PantryDatabase.isolated(this._storageKey);
  final String _storageKey;
  static final instance = PantryDatabase._();
  static const journalKey = 'pantry_sync_journal_v1';
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  Future<void> _pending = Future.value();
  String? _cachedRaw;
  SyncJournal? _cachedJournal;

  Future<T> _run<T>(Future<T> Function(SyncJournal) action,
      {bool readOnly = false}) {
    final result = _pending.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      final journal = raw != null && raw == _cachedRaw && _cachedJournal != null
          ? _cachedJournal!
          : raw == null
              ? SyncJournal()
              : SyncJournal.decode(raw);
      if (readOnly && raw == null) return action(journal);
      if (readOnly && raw != null) {
        _cachedRaw = raw;
        _cachedJournal = journal;
        return action(journal);
      }
      final before = journal.encode();
      final value = await action(journal);
      journal.materialize();
      final after = journal.encode();
      if (raw == null || before != after) {
        if (!await prefs.setString(_storageKey, after)) {
          throw StateError('Não foi possível salvar a despensa');
        }
        _changes.add(null);
      }
      _cachedRaw = after;
      _cachedJournal = journal;
      return value;
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {
      _cachedRaw = null;
      _cachedJournal = null;
    });
    return result;
  }

  Future<List<PantryItem>> allItems() => _run(
      (journal) async => journal.materialize().values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      readOnly: true);

  Future<List<dynamic>> exportChanges() =>
      _run((journal) async => journal.events.values.toList(), readOnly: true);

  Future<List<String>> familyMembers() =>
      _run((journal) async => journal.familyMembers(), readOnly: true);

  Future<bool> hasFamilyMemberEvents() =>
      _run((journal) async => journal.hasFamilyMemberEvents, readOnly: true);

  Future<void> setFamilyMembers(List<String> members) =>
      _run((journal) async {
        final existing = journal.familyMembers();
        final desiredByKey = {
          for (final name in members) name.toLowerCase(): name,
        };
        final existingByKey = {
          for (final name in existing) name.toLowerCase(): name,
        };
        for (final entry in desiredByKey.entries) {
          if (existingByKey.containsKey(entry.key)) continue;
          journal.append(
            'family_member',
            'family:${entry.key}',
            {'person': entry.value, 'active': true},
          );
        }
        for (final entry in existingByKey.entries) {
          if (desiredByKey.containsKey(entry.key)) continue;
          journal.append(
            'family_member',
            'family:${entry.key}',
            {'person': entry.value, 'active': false},
          );
        }
      });

  Future<String> exportBackupJson() =>
      _run((journal) async => journal.encode(), readOnly: true);

  Future<void> importBackupJson(String raw, {bool replace = false}) =>
      _run((journal) async {
        final imported = SyncJournal.decode(raw);
        if (replace) {
          journal.events.clear();
          journal.localIds.clear();
          journal.clock = 0;
        }
        journal.merge(imported.events.values.toList());
      });

  Future<bool> mergeChanges(List<dynamic> incoming) => incoming.isEmpty
      ? Future.value(false)
      : _run((journal) async => journal.merge(incoming));

  PantryItem _validate(PantryItem item) {
    if (item.name.trim().isEmpty ||
        item.name.length > 200 ||
        !item.quantity.isFinite ||
        item.quantity < 0) {
      throw ArgumentError('Item inválido');
    }
    final autoShop = AppSettingsService.instance.autoAddToShoppingListOnZero;
    return item.copyWith(
        name: item.name.trim(),
        inShoppingList:
            (autoShop && item.quantity == 0) || item.inShoppingList);
  }

  String _keyFor(SyncJournal journal, int id) {
    return journal
        .materialize()
        .entries
        .firstWhere((e) => e.value.id == id,
            orElse: () => throw StateError('Item não encontrado'))
        .key;
  }

  Future<void> add(PantryItem item) => _run((journal) async {
        final normalized = _validate(item);
        if (journal
            .materialize()
            .values
            .any((e) => e.name.toLowerCase() == normalized.name.toLowerCase())) {
          throw StateError('Item já existe');
        }
        var key = normalized.name.toLowerCase();
        if (journal.materialize().containsKey(key)) key = randomSyncId();
        journal.append('add', key, {'item': normalized.toMap()});
      });

  Future<void> update(PantryItem item) => _run((journal) async {
        final normalized = _validate(item);
        final key = _keyFor(journal, item.id!);
        if (journal.materialize().entries.any((e) =>
            e.key != key &&
            e.value.name.toLowerCase() == normalized.name.toLowerCase())) {
          throw StateError('Item já existe');
        }
        journal.append('edit', key, {'item': normalized.toMap()});
      });

  Future<void> delete(int id) => _run((journal) async {
        journal.append('delete', _keyFor(journal, id));
      });

  Future<int> deleteOutOfStockItems() => _run((journal) async {
        final emptyKeys = journal
            .materialize()
            .entries
            .where((e) => e.value.quantity == 0)
            .map((e) => e.key)
            .toList();
        for (final key in emptyKeys) {
          journal.append('delete', key);
        }
        return emptyKeys.length;
      });

  Future<int> clearShoppingList() => _run((journal) async {
        final shoppingKeys = journal
            .materialize()
            .entries
            .where((e) => e.value.inShoppingList)
            .map((e) => e.key)
            .toList();
        for (final key in shoppingKeys) {
          journal.append('shopping', key, {'value': false});
        }
        return shoppingKeys.length;
      });

  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    _cachedRaw = null;
    _cachedJournal = null;
    _changes.add(null);
  }

  Future<void> consume(
    int id,
    double amount, {
    String? person,
  }) =>
      _run((journal) async {
        final key = _keyFor(journal, id);
        final current = journal.materialize()[key]!;
        final remaining = current.quantityAfterConsuming(amount);
        journal.append('consume', key, {
          'amount': amount,
          'date': DateTime.now().toIso8601String(),
          'name': current.name,
          'unit': current.unit,
          if (person != null) 'person': person.trim(),
        });
        if (remaining == 0 &&
            !AppSettingsService.instance.autoAddToShoppingListOnZero &&
            !current.inShoppingList) {
          journal.append('shopping', key, {'value': false});
        }
      });

  Future<void> checkout(List<PurchaseLine> lines) => _run((journal) async {
        if (lines.isEmpty) throw ArgumentError('Carrinho vazio');
        final date = DateTime.now().toIso8601String();
        final receipt = randomSyncId();
        final entries = <Map<String, dynamic>>[];
        for (final line in lines) {
          line.validate();
          final key = _keyFor(journal, line.item.id!);
          final item = journal.materialize()[key]!;
          entries.add({
            'key': key,
            'amount': line.amount,
            'expiry': null,
            'date': date,
            'receipt': receipt,
            'name': item.name,
            'unit': item.unit,
            'unitPriceCents': line.unitPriceCents,
            'discountCents': line.discountCents
          });
        }
        final batch = SyncJournal.decode(journal.encode());
        for (final entry in entries) {
          batch.append('restock', entry['key'] as String, entry);
        }
        batch.materialize();
        journal.merge(batch.events.values.toList());
      });

  Future<void> restock(int id, double amount, DateTime? expiry) =>
      _run((journal) async {
        final key = _keyFor(journal, id);
        if (!amount.isFinite || amount <= 0) {
          throw ArgumentError('Quantidade inválida');
        }
        journal.append('restock', key,
            {'amount': amount, 'expiry': expiry?.toIso8601String()});
      });

  Future<List<PantryItem>> getShoppingList() async =>
      (await allItems()).where((e) => e.inShoppingList).toList();
  Future<void> toggleShoppingList(int id) => _run((journal) async {
        final key = _keyFor(journal, id);
        journal.append('shopping', key,
            {'value': !journal.materialize()[key]!.inShoppingList});
      });
}
