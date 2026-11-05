import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../data/pantry_database.dart';
import 'app_settings_service.dart';
import 'expiry_notice_planner.dart';

class ExpiryNotificationService extends ChangeNotifier
    with WidgetsBindingObserver {
  ExpiryNotificationService._();
  static final instance = ExpiryNotificationService._();
  static const _enabledKey = 'expiry_notifications_enabled_v1';
  static const _registryKey = 'expiry_notifications_registry_v1';
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;
  Future<void> _pending = Future.value();
  StreamSubscription<void>? _subscription;
  bool enabled = false;
  bool ready = false;
  String? error;
  int scheduledCount = 0;
  VoidCallback? onOpenRecipes;
  bool get supported =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }.contains(defaultTargetPlatform);

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    if (!supported) {
      notifyListeners();
      return;
    }
    try {
      tzdata.initializeTimeZones();
      await _updateTimezone();
      const darwin = DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false);
      await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('ic_stat_pantry'),
            iOS: darwin,
            macOS: darwin,
            windows: WindowsInitializationSettings(
                appName: 'Despensa Smart',
                appUserModelId: 'Com.Awesome.DespensaSmart',
                guid: '8efb31cb-33e3-43c8-84f5-7a55704a89ba'),
          ),
          onDidReceiveNotificationResponse: (response) {
            if (response.payload == 'expiry_recipes') onOpenRecipes?.call();
          });
      ready = true;
      WidgetsBinding.instance.addObserver(this);
      _subscription =
          PantryDatabase.instance.changes.listen((_) => unawaited(refresh()));
      AppSettingsService.instance.addListener(_onSettingsChanged);
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_enabledKey);
      enabled = saved ?? false;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true &&
          launch?.notificationResponse?.payload == 'expiry_recipes') {
        onOpenRecipes?.call();
      }
      await refresh();
    } catch (_) {
      error = 'Não foi possível iniciar os avisos. Tente ativá-los novamente.';
    }
    notifyListeners();
  }

  void _onSettingsChanged() {
    if (ready && enabled) unawaited(refresh());
  }

  Future<void> _updateTimezone() async {
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
  }

  Future<bool> _requestPermission() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin>()!
                .requestNotificationsPermission() ??
            false;
      case TargetPlatform.iOS:
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin>()!
                .requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      case TargetPlatform.macOS:
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin>()!
                .requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      default:
        return true;
    }
  }

  Future<void> setEnabled(bool value) async {
    await initialize();
    if (!supported) return;
    if (!ready) {
      _initializing = null;
      await initialize();
      if (!ready) return;
    }
    try {
      final granted = !value || await _requestPermission();
      enabled = value && granted;
      await (await SharedPreferences.getInstance())
          .setBool(_enabledKey, enabled);
      await refresh();
      if (!granted) {
        error =
            'Permissão negada. Autorize as notificações nas configurações do sistema e tente novamente.';
      }
    } catch (_) {
      error = 'Não foi possível alterar os avisos. Tente novamente.';
    }
    notifyListeners();
  }

  Future<bool> sendTestNotification() async {
    await initialize();
    if (!supported || !ready) return false;
    final granted = await _requestPermission();
    if (!granted) {
      error =
          'Permissão negada. Autorize as notificações nas configurações do sistema.';
      notifyListeners();
      return false;
    }
    await _plugin.show(
      id: 81999,
      title: 'Despensa Smart • Notificação de teste',
      body:
          'Seus alertas de validade, estoque e receitas estão funcionando perfeitamente!',
      payload: 'expiry_recipes',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'pantry_expiry_v1',
          'Validade dos produtos',
          channelDescription:
              'Lembretes para consumir produtos antes da validade',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(threadIdentifier: 'pantry_expiry'),
        macOS: DarwinNotificationDetails(threadIdentifier: 'pantry_expiry'),
      ),
    );
    error = null;
    notifyListeners();
    return true;
  }

  Future<void> refresh() {
    final result = _pending.then((_) => _refresh()).catchError((Object _) {
      error =
          'Não foi possível atualizar os avisos. Tente novamente nas configurações.';
      notifyListeners();
    });
    _pending = result;
    return result;
  }

  Future<void> _refresh() async {
    if (!ready) return;
    await _updateTimezone();
    final prefs = await SharedPreferences.getInstance();
    final registry = Map<String, String>.from(
        jsonDecode(prefs.getString(_registryKey) ?? '{}') as Map);
    final pending = (await _plugin.pendingNotificationRequests())
        .where((e) => e.payload == 'expiry_recipes')
        .toList();
    if (!enabled) {
      for (final id in {
        ...registry.keys.map(int.parse),
        ...pending.map((e) => e.id)
      }) {
        await _plugin.cancel(id: id);
      }
      await prefs.remove(_registryKey);
      scheduledCount = 0;
      error = null;
      notifyListeners();
      return;
    }
    final now = DateTime.now();
    final settings = AppSettingsService.instance;
    final plan = planExpiryNotices(
      await PantryDatabase.instance.allItems(),
      now,
      warningDays: settings.expiryWarningDays,
      reminderHour: settings.expiryReminderHour,
    );
    final ids = plan.map((e) => e.id).toSet();
    for (final id in {
      ...registry.keys.map(int.parse),
      ...pending.map((e) => e.id)
    }) {
      if (!ids.contains(id)) {
        await _plugin.cancel(id: id);
        registry.remove('$id');
      }
    }
    final pendingIds = pending.map((e) => e.id).toSet();
    for (final notice in plan) {
      final signature = '${tz.local.name}:${notice.signature}';
      if (registry['${notice.id}'] == signature &&
          (pendingIds.contains(notice.id) || !notice.date.isAfter(now))) {
        continue;
      }
      final date = notice.date.isAfter(now)
          ? notice.date
          : now.add(const Duration(minutes: 1));
      await _plugin.zonedSchedule(
          id: notice.id,
          title: 'Aproveite antes de vencer',
          body: notice.body,
          scheduledDate: tz.TZDateTime.from(date, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
                'pantry_expiry_v1', 'Validade dos produtos',
                channelDescription:
                    'Lembretes para consumir produtos antes da validade',
                importance: Importance.high,
                priority: Priority.high),
            iOS: DarwinNotificationDetails(threadIdentifier: 'pantry_expiry'),
            macOS: DarwinNotificationDetails(threadIdentifier: 'pantry_expiry'),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'expiry_recipes');
      registry['${notice.id}'] = signature;
      if (!await prefs.setString(_registryKey, jsonEncode(registry))) {
        throw StateError('Falha ao salvar avisos');
      }
    }
    await prefs.setString(_registryKey, jsonEncode(registry));
    scheduledCount = (await _plugin.pendingNotificationRequests())
        .where((e) => e.payload == 'expiry_recipes')
        .length;
    error = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppSettingsService.instance.removeListener(_onSettingsChanged);
    _subscription?.cancel();
    super.dispose();
  }
}
