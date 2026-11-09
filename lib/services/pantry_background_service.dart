import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/pantry_item.dart';
import '../models/recipe.dart';
import '../data/pantry_database.dart';
import '../sync/sync_journal.dart';
import 'expiry_notification_service.dart';
import 'pantry_notification_plan.dart';
import 'recipe_service.dart';

@pragma('vm:entry-point')
void pantryCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await runPantryBackgroundCheck();
      return true;
    } catch (_) {
      return false;
    }
  });
}

const pantryEnabledKey = 'pantry_background_enabled_v1';
const pantryStockKey = 'pantry_background_stock_v1';
const pantryRecipesKey = 'pantry_background_recipes_v1';
const pantryThresholdsKey = 'pantry_stock_thresholds_v1';
const pantryRecipeInboxKey = 'pantry_recipe_inbox_v1';
const _stockSentKey = 'pantry_stock_notice_sent_v1';
const _recipeSentKey = 'pantry_recipe_notice_sent_v1';
const _recipeAttemptKey = 'pantry_recipe_attempt_v1';

Map<String, double> readThresholds(SharedPreferences prefs) =>
    (jsonDecode(prefs.getString(pantryThresholdsKey) ?? '{}') as Map).map(
        (key, value) => MapEntry(key as String, (value as num).toDouble()));

Future<void> initializePantryNotificationPlugin(
    FlutterLocalNotificationsPlugin plugin,
    {void Function(NotificationResponse)? onResponse}) async {
  const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false);
  await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_pantry'),
        iOS: darwin,
        macOS: darwin,
        windows: WindowsInitializationSettings(
            appName: 'Despensa Smart',
            appUserModelId: 'Com.Awesome.DespensaSmart',
            guid: '8efb31cb-33e3-43c8-84f5-7a55704a89ba'),
      ),
      onDidReceiveNotificationResponse: onResponse);
}

Future<void> runPantryBackgroundCheck(
    {bool forceRecipes = false,
    FlutterLocalNotificationsPlugin? initializedPlugin,
    @visibleForTesting
    Future<List<Recipe>> Function(PantryNotificationPlan)?
        fetchRecipes}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  if (!(prefs.getBool(pantryEnabledKey) ?? false)) return;
  final raw = prefs.getString(PantryDatabase.journalKey);
  final items = raw == null
      ? <PantryItem>[]
      : SyncJournal.decode(raw).materialize().values.toList();
  final now = DateTime.now();
  final defaultThreshold =
      (prefs.getDouble('settings_default_low_stock_v1') ?? 1.0).clamp(0.0, 1000.0);
  final warningDays =
      (prefs.getInt('settings_expiry_warning_days_v1') ?? 7).clamp(1, 60);
  final plan = PantryNotificationPlan(
    items,
    readThresholds(prefs),
    now,
    defaultThreshold: defaultThreshold,
    warningDays: warningDays,
  );
  final plugin = initializedPlugin ?? FlutterLocalNotificationsPlugin();
  if (initializedPlugin == null) {
    await initializePantryNotificationPlugin(plugin);
  }
  Future<void> show(int id, String title, String body, String payload) async {
    await plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
              id == stockNoticeId ? 'pantry_stock_v1' : 'pantry_recipes_v1',
              id == stockNoticeId
                  ? 'Estoque da despensa'
                  : 'Receitas da despensa',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              styleInformation: BigTextStyleInformation(body)),
          iOS: const DarwinNotificationDetails(
              threadIdentifier: 'pantry_digest'),
          macOS: const DarwinNotificationDetails(
              threadIdentifier: 'pantry_digest'),
        ));
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final next = DateTime(now.year, now.month, now.day + 1, 9);
      final day = DateTime(next.year, next.month, next.day);
      if (id == recipeNoticeId &&
          plan.available
              .any((e) => e.expiryDate != null && e.expiryDate!.isBefore(day))) {
        return;
      }
      await plugin.zonedSchedule(
          id: id + 100,
          title: title,
          body: body,
          scheduledDate: tz.TZDateTime.from(next, tz.local),
          notificationDetails: const NotificationDetails(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload);
    }
  }

  if (prefs.getBool(pantryStockKey) ?? true) {
    if (!plan.hasStockAlert) {
      await plugin.cancel(id: stockNoticeId);
      await plugin.cancel(id: stockNoticeId + 100);
      await prefs.remove(_stockSentKey);
    } else {
      final saved = jsonDecode(prefs.getString(_stockSentKey) ?? '{}') as Map;
      final last = DateTime.tryParse(saved['date'] as String? ?? '');
      if (saved['signature'] != plan.stockSignature ||
          last == null ||
          now.difference(last) >= const Duration(days: 1)) {
        await show(stockNoticeId, 'Confira o estoque da despensa',
            plan.stockBody, stockNoticePayload);
        await prefs.setString(
            _stockSentKey,
            jsonEncode({
              'signature': plan.stockSignature,
              'date': now.toIso8601String()
            }));
      }
    }
  }
  if (!(prefs.getBool(pantryRecipesKey) ?? true)) return;
  if (plan.available.isEmpty) {
    await plugin.cancel(id: recipeNoticeId);
    await plugin.cancel(id: recipeNoticeId + 100);
    await prefs.remove(pantryRecipeInboxKey);
    return;
  }
  final inboxRaw = prefs.getString(pantryRecipeInboxKey);
  if (inboxRaw != null) {
    final inbox = jsonDecode(inboxRaw) as Map;
    if (inbox['inventory'] != plan.inventorySignature) {
      await plugin.cancel(id: recipeNoticeId);
      await plugin.cancel(id: recipeNoticeId + 100);
    }
  }
  final lastAttempt =
      DateTime.tryParse(prefs.getString(_recipeAttemptKey) ?? '');
  if (!forceRecipes &&
      lastAttempt != null &&
      now.difference(lastAttempt) < const Duration(hours: 6)) {
    return;
  }
  await prefs.setString(_recipeAttemptKey, now.toIso8601String());
  final service = RecipeService();
  try {
    List<Recipe> recipes = await (fetchRecipes != null
            ? fetchRecipes(plan)
            : service.recommend(plan.available.map((e) => e.name).toList(),
                priorityIngredients: plan.priority.map((e) => e.name).toList()))
        .timeout(const Duration(seconds: 22));
    recipes = recipes.take(5).toList();
    final latest = await SharedPreferences.getInstance();
    await latest.reload();
    if (!(latest.getBool(pantryEnabledKey) ?? false) ||
        !(latest.getBool(pantryRecipesKey) ?? true)) {
      return;
    }
    final latestRaw = latest.getString(PantryDatabase.journalKey);
    final latestItems = latestRaw == null
        ? <PantryItem>[]
        : SyncJournal.decode(latestRaw).materialize().values.toList();
    final latestPlan = PantryNotificationPlan(
      latestItems,
      readThresholds(latest),
      DateTime.now(),
      defaultThreshold: defaultThreshold,
      warningDays: warningDays,
    );
    if (latestPlan.inventorySignature != plan.inventorySignature) {
      await latest.remove(_recipeAttemptKey);
      return;
    }
    if (recipes.isEmpty) {
      await plugin.cancel(id: recipeNoticeId);
      await plugin.cancel(id: recipeNoticeId + 100);
      await latest.remove(pantryRecipeInboxKey);
      return;
    }
    final data = {
      'date': now.toIso8601String(),
      'inventory': plan.inventorySignature,
      'priority': plan.priority.map((e) => e.name).toList(),
      'recipes': recipes.map(recipeToJson).toList()
    };
    await latest.setString(pantryRecipeInboxKey, jsonEncode(data));
    final sent = DateTime.tryParse(latest.getString(_recipeSentKey) ?? '');
    if (sent == null || now.difference(sent) >= const Duration(days: 1)) {
      final prefix = plan.priority.isEmpty
          ? 'Com os ingredientes disponíveis'
          : 'Aproveite ${plan.priority.take(3).map((e) => e.name).join(', ')}: estoque baixo ou validade próxima';
      await show(
          recipeNoticeId,
          '${recipes.length} receitas para sua despensa',
          '$prefix. ${recipes.map((e) => e.name).join(' • ')}. Toque para ver ingredientes e preparo.',
          recipeNoticePayload);
      await latest.setString(_recipeSentKey, now.toIso8601String());
    }
  } catch (_) {
    await prefs.setString(_recipeAttemptKey,
        now.subtract(const Duration(hours: 5)).toIso8601String());
  } finally {
    service.dispose();
  }
}

class PantryBackgroundService extends ChangeNotifier
    with WidgetsBindingObserver {
  PantryBackgroundService._();
  static final instance = PantryBackgroundService._();
  bool enabled = false;
  bool stockEnabled = true;
  bool recipesEnabled = true;
  bool ready = false;
  bool busy = false;
  String? error;
  Map<String, double> thresholds = {};
  StreamSubscription<void>? _subscription;
  Timer? _debounce;
  Timer? _timer;
  Future<void>? _initializing;
  final _plugin = FlutterLocalNotificationsPlugin();
  final navigation = ValueNotifier<String?>(null);
  bool get supported =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows
      }.contains(defaultTargetPlatform);
  bool get hasBackgroundWorker =>
      !kIsWeb &&
      {TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS}
          .contains(defaultTargetPlatform);
  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    if (!supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(pantryEnabledKey) ?? false;
      stockEnabled = prefs.getBool(pantryStockKey) ?? true;
      recipesEnabled = prefs.getBool(pantryRecipesKey) ?? true;
      thresholds = readThresholds(prefs);
      await initializePantryNotificationPlugin(_plugin,
          onResponse: (r) => _open(r.payload));
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _open(launch?.notificationResponse?.payload);
      }
      ExpiryNotificationService.instance.onOpenRecipes =
          () => _open('expiry_recipes');
      if (hasBackgroundWorker) {
        await Workmanager().initialize(pantryCallbackDispatcher);
      }
      ready = true;
      WidgetsBinding.instance.addObserver(this);
      _subscription = PantryDatabase.instance.changes.listen((_) {
        _debounce?.cancel();
        _debounce =
            Timer(const Duration(seconds: 2), () => unawaited(checkNow()));
      });
      _timer = Timer.periodic(
          const Duration(hours: 1), (_) => unawaited(checkNow()));
      await _schedule();
      if (enabled) unawaited(checkNow());
    } catch (_) {
      error = 'Não foi possível iniciar as notificações. Tente novamente.';
    }
    notifyListeners();
  }

  void _open(String? payload) {
    if ({stockNoticePayload, recipeNoticePayload, 'expiry_recipes'}
        .contains(payload)) {
      navigation.value = null;
      navigation.value = payload;
    }
  }

  Future<bool> _permission() async {
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

  Future<void> _schedule() async {
    if (!hasBackgroundWorker) return;
    if (enabled) {
      await Workmanager().registerPeriodicTask(
          backgroundTaskId, backgroundTaskId,
          frequency: const Duration(hours: 6),
          initialDelay: const Duration(minutes: 15),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep);
    } else {
      await Workmanager().cancelByUniqueName(backgroundTaskId);
    }
  }

  Future<void> setEnabled(bool value) async {
    await initialize();
    if (!ready) {
      _initializing = null;
      await initialize();
    }
    if (!ready || !supported) return;
    try {
      error = null;
      if (value && !await _permission()) {
        error =
            'Permissão negada. Autorize as notificações nas configurações do sistema.';
        notifyListeners();
        return;
      }
      enabled = value;
      await (await SharedPreferences.getInstance())
          .setBool(pantryEnabledKey, value);
      await _schedule();
      if (!value) {
        await _plugin.cancel(id: stockNoticeId);
        await _plugin.cancel(id: recipeNoticeId);
        await _plugin.cancel(id: stockNoticeId + 100);
        await _plugin.cancel(id: recipeNoticeId + 100);
      } else {
        await checkNow();
      }
    } catch (_) {
      error = 'Não foi possível alterar as notificações. Tente novamente.';
    }
    notifyListeners();
  }

  Future<void> setCategory({bool? stock, bool? recipes}) async {
    final prefs = await SharedPreferences.getInstance();
    if (stock != null) {
      stockEnabled = stock;
      await prefs.setBool(pantryStockKey, stock);
      if (!stock) {
        await _plugin.cancel(id: stockNoticeId);
        await _plugin.cancel(id: stockNoticeId + 100);
      }
    }
    if (recipes != null) {
      recipesEnabled = recipes;
      await prefs.setBool(pantryRecipesKey, recipes);
      if (!recipes) {
        await _plugin.cancel(id: recipeNoticeId);
        await _plugin.cancel(id: recipeNoticeId + 100);
      }
    }
    notifyListeners();
    await checkNow();
  }

  Future<void> setThreshold(PantryItem item, double amount) async {
    if (!amount.isFinite || amount < 0) throw ArgumentError('Limite inválido');
    thresholds['${item.id}'] = amount;
    await (await SharedPreferences.getInstance())
        .setString(pantryThresholdsKey, jsonEncode(thresholds));
    notifyListeners();
    await checkNow();
  }

  Future<void> clearCustomThresholds() async {
    thresholds.clear();
    await (await SharedPreferences.getInstance()).remove(pantryThresholdsKey);
    notifyListeners();
    await checkNow();
  }

  Future<void> clearRecipeInbox() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(pantryRecipeInboxKey);
    await prefs.remove(_recipeAttemptKey);
    await prefs.remove(_recipeSentKey);
    if (ready) {
      await _plugin.cancel(id: recipeNoticeId);
      await _plugin.cancel(id: recipeNoticeId + 100);
    }
    notifyListeners();
  }

  Future<void> checkNow({bool forceRecipes = false}) async {
    if (!ready || !enabled || busy) return;
    busy = true;
    notifyListeners();
    try {
      await runPantryBackgroundCheck(
          forceRecipes: forceRecipes, initializedPlugin: _plugin);
      error = null;
    } catch (_) {
      error =
          'Falha ao verificar a despensa. Confira a permissão de notificações.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(checkNow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _debounce?.cancel();
    _timer?.cancel();
    navigation.dispose();
    super.dispose();
  }
}
