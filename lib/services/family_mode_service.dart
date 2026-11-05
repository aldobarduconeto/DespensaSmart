import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/pantry_database.dart';
import '../sync/lan_sync.dart';

class FamilyModeService {
  FamilyModeService._();

  static final instance = FamilyModeService._();

  static const _enabledKey = 'family_mode_enabled_v1';
  static const _membersKey = 'family_mode_members_v1';

  bool configuredEnabled = false;
  List<String> members = [];
  bool loaded = false;

  bool get available =>
      configuredEnabled && LanSync.instance.enabled && members.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    configuredEnabled = prefs.getBool(_enabledKey) ?? false;
    final raw = prefs.getString(_membersKey);
    if (raw == null) {
      members = [];
    } else {
      final values = jsonDecode(raw);
      if (values is! List || values.any((value) => value is! String)) {
        throw const FormatException('A lista de pessoas da casa é inválida.');
      }
      members = values.cast<String>();
    }
    if (LanSync.instance.enabled &&
        await PantryDatabase.instance.hasFamilyMemberEvents()) {
      members = await PantryDatabase.instance.familyMembers();
      await prefs.setString(_membersKey, jsonEncode(members));
    }
    loaded = true;
  }

  Future<void> setEnabled(bool value) async {
    if (value && !LanSync.instance.enabled) {
      throw StateError(
        'Ative e configure a sincronização com a casa antes de ativar o modo família.',
      );
    }
    if (value && members.isEmpty) {
      throw StateError('Cadastre ao menos uma pessoa da casa.');
    }
    if (value) {
      await PantryDatabase.instance.setFamilyMembers(members);
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_enabledKey, value)) {
      throw StateError('Não foi possível salvar o modo família.');
    }
    configuredEnabled = value;
  }

  Future<void> saveMembers(List<String> values) async {
    final normalized = <String>[];
    for (final value in values) {
      final name = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (name.isEmpty) continue;
      if (name.length > 50) {
        throw ArgumentError('Cada nome pode ter no máximo 50 caracteres.');
      }
      if (!normalized.any((existing) =>
          existing.toLowerCase() == name.toLowerCase())) {
        normalized.add(name);
      }
    }
    if (normalized.length > 30) {
      throw ArgumentError('Cadastre no máximo 30 pessoas.');
    }
    if (configuredEnabled && normalized.isEmpty) {
      throw StateError(
        'Cadastre ao menos uma pessoa ou desative o modo família.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_membersKey, jsonEncode(normalized))) {
      throw StateError('Não foi possível salvar as pessoas da casa.');
    }
    if (LanSync.instance.enabled) {
      await PantryDatabase.instance.setFamilyMembers(normalized);
    }
    members = normalized;
  }
}
