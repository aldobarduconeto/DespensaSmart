import 'dart:async';

import 'package:flutter/material.dart';

import '../data/pantry_database.dart';
import '../models/pantry_item.dart';
import '../services/date_formatter.dart';
import '../services/pantry_forecast_service.dart';
import 'widgets/liquid_glass.dart';

class PantryForecastScreen extends StatefulWidget {
  const PantryForecastScreen({super.key});

  @override
  State<PantryForecastScreen> createState() => _PantryForecastScreenState();
}

class _PantryForecastScreenState extends State<PantryForecastScreen> {
  final _db = PantryDatabase.instance;
  final _service = PantryForecastService.instance;

  List<PantryItem> _items = [];
  List<ItemDepletionForecast> _forecasts = [];
  bool _loading = true;
  String? _error;
  StockDepletionLevel? _selectedFilter;
  StreamSubscription<void>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _db.changes.listen((_) => _loadData());
    _loadData();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final items = await _db.allItems();
      final rawEvents = await _db.exportChanges();
      final events = rawEvents
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final forecasts = _service.calculateForecasts(
        items: items,
        rawEvents: events,
      );

      if (mounted) {
        setState(() {
          _items = items;
          _forecasts = forecasts;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar a previsão: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleShoppingList(PantryItem item) async {
    try {
      await _db.update(item.copyWith(inShoppingList: !item.inShoppingList));
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !item.inShoppingList
                  ? '${item.name} adicionado à lista de compras.'
                  : '${item.name} removido da lista de compras.',
            ),
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 750;

    final filtered = _selectedFilter == null
        ? _forecasts
        : _forecasts.where((f) => f.level == _selectedFilter).toList();

    final criticalCount =
        _forecasts.where((f) => f.level == StockDepletionLevel.critical).length;
    final warningCount =
        _forecasts.where((f) => f.level == StockDepletionLevel.warning).length;

    return Scaffold(
      appBar: const LiquidGlassAppBar(
        title: Text('Previsão de Estoque e Ritmo'),
      ),
      body: LiquidGlassBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 880 : 640),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: TextStyle(color: scheme.error)))
                    : ListView(
                        padding: const EdgeInsets.all(18),
                        children: [
                          // 1. HERO SUMMARY CARD
                          LiquidGlassCard(
                            prominent: true,
                            padding: const EdgeInsets.all(20),
                            borderRadius: 24,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: scheme.primary.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Icon(
                                        Icons.timeline_rounded,
                                        color: scheme.primary,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Ritmo de Consumo Inteligente',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'Previsão de quando seus mantimentos vão acabar',
                                            style: TextStyle(fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    LiquidGlassPill(
                                      icon: Icons.error_outline_rounded,
                                      label: '$criticalCount crítico(s) (< 3 dias)',
                                      color: criticalCount > 0 ? scheme.error : scheme.primary,
                                    ),
                                    LiquidGlassPill(
                                      icon: Icons.warning_amber_rounded,
                                      label: '$warningCount atenção (< 7 dias)',
                                      color: warningCount > 0 ? Colors.orange : scheme.primary,
                                    ),
                                    LiquidGlassPill(
                                      icon: Icons.inventory_2_outlined,
                                      label: '${_items.length} itens monitorados',
                                      color: scheme.primary,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 2. FILTER PILLS
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                FilterChip(
                                  label: const Text('Todos'),
                                  selected: _selectedFilter == null,
                                  onSelected: (_) => setState(() => _selectedFilter = null),
                                ),
                                const SizedBox(width: 8),
                                FilterChip(
                                  label: const Text('Críticos (< 3d)'),
                                  selected: _selectedFilter == StockDepletionLevel.critical,
                                  onSelected: (_) => setState(
                                    () => _selectedFilter = StockDepletionLevel.critical,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilterChip(
                                  label: const Text('Atenção (< 7d)'),
                                  selected: _selectedFilter == StockDepletionLevel.warning,
                                  onSelected: (_) => setState(
                                    () => _selectedFilter = StockDepletionLevel.warning,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilterChip(
                                  label: const Text('Confortáveis (> 7d)'),
                                  selected: _selectedFilter == StockDepletionLevel.comfortable,
                                  onSelected: (_) => setState(
                                    () => _selectedFilter = StockDepletionLevel.comfortable,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilterChip(
                                  label: const Text('Esgotados'),
                                  selected: _selectedFilter == StockDepletionLevel.outOfStock,
                                  onSelected: (_) => setState(
                                    () => _selectedFilter = StockDepletionLevel.outOfStock,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // 3. FORECAST LIST
                          if (filtered.isEmpty)
                            LiquidGlassCard(
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                child: Text(
                                  'Nenhum item com esse filtro.',
                                  style: TextStyle(color: scheme.onSurfaceVariant),
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (ctx, index) {
                                final f = filtered[index];
                                final item = f.item;

                                final Color cardColor;
                                final IconData icon;

                                switch (f.level) {
                                  case StockDepletionLevel.critical:
                                    cardColor = scheme.error;
                                    icon = Icons.error_outline_rounded;
                                    break;
                                  case StockDepletionLevel.warning:
                                    cardColor = Colors.orange;
                                    icon = Icons.warning_amber_rounded;
                                    break;
                                  case StockDepletionLevel.comfortable:
                                    cardColor = Colors.green;
                                    icon = Icons.check_circle_outline_rounded;
                                    break;
                                  case StockDepletionLevel.outOfStock:
                                    cardColor = Colors.blueGrey;
                                    icon = Icons.remove_shopping_cart_outlined;
                                    break;
                                  case StockDepletionLevel.untracked:
                                    cardColor = scheme.outline;
                                    icon = Icons.help_outline_rounded;
                                    break;
                                }

                                return LiquidGlassCard(
                                  padding: const EdgeInsets.all(16),
                                  borderRadius: 20,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: cardColor.withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Icon(icon, color: cardColor, size: 22),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Estoque: ${item.quantity} ${item.unit} • ${f.velocityText}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: cardColor.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    f.badgeText,
                                                    style: TextStyle(
                                                      color: cardColor,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                                if (f.estimatedRunoutDate != null) ...[
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Término est.: ${DateFormatter.formatShort(f.estimatedRunoutDate!)}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: scheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton.filledTonal(
                                        tooltip: item.inShoppingList
                                            ? 'Na lista de compras'
                                            : 'Adicionar à lista',
                                        icon: Icon(
                                          item.inShoppingList
                                              ? Icons.shopping_cart_rounded
                                              : Icons.add_shopping_cart_rounded,
                                          color: item.inShoppingList ? scheme.primary : null,
                                        ),
                                        onPressed: () => _toggleShoppingList(item),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 32),
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}
