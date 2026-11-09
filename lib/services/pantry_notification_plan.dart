import 'dart:convert';
import '../models/pantry_item.dart';
import '../models/recipe.dart';

const backgroundTaskId = 'com.awesome.despensa_smart.pantry_check';
const stockNoticeId = 81001;
const recipeNoticeId = 81002;
const stockNoticePayload = 'pantry_stock';
const recipeNoticePayload = 'pantry_recipe_digest';

class PantryNotificationPlan {
  final List<PantryItem> missing;
  final List<PantryItem> low;
  final List<PantryItem> available;
  final List<PantryItem> priority;
  PantryNotificationPlan(
    List<PantryItem> items,
    Map<String, double> thresholds,
    DateTime now, {
    double defaultThreshold = 1.0,
    int warningDays = 7,
  })  : missing = items.where((e) => e.quantity == 0).toList(),
        low = items
            .where((e) =>
                e.quantity > 0 &&
                e.quantity <= (thresholds['${e.id}'] ?? defaultThreshold))
            .toList(),
        available =
            items.where((e) => e.quantity > 0 && !_expired(e, now)).toList(),
        priority = items
            .where((e) =>
                e.quantity > 0 &&
                !_expired(e, now) &&
                (_soon(e, now, warningDays) ||
                    e.quantity <= (thresholds['${e.id}'] ?? defaultThreshold)))
            .toList();

  static bool _expired(PantryItem e, DateTime now) =>
      e.expiryDate != null &&
      e.expiryDate!.isBefore(DateTime(now.year, now.month, now.day));

  static bool _soon(PantryItem e, DateTime now, int warningDays) {
    if (e.expiryDate == null) return false;
    final date = e.expiryDate!;
    return !DateTime(date.year, date.month, date.day)
        .isAfter(DateTime(now.year, now.month, now.day + warningDays));
  }

  bool get hasStockAlert => missing.isNotEmpty || low.isNotEmpty;
  String get stockSignature => jsonEncode([
        (missing.map((e) => '${e.id}:${e.name}').toList()..sort()),
        (low.map((e) => '${e.id}:${e.name}:${e.unit}').toList()..sort()),
      ]);
  String get stockBody => [
        if (missing.isNotEmpty)
          'Faltando: ${missing.take(5).map((e) => e.name).join(', ')}${missing.length > 5 ? ' e mais ${missing.length - 5}' : ''}.',
        if (low.isNotEmpty)
          'Acabando: ${low.take(5).map((e) => '${e.name} (${e.quantity} ${e.unit})').join(', ')}${low.length > 5 ? ' e mais ${low.length - 5}' : ''}.',
        'Toque para conferir o carrinho.',
      ].join(' ');
  String get inventorySignature => jsonEncode((available
      .map((e) =>
          '${e.id}:${e.name}:${e.quantity}:${e.unit}:${e.expiryDate?.toIso8601String()}')
      .toList()
    ..sort()));
}

Map<String, dynamic> recipeToJson(Recipe recipe) => {
      'id': recipe.id,
      'name': recipe.name,
      'thumbnail': recipe.thumbnail,
      'instructions': recipe.instructions,
      'sourceUrl': recipe.sourceUrl,
      'ingredients': recipe.ingredients,
      'matchingIngredients': recipe.matchingIngredients,
    };
Recipe recipeFromJson(Map<String, dynamic> json) => Recipe(
      id: json['id'] as String,
      name: json['name'] as String,
      thumbnail: json['thumbnail'] as String,
      instructions: json['instructions'] as String,
      sourceUrl: json['sourceUrl'] as String,
      ingredients: List<String>.from(json['ingredients'] as List),
      matchingIngredients: json['matchingIngredients'] as int,
    );
