import 'package:flutter/foundation.dart';

class LanSync extends ChangeNotifier {
  static final instance = LanSync();
  bool get supported => false;
  bool get enabled => false;
  bool get busy => false;
  String get code => '';
  String get manualPeer => '';
  List<String> get addresses => [];
  String get status =>
      'O compartilhamento local requer o aplicativo instalado.';
  DateTime? get lastSync => null;
  Future<void> initialize() async {}
  Future<void> configure(
      {required bool enabled,
      required String code,
      required String peer}) async {}
  Future<void> syncNow() async {}
  Future<void> stop() async {}
}
