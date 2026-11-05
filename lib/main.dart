import 'dart:async';
import 'package:flutter/material.dart';
import 'services/app_settings_service.dart';
import 'services/theme_service.dart';
import 'sync/lan_sync.dart';
import 'views/home_screen.dart';
import 'views/onboarding_screen.dart';
import 'services/expiry_notification_service.dart';
import 'services/pantry_background_service.dart';
import 'services/pantry_notification_plan.dart';
import 'views/shopping_list_screen.dart';
import 'views/recipe_inbox_screen.dart';

@pragma('vm:entry-point')
void callbackDispatcher() => pantryCallbackDispatcher();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeModeFuture = ThemeService.loadThemeMode();
  final onboardingDoneFuture = ThemeService.isOnboardingCompleted();
  await AppSettingsService.instance.load();
  final themeMode = await themeModeFuture;
  final onboardingDone = await onboardingDoneFuture;
  runApp(App(initialThemeMode: themeMode, initialShowOnboarding: !onboardingDone));
  unawaited(LanSync.instance.initialize());
}

class App extends StatefulWidget {
  final ThemeMode initialThemeMode;
  final bool initialShowOnboarding;
  const App({super.key, this.initialThemeMode = ThemeMode.system, this.initialShowOnboarding = false});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _navigator = GlobalKey<NavigatorState>();
  late bool _showOnboarding = widget.initialShowOnboarding;

  @override
  void initState() {
    super.initState();
    PantryBackgroundService.instance.navigation.addListener(_openNotification);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_startNotifications()));
  }

  Future<void> _startNotifications() async {
    ExpiryNotificationService.instance.onOpenRecipes = () {
      PantryBackgroundService.instance.navigation.value = 'expiry_recipes';
    };
    await ExpiryNotificationService.instance.initialize();
    await PantryBackgroundService.instance.initialize();
  }

  void _openNotification() {
    final payload = PantryBackgroundService.instance.navigation.value;
    final navigator = _navigator.currentState;
    if (navigator == null || payload == null) return;
    if (payload == 'expiry_recipes') {
      navigator.popUntil((route) => route.isFirst);
    } else {
      navigator.push(MaterialPageRoute(
          builder: (_) => payload == stockNoticePayload
              ? const ShoppingListScreen()
              : const RecipeInboxScreen()));
    }
  }

  @override
  void dispose() {
    PantryBackgroundService.instance.navigation
        .removeListener(_openNotification);
    super.dispose();
  }

  final _lightTheme = ThemeService.theme(Brightness.light);
  final _darkTheme = ThemeService.theme(Brightness.dark);
  late ThemeMode _themeMode = widget.initialThemeMode;

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await ThemeService.setThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'Despensa Smart',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _showOnboarding
            ? OnboardingScreen(
                key: const ValueKey('onboarding'),
                onFinish: () => setState(() => _showOnboarding = false),
              )
            : HomeScreen(
                key: const ValueKey('home'),
                themeMode: _themeMode,
                onThemeModeChanged: _setThemeMode,
              ),
      ),
    );
  }
}
