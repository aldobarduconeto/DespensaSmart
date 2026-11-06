import 'dart:async';

import 'package:flutter/material.dart';
import '../data/pantry_database.dart';
import '../services/app_settings_service.dart';
import '../services/local_recipe_ai_service.dart';
import '../services/recipe_service.dart';
import '../models/pantry_item.dart';
import '../models/recipe.dart';
import 'add_item_screen.dart';
import 'edit_item_screen.dart';
import 'settings_screen.dart';
import 'shopping_list_screen.dart';
import 'local_ai_settings_screen.dart';
import 'family_consumption_screen.dart';
import 'pantry_advice_screen.dart';
import 'widgets/liquid_glass.dart';
import 'widgets/recipe_card.dart';
import 'widgets/empty_state.dart';
import 'widgets/expiry_warning_banner.dart';
import 'widgets/expiry_agenda.dart';
import 'widgets/pantry_item_card.dart';
import 'widgets/stock_dialog.dart';
import 'widgets/pantry_overview.dart';
import '../services/ingredient_names.dart';
import '../services/pantry_background_service.dart';
import '../services/family_mode_service.dart';
import '../sync/lan_sync.dart';

enum PantryStatusFilter {
  all,
  stocked,
  attention,
  withoutExpiry,
  outOfStock,
  shopping,
}

enum PantrySortOption { name, expiry, quantity }

class HomeScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  const HomeScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _db = PantryDatabase.instance;
  final _settings = AppSettingsService.instance;
  StreamSubscription<void>? _dataChanges;
  Timer? _expiryTimer;
  final _recipes = RecipeService();
  final _searchController = TextEditingController();
  List<PantryItem> _items = [];
  List<PantryItem> _filteredItems = [];
  List<Recipe> _recommendations = [];
  List<PantryItem> _expiringSoon = [];
  bool _loadingItems = true;
  bool _loadingRecipes = false;
  String? _recipeError;
  String? _loadError;
  int _loadRequest = 0;
  String _ingredientKey = "";
  int _recipeRequest = 0;
  int _tab = 0;
  String? _selectedCategory;
  PantryStatusFilter _statusFilter = PantryStatusFilter.all;
  late PantrySortOption _sortOption = _sortFromKey(_settings.defaultSort);
  List<String> _categories = [];

  static const _statusLabels = {
    PantryStatusFilter.all: 'Todas as situações',
    PantryStatusFilter.stocked: 'Em estoque',
    PantryStatusFilter.attention: 'Para conferir',
    PantryStatusFilter.withoutExpiry: 'Sem validade',
    PantryStatusFilter.outOfStock: 'Esgotados',
    PantryStatusFilter.shopping: 'Nas compras',
  };

  static PantrySortOption _sortFromKey(String key) => switch (key) {
    'expiry' => PantrySortOption.expiry,
    'quantity' => PantrySortOption.quantity,
    _ => PantrySortOption.name,
  };

  @override
  void initState() {
    super.initState();
    PantryBackgroundService.instance.navigation.addListener(
      _notificationOpened,
    );
    _settings.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addObserver(this);
    _dataChanges = _db.changes.listen((_) {
      if (mounted) _loadItems();
    });
    _loadItems();
    _scheduleExpiryRefresh();
  }

  void _scheduleExpiryRefresh() {
    _expiryTimer?.cancel();
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _expiryTimer = Timer(nextDay.difference(now), () {
      if (!mounted) return;
      _loadItems();
      _scheduleExpiryRefresh();
    });
  }

  @override
  void dispose() {
    PantryBackgroundService.instance.navigation.removeListener(
      _notificationOpened,
    );
    _settings.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    _dataChanges?.cancel();
    _expiryTimer?.cancel();
    _searchController.dispose();
    _recipes.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {
      _sortOption = _sortFromKey(_settings.defaultSort);
    });
    _loadItems();
  }

  void _notificationOpened() {
    if (PantryBackgroundService.instance.navigation.value == 'expiry_recipes') {
      _selectTab(1);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadItems();
  }

  Future<void> _loadItems() async {
    final request = ++_loadRequest;
    late final List<PantryItem> items;
    try {
      items = await _db.allItems();
    } catch (_) {
      if (mounted && request == _loadRequest) {
        setState(() {
          _loadingItems = false;
          _loadError = 'Não foi possível carregar a despensa. Tente novamente.';
        });
      }
      return;
    }
    if (!mounted || request != _loadRequest) return;
    final ingredientKey =
        (items
                .where((e) => e.quantity > 0 && !e.isExpired())
                .map(
                  (e) =>
                      '${e.name}:${e.isExpiringSoon()}:${_settings.prioritizeExpiringInRecipes}:${_settings.maxRecipesResults}',
                )
                .toList()
              ..sort())
            .join('|');
    final changed = ingredientKey != _ingredientKey;

    final categories = items.map((e) => e.category).toSet().toList()..sort();
    if (_selectedCategory != null && !categories.contains(_selectedCategory)) {
      _selectedCategory = null;
    }
    final expiring =
        items
            .where(
              (e) => e.quantity > 0 && (e.isExpiringSoon() || e.isExpired()),
            )
            .toList()
          ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));

    setState(() {
      _loadError = null;
      if (changed) {
        _ingredientKey = ingredientKey;
        _recipeRequest++;
        _loadingRecipes = false;
        _recommendations = [];
        _recipeError = null;
      }
      _items = items;
      _categories = categories;
      _expiringSoon = expiring.take(20).toList();
      _filteredItems = _applyFilters(
        _searchController.text,
        _selectedCategory,
        _statusFilter,
        _sortOption,
      );
      _loadingItems = false;
    });
    if (changed && _tab == 1) await _getRecipes();
  }

  void _filterItems(String query) {
    setState(() {
      _filteredItems = _applyFilters(
        query,
        _selectedCategory,
        _statusFilter,
        _sortOption,
      );
    });
  }

  List<PantryItem> _applyFilters(
    String query,
    String? category,
    PantryStatusFilter status,
    PantrySortOption sort,
  ) {
    final q = IngredientNames.normalize(query);
    final result = _items.where((item) {
      final matchesCategory = category == null || item.category == category;
      final matchesSearch =
          q.isEmpty || IngredientNames.normalize(item.name).contains(q);
      final matchesStatus = switch (status) {
        PantryStatusFilter.all => true,
        PantryStatusFilter.stocked => item.quantity > 0,
        PantryStatusFilter.withoutExpiry =>
          item.quantity > 0 && item.expiryDate == null,
        PantryStatusFilter.attention =>
          item.quantity > 0 && (item.isExpired() || item.isExpiringSoon()),
        PantryStatusFilter.outOfStock => item.quantity == 0,
        PantryStatusFilter.shopping => item.inShoppingList,
      };
      return matchesCategory && matchesSearch && matchesStatus;
    }).toList();

    result.sort((a, b) {
      return switch (sort) {
        PantrySortOption.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        PantrySortOption.expiry => (a.expiryDate ?? DateTime(9999)).compareTo(
          b.expiryDate ?? DateTime(9999),
        ),
        PantrySortOption.quantity => a.quantity.compareTo(b.quantity),
      };
    });
    return result;
  }

  void _clearSearch() {
    _searchController.clear();
    _filterItems('');
  }

  void _filterByCategory(String? category) {
    _selectedCategory = category;
    _filterItems(_searchController.text);
  }

  void _setStatusFilter(PantryStatusFilter status) {
    _statusFilter = status;
    _filterItems(_searchController.text);
  }

  void _setSortOption(PantrySortOption sort) {
    _sortOption = sort;
    _filterItems(_searchController.text);
  }

  Future<void> _addItem() async {
    final result = await Navigator.of(context).push<PantryItem>(
      MaterialPageRoute(builder: (_) => const AddItemScreen()),
    );
    if (result == null) return;
    try {
      await _db.add(result);
      await _loadItems();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item adicionado à despensa.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Esse item já existe. Edite ou remova o item existente.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _editItem(PantryItem item) async {
    final result = await Navigator.of(context).push<PantryItem>(
      MaterialPageRoute(builder: (_) => EditItemScreen(item: item)),
    );
    if (result == null) return;
    try {
      await _db.update(result);
      await _loadItems();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível salvar. Verifique se já existe um item com esse nome.',
            ),
          ),
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Item atualizado.')));
    }
  }

  Future<void> _toggleShoppingList(PantryItem item) async {
    if (item.id == null) return;
    try {
      await _db.toggleShoppingList(item.id!);
      await _loadItems();
    } catch (_) {
      _showError('Não foi possível atualizar a lista de compras.');
      return;
    }
    final inList = !item.inShoppingList;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            inList
                ? 'Adicionado à lista de compras'
                : 'Removido da lista de compras',
          ),
        ),
      );
    }
  }

  Future<void> _getRecipes() async {
    final available =
        _items.where((e) => e.quantity > 0 && !e.isExpired()).toList()..sort(
          (a, b) => (a.expiryDate ?? DateTime(9999)).compareTo(
            b.expiryDate ?? DateTime(9999),
          ),
        );
    if (available.isEmpty) {
      setState(() {
        _recipeError =
            'Adicione ingredientes em estoque e dentro da validade para receber receitas.';
        _recommendations = [];
      });
      return;
    }
    final request = ++_recipeRequest;
    setState(() {
      _recommendations = [];
      _loadingRecipes = true;
      _recipeError = null;
    });
    try {
      final priorityList = _settings.prioritizeExpiringInRecipes
          ? available
                .where((e) => e.isExpiringSoon())
                .map((e) => e.name)
                .toList()
          : const <String>[];
      final result = await _recipes.recommend(
        available.map((e) => e.name).toList(),
        priorityIngredients: priorityList,
      );
      if (!mounted || request != _recipeRequest) return;
      final limited = result.take(_settings.maxRecipesResults).toList();
      setState(() {
        _recommendations = limited;
        if (limited.isEmpty) {
          _recipeError =
              'Nenhuma receita encontrada para estes ingredientes. Tente novamente mais tarde.';
        }
      });
    } catch (e) {
      if (!mounted || request != _recipeRequest) return;
      setState(
        () => _recipeError =
            'Não foi possível consultar receitas. Verifique a internet e tente novamente.',
      );
    } finally {
      if (mounted && request == _recipeRequest) {
        setState(() => _loadingRecipes = false);
      }
    }
  }

  void _selectTab(int value) {
    setState(() => _tab = value);
    if (value == 1 && !_loadingRecipes && _recommendations.isEmpty) {
      _getRecipes();
    }
  }

  Future<void> _consume(PantryItem item) async {
    await LanSync.instance.initialize();
    await FamilyModeService.instance.load();
    final familyMode = FamilyModeService.instance;
    String? person;
    double? amount;
    if (familyMode.available) {
      final selection = await showConsumptionDialog(
        context,
        item,
        familyMembers: familyMode.members,
      );
      amount = selection?.amount;
      person = selection?.person;
    } else {
      amount = await showStockDialog(context, item, buying: false);
    }
    if (amount == null || item.id == null) return;
    try {
      await _db.consume(item.id!, amount, person: person);
      await _loadItems();
      if (mounted) {
        final zeroed = item.quantityAfterConsuming(amount) == 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              zeroed && _settings.autoAddToShoppingListOnZero
                  ? 'Item esgotado e adicionado à lista de compras.'
                  : 'Consumo registrado.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível registrar o consumo. Atualize o estoque e tente novamente.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _restock(PantryItem item) async {
    final amount = await showStockDialog(context, item, buying: true);
    if (amount == null || item.id == null) return;
    try {
      await _db.restock(item.id!, amount, item.expiryDate);
      await _loadItems();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estoque reposto com sucesso.')),
        );
      }
    } catch (_) {
      _showError('Não foi possível repor o estoque.');
    }
  }

  Future<void> _deleteItem(PantryItem item) async {
    if (item.id == null) return;
    try {
      await _db.delete(item.id!);
      await _loadItems();
    } catch (_) {
      _showError('Não foi possível excluir o item.');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _openShoppingList() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ShoppingListScreen()));
    await _loadItems();
  }

  Future<void> _openExpiryAgenda() async {
    final item = await showExpiryAgenda(context, _items);
    if (!mounted || item == null) return;
    final index = _items.indexWhere((current) => current.id == item.id);
    if (index >= 0) await _editItem(_items[index]);
  }

  PopupMenuItem<VoidCallback> _aiMenuItem(
    String title,
    IconData icon,
    VoidCallback action,
  ) => PopupMenuItem(
    value: action,
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      contentPadding: EdgeInsets.zero,
    ),
  );

  void _openAiScreen(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final shoppingCount = _items.where((e) => e.inShoppingList).length;
    final wide = MediaQuery.sizeOf(context).width >= 850;

    return Scaffold(
      extendBody: true,
      appBar: LiquidGlassAppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.asset('assets/app_icon.png', width: 34, height: 34),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                'Despensa Smart',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<VoidCallback>(
            tooltip: 'Recursos de IA local',
            icon: const Icon(Icons.auto_awesome_outlined),
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              _aiMenuItem(
                'Receitas com IA local',
                Icons.restaurant_menu_rounded,
                () => _selectTab(1),
              ),
              _aiMenuItem(
                'Configurar IA e família',
                Icons.tune_rounded,
                () => _openAiScreen(const LocalAiSettingsScreen()),
              ),
              for (final kind in PantryAdviceKind.values)
                _aiMenuItem(
                  kind.presentation.title,
                  kind.presentation.icon,
                  () => _openAiScreen(
                    PantryAdviceScreen(items: List.of(_items), kind: kind),
                  ),
                ),
              _aiMenuItem(
                'Consumo e análise local',
                Icons.insights_rounded,
                () => _openAiScreen(const FamilyConsumptionScreen()),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Lista de compras',
            onPressed: _openShoppingList,
            icon: Badge(
              isLabelVisible: shoppingCount > 0,
              label: Text('$shoppingCount'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Configurações',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    themeMode: widget.themeMode,
                    onThemeModeChanged: widget.onThemeModeChanged,
                  ),
                ),
              );
              await _loadItems();
            },
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LiquidGlassBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 850;
            final content = _loadingItems
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                ? EmptyState(
                    icon: Icons.error_outline,
                    title: 'Falha ao carregar',
                    message: _loadError!,
                    actionLabel: 'Tentar novamente',
                    onAction: _loadItems,
                  )
                : IndexedStack(
                    index: _tab,
                    children: [_pantryView(), _recipeView()],
                  );
            if (!isWide) return content;
            return Row(
              children: [
                NavigationRail(
                  backgroundColor: Colors.transparent,
                  extended: constraints.maxWidth >= 1100,
                  selectedIndex: _tab,
                  onDestinationSelected: _selectTab,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Icon(
                      Icons.kitchen,
                      color: Theme.of(context).colorScheme.primary,
                      size: 30,
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2),
                      label: Text('Despensa'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.restaurant_menu),
                      selectedIcon: Icon(Icons.restaurant),
                      label: Text('Receitas'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: content,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: _addItem,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar item'),
            )
          : null,
      bottomNavigationBar: !wide
          ? LiquidGlassBottomNav(
              selectedIndex: _tab,
              onDestinationSelected: _selectTab,
              destinations: [
                (
                  icon: Icons.inventory_2_outlined,
                  selectedIcon: Icons.inventory_2_rounded,
                  label: 'Despensa',
                  badge: null,
                ),
                (
                  icon: Icons.restaurant_menu,
                  selectedIcon: Icons.restaurant,
                  label: 'Receitas',
                  badge: _expiringSoon.isNotEmpty ? _expiringSoon.length : null,
                ),
              ],
            )
          : null,
    );
  }

  Widget _pantryView() {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _loadItems,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: PantryOverview(
                items: _items,
                onTapStocked: () => _setStatusFilter(
                  _statusFilter == PantryStatusFilter.stocked
                      ? PantryStatusFilter.all
                      : PantryStatusFilter.stocked,
                ),
                onTapAgenda: _openExpiryAgenda,
                onTapShopping: _openShoppingList,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ExpiryWarningBanner(
              expiringItems: _expiringSoon,
              onRecipes: () => _selectTab(1),
            ),
          ),
          if (_items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.kitchen_outlined,
                title: 'Comece pela sua despensa',
                message:
                    'Adicione seus ingredientes. Quando acabarem, eles entram na lista de compras.',
                actionLabel: 'Cadastrar primeiro item',
                onAction: _addItem,
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ingredientes',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    PopupMenuButton<PantrySortOption>(
                      tooltip: 'Ordenar ingredientes',
                      initialValue: _sortOption,
                      onSelected: _setSortOption,
                      child: LiquidGlassPill(
                        icon: Icons.sort_rounded,
                        label: switch (_sortOption) {
                          PantrySortOption.name => 'A-Z',
                          PantrySortOption.expiry => 'Validade',
                          PantrySortOption.quantity => 'Estoque',
                        },
                        color: scheme.primary,
                      ),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: PantrySortOption.name,
                          child: Text('Ordenar por nome (A-Z)'),
                        ),
                        PopupMenuItem(
                          value: PantrySortOption.expiry,
                          child: Text('Ordenar por validade'),
                        ),
                        PopupMenuItem(
                          value: PantrySortOption.quantity,
                          child: Text('Ordenar por menor estoque'),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${_filteredItems.length} itens',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar ingredientes',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Limpar busca',
                            icon: const Icon(Icons.clear),
                            onPressed: _clearSearch,
                          )
                        : null,
                  ),
                  onChanged: _filterItems,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    PopupMenuButton<PantryStatusFilter>(
                      tooltip: 'Filtrar por situação',
                      initialValue: _statusFilter,
                      onSelected: _setStatusFilter,
                      itemBuilder: (_) => [
                        for (final entry in _statusLabels.entries)
                          PopupMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      child: LiquidGlassPill(
                        icon: Icons.tune_rounded,
                        label: _statusFilter == PantryStatusFilter.all
                            ? 'Situação'
                            : _statusLabels[_statusFilter]!,
                      ),
                    ),
                    PopupMenuButton<({String? category})>(
                      tooltip: 'Filtrar por categoria',
                      initialValue: (category: _selectedCategory),
                      onSelected: (choice) =>
                          _filterByCategory(choice.category),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: (category: null),
                          child: Text('Todas as categorias'),
                        ),
                        for (final category in _categories)
                          PopupMenuItem(
                            value: (category: category),
                            child: Text(category),
                          ),
                      ],
                      child: LiquidGlassPill(
                        icon: Icons.expand_more_rounded,
                        label: _selectedCategory ?? 'Categoria',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_filteredItems.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Nenhum ingrediente corresponde à busca.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 160),
              sliver: SliverList.separated(
                itemCount: _filteredItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, index) {
                  final item = _filteredItems[index];
                  return PantryItemCard(
                    key: ValueKey(item.id),
                    item: item,
                    onConsume: () => _consume(item),
                    onRestock: () => _restock(item),
                    onEdit: () => _editItem(item),
                    onDelete: () => _deleteItem(item),
                    onToggleShoppingList: () => _toggleShoppingList(item),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _recipeView() => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverToBoxAdapter(
          child: LiquidGlassCard(
            prominent: true,
            padding: const EdgeInsets.all(24),
            borderRadius: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    color: Theme.of(context).colorScheme.secondary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _settings.prioritizeExpiringInRecipes &&
                          _items.any(
                            (e) => e.quantity > 0 && e.isExpiringSoon(),
                          )
                      ? 'Aproveite antes de vencer'
                      : 'O que vamos preparar?',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _settings.prioritizeExpiringInRecipes &&
                          _items.any(
                            (e) => e.quantity > 0 && e.isExpiringSoon(),
                          )
                      ? 'Receitas com ${_items.where((e) => e.quantity > 0 && e.isExpiringSoon()).map((e) => e.name).join(', ')}. Priorizamos também os outros ingredientes disponíveis na despensa. Produtos vencidos ficam fora da busca.'
                      : 'Ideias com os ingredientes que você já tem. Priorizamos as receitas que aproveitam melhor sua despensa.',
                  style: const TextStyle(height: 1.4),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _loadingRecipes ? null : _getRecipes,
                  icon: _loadingRecipes
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restaurant_menu),
                  label: Text(
                    _loadingRecipes
                        ? 'Procurando receitas...'
                        : 'Encontrar receitas',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Receitas do TheMealDB • até ${_settings.maxRecipesResults} sugestões • conexão com a internet necessária',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (_recipeError != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_recipeError!, textAlign: TextAlign.center),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        sliver: SliverList.builder(
          itemCount: _recommendations.length,
          itemBuilder: (_, i) => RecipeCard(recipe: _recommendations[i]),
        ),
      ),
    ],
  );
}
