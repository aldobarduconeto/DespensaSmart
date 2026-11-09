import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/pantry_database.dart';
import '../models/pantry_item.dart';
import '../models/recipe.dart';
import '../services/app_settings_service.dart';
import '../services/ingredient_names.dart';
import '../services/local_recipe_ai_service.dart';
import '../services/pantry_background_service.dart';
import '../services/pantry_notification_plan.dart';
import 'widgets/liquid_glass.dart';
import 'local_ai_settings_screen.dart';
import 'widgets/recipe_card.dart';

enum _LocalAiOperation { recipes, mealPlan }

class RecipeInboxScreen extends StatefulWidget {
  const RecipeInboxScreen({super.key});
  @override
  State<RecipeInboxScreen> createState() => _RecipeInboxScreenState();
}

class _RecipeInboxScreenState extends State<RecipeInboxScreen> {
  List<Recipe> _recipes = [];
  String? _date;
  String? _error;
  bool _loading = true;
  bool _stale = false;
  _LocalAiOperation? _activeAiOperation;
  String? _localAiError;
  String? _inventorySignature;
  List<PantryItem> _availableItems = [];
  List<Recipe> _localRecipes = [];
  List<LocalMealPlanEntry> _mealPlan = [];
  List<String> _priority = [];

  bool get _generatingLocalRecipes =>
      _activeAiOperation == _LocalAiOperation.recipes;
  bool get _generatingMealPlan =>
      _activeAiOperation == _LocalAiOperation.mealPlan;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (mounted) setState(() => _loading = true);
    try {
      if (refresh) {
        await PantryBackgroundService.instance.checkNow(forceRecipes: true);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString(pantryRecipeInboxKey);
      final items = await PantryDatabase.instance.allItems();
      final plan = PantryNotificationPlan(
        items,
        readThresholds(prefs),
        DateTime.now(),
        defaultThreshold: AppSettingsService.instance.defaultLowStockThreshold,
        warningDays: AppSettingsService.instance.expiryWarningDays,
      );
      final data = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
      final recipes = data == null
          ? <Recipe>[]
          : (data['recipes'] as List)
                .map((e) => recipeFromJson(Map<String, dynamic>.from(e as Map)))
                .toList();
      if (_inventorySignature != plan.inventorySignature) {
        _localRecipes = [];
        _mealPlan = [];
        _inventorySignature = plan.inventorySignature;
      }
      // Recalcula cobertura ao abrir: uma lista antiga nunca conta estoque vencido ou esgotado.
      final available = plan.available
          .map((e) => IngredientNames.canonical(e.name))
          .toSet();
      final usable = <Recipe>[];
      for (final recipe in recipes) {
        final matches = recipe.ingredients
            .where(
              (e) => available.any(
                (p) => IngredientNames.matches(
                  p,
                  IngredientNames.canonical(e.split('—').first),
                ),
              ),
            )
            .length;
        if (matches == 0) continue;
        usable.add(
          Recipe(
            id: recipe.id,
            name: recipe.name,
            thumbnail: recipe.thumbnail,
            instructions: recipe.instructions,
            sourceUrl: recipe.sourceUrl,
            ingredients: recipe.ingredients,
            matchingIngredients: matches,
          ),
        );
      }
      if (mounted) {
        setState(() {
          _recipes = usable;
          _availableItems = plan.available;
          _date = data?['date'] as String?;
          _priority = data == null
              ? []
              : List<String>.from(data['priority'] as List);
          _stale = data != null && data['inventory'] != plan.inventorySignature;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível carregar as receitas.';
        });
      }
    }
  }

  Future<void> _generateLocalRecipes() => _runLocalAi(
    operation: _LocalAiOperation.recipes,
    generate: () => LocalRecipeAiService.instance.generateRecipes(
      _availableItems,
      priorityIngredients: _priority,
    ),
    onSuccess: (recipes) => _localRecipes = recipes,
  );

  Future<void> _generateMealPlan() => _runLocalAi(
    operation: _LocalAiOperation.mealPlan,
    generate: () => LocalRecipeAiService.instance.generateMealPlan(
      _availableItems,
      priorityIngredients: _priority,
    ),
    onSuccess: (plan) => _mealPlan = plan,
  );

  Future<void> _runLocalAi<T>({
    required _LocalAiOperation operation,
    required Future<T> Function() generate,
    required void Function(T) onSuccess,
  }) async {
    if (_activeAiOperation != null || _availableItems.isEmpty) return;
    final inventorySignature = _inventorySignature;
    setState(() {
      _activeAiOperation = operation;
      _localAiError = null;
    });
    try {
      final result = await generate();
      if (mounted && inventorySignature == _inventorySignature) {
        setState(() => onSuccess(result));
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _localAiError = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _activeAiOperation = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const LiquidGlassAppBar(title: Text('Receitas sugeridas')),
    body: LiquidGlassBackground(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                LiquidGlassCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sugestões consultadas no TheMealDB. Confira ingredientes, quantidades e validade antes de preparar.',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed:
                            _availableItems.isEmpty ||
                                _generatingLocalRecipes ||
                                _generatingMealPlan
                            ? null
                            : _generateLocalRecipes,
                        icon: _generatingLocalRecipes
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_rounded),
                        label: Text(
                          _generatingLocalRecipes
                              ? 'Gerando receitas no aparelho...'
                              : 'Gerar receitas com IA local',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _availableItems.isEmpty ||
                                _generatingLocalRecipes ||
                                _generatingMealPlan
                            ? null
                            : _generateMealPlan,
                        icon: _generatingMealPlan
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.event_note_rounded),
                        label: Text(
                          _generatingMealPlan
                              ? 'Montando plano no aparelho...'
                              : 'Planejar 3 dias com IA local',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LocalAiSettingsScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: const Text('Configurar IA local'),
                      ),
                      if (_localAiError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _localAiError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      if (_availableItems.isEmpty)
                        Text(
                          'Adicione itens disponíveis à despensa para gerar receitas.',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        Text(
                          'A IA usa apenas os itens disponíveis neste aparelho. Receitas e plano de refeições são gerados localmente, sem enviar sua despensa para servidores de IA.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (_date != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Consulta: ${DateTime.parse(_date!).toLocal().toString().substring(0, 16)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (_priority.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Priorizados na consulta: ${_priority.join(', ')}.',
                        ),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _load(refresh: true),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Atualizar sugestões'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_stale)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LiquidGlassCard(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Sua despensa mudou desde esta consulta. Atualize as sugestões; os ingredientes disponíveis foram recalculados.',
                      ),
                    ),
                  ),
                if (_localRecipes.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LiquidGlassCard(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Receitas criadas pelo Gemma 4 E2B no seu aparelho. Confira ingredientes, quantidades e preparo.',
                      ),
                    ),
                  ),
                  for (final recipe in _localRecipes)
                    RecipeCard(recipe: recipe),
                ],
                if (_mealPlan.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LiquidGlassCard(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Plano de 3 dias gerado pelo Gemma no aparelho. Confira ingredientes, quantidades e preparo antes de cozinhar.',
                      ),
                    ),
                  ),
                  for (final entry in _mealPlan) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        entry.day,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    RecipeCard(recipe: entry.recipe),
                  ],
                ],
                if (_error != null) Text(_error!),
                if (!PantryBackgroundService.instance.enabled)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Ative estoque e receitas nas configurações para receber e atualizar sugestões.',
                    ),
                  ),
                if (_recipes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Nenhuma sugestão disponível. Confira seu estoque e a conexão com a internet e tente novamente.',
                    ),
                  ),
                for (final recipe in _recipes) RecipeCard(recipe: recipe),
              ],
            ),
    ),
  );
}
