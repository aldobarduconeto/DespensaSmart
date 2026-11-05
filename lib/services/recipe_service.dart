import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/recipe.dart';
import 'ingredient_names.dart';

class RecipeService {
  static const _base = 'https://www.themealdb.com/api/json/v1/1';
  static const _timeout = Duration(seconds: 12);
  static const _cacheDuration = Duration(hours: 1);
  static const _maxIngredientsQueried = 8;
  static const _maxCacheEntries = 20;
  static const _maxRecipes = 20;
  static const _detailBatchSize = 5;

  final http.Client _client;
  final Map<String, _CacheEntry> _cache = {};
  final Map<String, Future<List<Recipe>>> _inFlight = {};
  bool _disposed = false;

  RecipeService({http.Client? client}) : _client = client ?? http.Client();

  void dispose() {
    _disposed = true;
    _client.close();
    _cache.clear();
  }

  void clearCache() => _cache.clear();

  Future<List<Recipe>> recommend(List<String> pantryIngredients,
      {List<String> priorityIngredients = const []}) async {
    final priority = priorityIngredients.map(IngredientNames.canonical).toSet();
    final available = pantryIngredients
        .map(IngredientNames.canonical)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    final ingredients = [
      ...available.where(priority.contains),
      ...available.where((ingredient) => !priority.contains(ingredient)),
    ];
    if (ingredients.isEmpty) return [];

    final cacheKey = jsonEncode([
      ingredients.take(_maxIngredientsQueried).toList(),
      priority.toList()..sort(),
      (ingredients.toList()..sort())
    ]);
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.savedAt) < _cacheDuration) {
      return cached.recipes;
    }

    if (_disposed) throw StateError('Serviço encerrado');
    final existing = _inFlight[cacheKey];
    if (existing != null) return existing;
    final request = _recommend(ingredients, cacheKey, priority);
    _inFlight[cacheKey] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<List<Recipe>> _recommend(
      List<String> ingredients, String cacheKey, Set<String> priority) async {
    // 1) Uma busca por ingrediente, em paralelo. null = a requisição falhou.
    final idLists = await Future.wait(
      ingredients.take(_maxIngredientsQueried).map(_idsForIngredient),
    );
    if (idLists.every((ids) => ids == null)) {
      throw Exception('Serviço de receitas indisponível');
    }

    // 2) Ranqueia as receitas pelo número de ingredientes da despensa que usam e
    //    detalha só as melhores, evitando dezenas de requisições desnecessárias.
    final hits = <String, int>{};
    final priorityHits = <String, int>{};
    for (var i = 0; i < idLists.length; i++) {
      final ids = idLists[i];
      if (ids == null) continue;
      for (final id in ids) {
        hits[id] = (hits[id] ?? 0) + 1;
        if (priority.contains(ingredients[i])) {
          priorityHits[id] = (priorityHits[id] ?? 0) + 1;
        }
      }
    }
    final ranked = hits.entries.toList()
      ..sort((a, b) {
        final urgent =
            (priorityHits[b.key] ?? 0).compareTo(priorityHits[a.key] ?? 0);
        if (urgent != 0) return urgent;
        final byHits = b.value.compareTo(a.value);
        return byHits != 0 ? byHits : a.key.compareTo(b.key);
      });
    final topIds = ranked.take(_maxRecipes).map((e) => e.key).toList();

    // 3) Detalhes em lotes paralelos para não sobrecarregar a API.
    final pantry = ingredients.toSet();
    final detailed = <Recipe>[];
    for (var i = 0; i < topIds.length; i += _detailBatchSize) {
      if (_disposed) throw StateError('Serviço encerrado');
      final batch = topIds.skip(i).take(_detailBatchSize);
      final results = await Future.wait(batch.map((id) => _lookup(id, pantry)));
      detailed.addAll(results.whereType<Recipe>());
    }

    if (topIds.isNotEmpty && detailed.isEmpty) {
      throw Exception('Não foi possível carregar os detalhes das receitas');
    }
    detailed.removeWhere((recipe) => recipe.matchingIngredients == 0);
    int urgentMatches(Recipe recipe) => recipe.ingredients
        .where((ingredient) => priority.any((p) => IngredientNames.matches(
            p, IngredientNames.canonical(ingredient.split('—').first))))
        .length;
    if (priority.isNotEmpty) {
      detailed.removeWhere((recipe) => urgentMatches(recipe) == 0);
    }
    detailed.sort((a, b) {
      final urgent = urgentMatches(b).compareTo(urgentMatches(a));
      if (urgent != 0) return urgent;
      final coverage = (b.matchingIngredients / b.ingredients.length)
          .compareTo(a.matchingIngredients / a.ingredients.length);
      if (coverage != 0) return coverage;
      final compare = b.matchingIngredients.compareTo(a.matchingIngredients);
      return compare != 0 ? compare : a.name.compareTo(b.name);
    });

    // Só guarda em cache resultados reais (nunca uma falha de rede).
    if (detailed.isNotEmpty && !_disposed) {
      _cache.removeWhere((_, entry) =>
          DateTime.now().difference(entry.savedAt) >= _cacheDuration);
      if (_cache.length >= _maxCacheEntries) _cache.remove(_cache.keys.first);
      _cache[cacheKey] =
          _CacheEntry(List.unmodifiable(detailed), DateTime.now());
    }
    return List.unmodifiable(detailed);
  }

  Future<Map<String, dynamic>> _getJson(
      String endpoint, Map<String, String> params) async {
    final uri = Uri.parse('$_base/$endpoint').replace(queryParameters: params);
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200)
      throw Exception('HTTP ${response.statusCode}');
    if (response.body.trim().isEmpty) return {'meals': null};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<String>?> _idsForIngredient(String ingredient) async {
    try {
      final json = await _getJson('filter.php', {'i': ingredient});
      final meals = json['meals'];
      if (meals is! List)
        return const <String>[]; // "meals": null: sem resultados
      return meals
          .whereType<Map<String, dynamic>>()
          .map((m) => (m['idMeal'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<Recipe?> _lookup(String id, Set<String> pantry) async {
    try {
      final json = await _getJson('lookup.php', {'i': id});
      final meals = json['meals'];
      if (meals is List &&
          meals.isNotEmpty &&
          meals.first is Map<String, dynamic>) {
        return Recipe.fromApi(meals.first as Map<String, dynamic>,
            pantry: pantry);
      }
    } catch (_) {
      // Uma receita que falha ao carregar não derruba a lista inteira.
    }
    return null;
  }
}

class _CacheEntry {
  final List<Recipe> recipes;
  final DateTime savedAt;
  const _CacheEntry(this.recipes, this.savedAt);
}
