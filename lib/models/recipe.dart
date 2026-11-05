import '../services/ingredient_names.dart';

class Recipe {
  final String id;
  final String name;
  final String thumbnail;
  final String instructions;
  final String sourceUrl;
  final List<String> ingredients;
  final int matchingIngredients;

  const Recipe({
    required this.id,
    required this.name,
    required this.thumbnail,
    required this.instructions,
    required this.sourceUrl,
    required this.ingredients,
    this.matchingIngredients = 0,
  });

  factory Recipe.fromApi(Map<String, dynamic> json,
      {Set<String> pantry = const {}}) {
    final ingredients = <String>[];
    for (var i = 1; i <= 20; i++) {
      final value = (json['strIngredient$i'] as String? ?? '').trim();
      final measure = (json['strMeasure$i'] as String? ?? '').trim();
      if (value.isNotEmpty) {
        ingredients.add(measure.isEmpty ? value : '$value — $measure');
      }
    }
    final normalizedPantry = pantry.map(_normalize).toSet();
    var matches = 0;
    for (final item in ingredients) {
      final ingredient = _normalize(item.split('—').first);
      if (normalizedPantry.any((p) => IngredientNames.matches(p, ingredient))) {
        matches++;
      }
    }
    return Recipe(
      id: (json['idMeal'] as String? ?? '').toString(),
      name: (json['strMeal'] as String? ?? 'Receita sem título').toString(),
      thumbnail: (json['strMealThumb'] as String? ?? '').toString(),
      instructions: (json['strInstructions'] as String? ?? '').toString(),
      sourceUrl:
          (json['strSource'] as String? ?? json['strYoutube'] as String? ?? '')
              .toString(),
      ingredients: ingredients,
      matchingIngredients: matches,
    );
  }

  static String _normalize(String value) => IngredientNames.canonical(value);
}
