import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/categories.dart';

class AppSettingsService extends ChangeNotifier {
  AppSettingsService._();
  static final instance = AppSettingsService._();

  static const _defaultCategoryKey = 'settings_default_category_v1';
  static const _defaultUnitKey = 'settings_default_unit_v1';
  static const _defaultSortKey = 'settings_default_sort_v1';
  static const _expiryWarningDaysKey = 'settings_expiry_warning_days_v1';
  static const _expiryReminderHourKey = 'settings_expiry_reminder_hour_v1';
  static const _defaultLowStockKey = 'settings_default_low_stock_v1';
  static const _autoShoppingOnZeroKey = 'settings_auto_shopping_zero_v1';
  static const _prioritizeExpiringRecipesKey =
      'settings_prioritize_expiring_recipes_v1';
  static const _maxRecipesKey = 'settings_max_recipes_v1';
  static const _glassBlurLevelKey = 'settings_glass_blur_level_v1';
  static const _ambientOrbsKey = 'settings_ambient_orbs_v1';
  static const _compactCardsKey = 'settings_compact_cards_v1';

  String defaultCategory = AppConstants.defaultCategory;
  String defaultUnit = AppConstants.defaultUnit;
  String defaultSort = 'name'; // 'name', 'expiry', 'quantity'
  int expiryWarningDays = 7;
  int expiryReminderHour = 9;
  double defaultLowStockThreshold = 1.0;
  bool autoAddToShoppingListOnZero = true;
  bool prioritizeExpiringInRecipes = true;
  int maxRecipesResults = 20;
  double glassBlurSigma = 18.0; // 10.0 (Suave), 18.0 (Padrão), 28.0 (Intenso)
  bool ambientOrbsEnabled = true;
  bool compactCards = false;

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final cat = prefs.getString(_defaultCategoryKey);
    if (cat != null && AppConstants.categories.contains(cat)) {
      defaultCategory = cat;
    }
    final unit = prefs.getString(_defaultUnitKey);
    if (unit != null && AppConstants.units.contains(unit)) {
      defaultUnit = unit;
    }
    final sort = prefs.getString(_defaultSortKey);
    if (sort != null && {'name', 'expiry', 'quantity'}.contains(sort)) {
      defaultSort = sort;
    }
    expiryWarningDays =
        (prefs.getInt(_expiryWarningDaysKey) ?? 7).clamp(1, 60);
    expiryReminderHour =
        (prefs.getInt(_expiryReminderHourKey) ?? 9).clamp(0, 23);
    defaultLowStockThreshold =
        (prefs.getDouble(_defaultLowStockKey) ?? 1.0).clamp(0.0, 1000.0);
    autoAddToShoppingListOnZero =
        prefs.getBool(_autoShoppingOnZeroKey) ?? true;
    prioritizeExpiringInRecipes =
        prefs.getBool(_prioritizeExpiringRecipesKey) ?? true;
    maxRecipesResults =
        (prefs.getInt(_maxRecipesKey) ?? 20).clamp(5, 50);
    glassBlurSigma =
        (prefs.getDouble(_glassBlurLevelKey) ?? 18.0).clamp(6.0, 32.0);
    ambientOrbsEnabled = prefs.getBool(_ambientOrbsKey) ?? true;
    compactCards = prefs.getBool(_compactCardsKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setDefaultCategory(String value) async {
    if (!AppConstants.categories.contains(value)) return;
    defaultCategory = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultCategoryKey, value);
  }

  Future<void> setDefaultUnit(String value) async {
    if (!AppConstants.units.contains(value)) return;
    defaultUnit = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultUnitKey, value);
  }

  Future<void> setDefaultSort(String value) async {
    if (!{'name', 'expiry', 'quantity'}.contains(value)) return;
    defaultSort = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultSortKey, value);
  }

  Future<void> setExpiryWarningDays(int days) async {
    expiryWarningDays = days.clamp(1, 60);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_expiryWarningDaysKey, expiryWarningDays);
  }

  Future<void> setExpiryReminderHour(int hour) async {
    expiryReminderHour = hour.clamp(0, 23);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_expiryReminderHourKey, expiryReminderHour);
  }

  Future<void> setDefaultLowStockThreshold(double amount) async {
    if (!amount.isFinite || amount < 0) return;
    defaultLowStockThreshold = amount;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_defaultLowStockKey, amount);
  }

  Future<void> setAutoAddToShoppingListOnZero(bool value) async {
    autoAddToShoppingListOnZero = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoShoppingOnZeroKey, value);
  }

  Future<void> setPrioritizeExpiringInRecipes(bool value) async {
    prioritizeExpiringInRecipes = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prioritizeExpiringRecipesKey, value);
  }

  Future<void> setMaxRecipesResults(int count) async {
    maxRecipesResults = count.clamp(5, 50);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxRecipesKey, maxRecipesResults);
  }

  Future<void> setGlassBlurSigma(double sigma) async {
    glassBlurSigma = sigma.clamp(6.0, 32.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_glassBlurLevelKey, glassBlurSigma);
  }

  Future<void> setAmbientOrbsEnabled(bool value) async {
    ambientOrbsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ambientOrbsKey, value);
  }

  Future<void> setCompactCards(bool value) async {
    compactCards = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_compactCardsKey, value);
  }

  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_defaultCategoryKey);
    await prefs.remove(_defaultUnitKey);
    await prefs.remove(_defaultSortKey);
    await prefs.remove(_expiryWarningDaysKey);
    await prefs.remove(_expiryReminderHourKey);
    await prefs.remove(_defaultLowStockKey);
    await prefs.remove(_autoShoppingOnZeroKey);
    await prefs.remove(_prioritizeExpiringRecipesKey);
    await prefs.remove(_maxRecipesKey);
    await prefs.remove(_glassBlurLevelKey);
    await prefs.remove(_ambientOrbsKey);
    await prefs.remove(_compactCardsKey);
    defaultCategory = AppConstants.defaultCategory;
    defaultUnit = AppConstants.defaultUnit;
    defaultSort = 'name';
    expiryWarningDays = 7;
    expiryReminderHour = 9;
    defaultLowStockThreshold = 1.0;
    autoAddToShoppingListOnZero = true;
    prioritizeExpiringInRecipes = true;
    maxRecipesResults = 20;
    glassBlurSigma = 18.0;
    ambientOrbsEnabled = true;
    compactCards = false;
    notifyListeners();
  }
}
