import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/categories.dart';
import '../data/pantry_database.dart';
import '../models/pantry_item.dart';
import '../services/app_settings_service.dart';
import '../services/expiry_notification_service.dart';
import '../services/pantry_background_service.dart';
import '../sync/lan_sync.dart';
import 'onboarding_screen.dart';
import 'purchase_history_screen.dart';
import 'widgets/lan_sync_settings.dart';
import 'widgets/liquid_glass.dart';
import 'local_ai_settings_screen.dart';
import 'family_consumption_screen.dart';
import 'widgets/pantry_notification_settings.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _db = PantryDatabase.instance;
  final _appSettings = AppSettingsService.instance;
  final _expiryService = ExpiryNotificationService.instance;
  final _bgService = PantryBackgroundService.instance;
  final _lanSync = LanSync.instance;

  late ThemeMode _selectedMode;
  StreamSubscription<void>? _dbSub;
  List<PantryItem> _items = [];
  int _eventsCount = 0;
  int _receiptsCount = 0;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.themeMode;
    _dbSub = _db.changes.listen((_) => _loadStats());
    _loadStats();
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final items = await _db.allItems();
      final events = await _db.exportChanges();
      final receipts = events
          .map((e) => (e as Map)['receipt'])
          .whereType<String>()
          .toSet()
          .length;
      if (mounted) {
        setState(() {
          _items = items;
          _eventsCount = events.length;
          _receiptsCount = receipts;
        });
      }
    } catch (_) {}
  }

  void _changeTheme(ThemeMode mode) {
    setState(() => _selectedMode = mode);
    widget.onThemeModeChanged(mode);
  }

  void _openOnboarding() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => OnboardingScreen(
          isRevisit: true,
          onFinish: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }

  Future<void> _exportBackup() async {
    try {
      final json = await _db.exportBackupJson();
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backup exportado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'O código JSON completo da sua despensa e histórico foi copiado para a área de transferência.',
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    json,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Concluído'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível exportar o backup.')),
        );
      }
    }
  }

  Future<void> _importBackup() async {
    final controller = TextEditingController();
    var replace = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Importar backup (JSON)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cole abaixo o JSON exportado de outro backup do Despensa Smart:',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: '{"device": "...", "events": [...]}',
                    suffixIcon: IconButton(
                      tooltip: 'Colar da área de transferência',
                      icon: const Icon(Icons.paste_rounded),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          controller.text = data!.text!;
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Substituir dados atuais'),
                  subtitle: Text(
                    replace
                        ? 'Apaga os itens atuais antes de restaurar o backup.'
                        : 'Mescla o backup com os itens que já estão no aparelho.',
                  ),
                  value: replace,
                  onChanged: (v) => setDialogState(() => replace = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Importar'),
            ),
          ],
        ),
      ),
    );
    final raw = controller.text.trim();
    controller.dispose();
    if (confirmed != true || raw.isEmpty) return;
    try {
      await _db.importBackupJson(raw, replace: replace);
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup importado com sucesso!')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Formato de backup inválido. Verifique o JSON colado e tente novamente.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _clearOutOfStock() async {
    final emptyCount = _items.where((e) => e.quantity == 0).length;
    if (emptyCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não há itens esgotados na despensa.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover itens esgotados'),
        content: Text(
          'Deseja excluir os $emptyCount itens que estão com quantidade zero na despensa?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover esgotados'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final removed = await _db.deleteOutOfStockItems();
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$removed item(ns) esgotado(s) removido(s).')),
      );
    }
  }

  Future<void> _clearShoppingList() async {
    final shoppingCount = _items.where((e) => e.inShoppingList).length;
    if (shoppingCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A lista de compras já está vazia.')),
      );
      return;
    }
    final cleared = await _db.clearShoppingList();
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$cleared item(ns) desmarcado(s) da lista de compras.'),
        ),
      );
    }
  }

  Future<void> _confirmClearAllData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar toda a despensa?'),
        content: const Text(
          'Esta ação removerá todos os ingredientes cadastrados e o histórico de compras deste aparelho. Recomendamos exportar um backup antes de continuar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar tudo'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _db.clearAllData();
    await _bgService.clearRecipeInbox();
    await _expiryService.refresh();
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Todos os dados da despensa foram apagados.')),
      );
    }
  }

  Future<void> _resetDefaultSettings() async {
    await _appSettings.resetToDefaults();
    await _bgService.clearCustomThresholds();
    _changeTheme(ThemeMode.system);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configurações restauradas para o padrão de fábrica.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final stockedCount = _items.where((e) => e.quantity > 0).length;

    return ListenableBuilder(
      listenable:
          Listenable.merge([_appSettings, _expiryService, _bgService, _lanSync]),
      builder: (context, _) {
        final blurMode = _appSettings.glassBlurSigma <= 12
            ? 'soft'
            : _appSettings.glassBlurSigma >= 24
                ? 'high'
                : 'normal';

        return Scaffold(
          appBar: LiquidGlassAppBar(
            title: const Text('Configurações'),
            actions: [
              IconButton(
                tooltip: 'Apresentação e permissões',
                onPressed: _openOnboarding,
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: LiquidGlassBackground(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 900 : 640),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // HERO STATUS CARD
                    LiquidGlassCard(
                      prominent: true,
                      padding: const EdgeInsets.all(22),
                      borderRadius: 28,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  Icons.kitchen_rounded,
                                  size: 30,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Despensa Smart',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 20,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Controle completo da sua despensa, alertas, receitas e sincronização.',
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
                                icon: Icons.inventory_2_outlined,
                                label:
                                    '${_items.length} itens ($stockedCount em estoque)',
                                color: scheme.primary,
                              ),
                              LiquidGlassPill(
                                icon: Icons.notifications_active_outlined,
                                label: _expiryService.enabled ||
                                        _bgService.enabled
                                    ? 'Alertas ativos'
                                    : 'Alertas desativados',
                                color: _expiryService.enabled ||
                                        _bgService.enabled
                                    ? scheme.primary
                                    : scheme.outline,
                              ),
                              LiquidGlassPill(
                                icon: Icons.wifi_rounded,
                                label: _lanSync.enabled
                                    ? 'Rede local ativa'
                                    : 'Rede local inativa',
                                color: _lanSync.enabled
                                    ? scheme.primary
                                    : scheme.outline,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: _openOnboarding,
                                icon: const Icon(Icons.auto_awesome_outlined,
                                    size: 18),
                                label: const Text(
                                    'Apresentação e Permissões'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const PurchaseHistoryScreen(
                                        monthly: true),
                                  ),
                                ),
                                icon: const Icon(Icons.insights_rounded,
                                    size: 18),
                                label: const Text('Relatório mensal'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),

                    // 1. APARÊNCIA E LIQUID GLASS
                    Text(
                      'Aparência e Liquid Glass',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    LiquidGlassCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tema do aplicativo',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<ThemeMode>(
                            expandedInsets: EdgeInsets.zero,
                            segments: const [
                              ButtonSegment(
                                value: ThemeMode.system,
                                icon: Icon(Icons.brightness_auto_outlined),
                                label: Text('Sistema'),
                              ),
                              ButtonSegment(
                                value: ThemeMode.light,
                                icon: Icon(Icons.light_mode_outlined),
                                label: Text('Claro'),
                              ),
                              ButtonSegment(
                                value: ThemeMode.dark,
                                icon: Icon(Icons.dark_mode_outlined),
                                label: Text('Escuro'),
                              ),
                            ],
                            selected: {_selectedMode},
                            onSelectionChanged: (selection) =>
                                _changeTheme(selection.first),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Intensidade da refração Liquid Glass',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<String>(
                            expandedInsets: EdgeInsets.zero,
                            segments: const [
                              ButtonSegment(
                                value: 'soft',
                                icon: Icon(Icons.blur_linear_rounded),
                                label: Text('Suave'),
                              ),
                              ButtonSegment(
                                value: 'normal',
                                icon: Icon(Icons.blur_on_rounded),
                                label: Text('Padrão'),
                              ),
                              ButtonSegment(
                                value: 'high',
                                icon: Icon(Icons.lens_blur_rounded),
                                label: Text('Intenso'),
                              ),
                            ],
                            selected: {blurMode},
                            onSelectionChanged: (sel) {
                              final sigma = switch (sel.first) {
                                'soft' => 10.0,
                                'high' => 28.0,
                                _ => 18.0,
                              };
                              _appSettings.setGlassBlurSigma(sigma);
                            },
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Orbes luminosos de fundo',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Exibe luzes ambientes suaves atrás das superfícies translúcidas.',
                            ),
                            value: _appSettings.ambientOrbsEnabled,
                            onChanged: _appSettings.setAmbientOrbsEnabled,
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Cartões compactos na despensa',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Reduz o espaçamento vertical dos ingredientes para exibir mais itens na tela.',
                            ),
                            value: _appSettings.compactCards,
                            onChanged: _appSettings.setCompactCards,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),

                    // 2. PADRÕES DA DESPENSA E VALIDADE
                    Text(
                      'Despensa, Cadastro e Validade',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    LiquidGlassCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _appSettings.defaultCategory,
                                  decoration: const InputDecoration(
                                    labelText: 'Categoria padrão ao adicionar',
                                    prefixIcon: Icon(Icons.category_outlined),
                                  ),
                                  items: AppConstants.categories
                                      .map((c) => DropdownMenuItem(
                                          value: c, child: Text(c)))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      _appSettings.setDefaultCategory(v);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _appSettings.defaultUnit,
                                  decoration: const InputDecoration(
                                    labelText: 'Unidade de medida padrão',
                                    prefixIcon: Icon(Icons.straighten_rounded),
                                  ),
                                  items: AppConstants.units
                                      .map((u) => DropdownMenuItem(
                                          value: u, child: Text(u)))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      _appSettings.setDefaultUnit(v);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _appSettings.defaultSort,
                            decoration: const InputDecoration(
                              labelText: 'Ordenação padrão da despensa',
                              prefixIcon: Icon(Icons.sort_rounded),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'name',
                                child: Text('Ordem alfabética (A-Z)'),
                              ),
                              DropdownMenuItem(
                                value: 'expiry',
                                child: Text('Validade mais próxima'),
                              ),
                              DropdownMenuItem(
                                value: 'quantity',
                                child: Text('Menor quantidade em estoque'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) _appSettings.setDefaultSort(v);
                            },
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Alerta de "Vence em breve": ${_appSettings.expiryWarningDays} dias antes',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Define quantos dias antes da data de vencimento um produto ganha destaque na despensa e nos lembretes.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [3, 5, 7, 14, 30].map((days) {
                              final selected =
                                  _appSettings.expiryWarningDays == days;
                              return ChoiceChip(
                                label: Text('$days dias'),
                                selected: selected,
                                onSelected: (_) =>
                                    _appSettings.setExpiryWarningDays(days),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 10),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Enviar automaticamente para compras ao zerar',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Quando você consome todo o estoque de um item, ele entra direto na lista de compras.',
                            ),
                            value: _appSettings.autoAddToShoppingListOnZero,
                            onChanged:
                                _appSettings.setAutoAddToShoppingListOnZero,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),

                    // 3. NOTIFICAÇÕES E SEGUNDO PLANO
                    const PantryNotificationSettings(),
                    const SizedBox(height: 26),

                    // 4. RECEITAS E SUGESTÕES
                    Text(
                      'Recomendações de Receitas',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    LiquidGlassCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: Icon(Icons.priority_high_rounded,
                                color: scheme.secondary),
                            title: const Text(
                              'Priorizar ingredientes perto de vencer',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: const Text(
                              'Dá preferência às receitas que utilizam itens com validade próxima.',
                            ),
                            value: _appSettings.prioritizeExpiringInRecipes,
                            onChanged:
                                _appSettings.setPrioritizeExpiringInRecipes,
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.auto_awesome_rounded,
                              color: scheme.primary,
                            ),
                            title: const Text(
                              'IA local e modo família',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: const Text(
                              'Modelo local, pessoas da casa, preferências e relatórios de consumo.',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LocalAiSettingsScreen(),
                              ),
                            ),
                          ),
                          const Divider(height: 16),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.bar_chart_rounded,
                              color: scheme.secondary,
                            ),
                            title: const Text(
                              'Consumo e gastos da casa',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: const Text(
                              'Consulte períodos de uma semana a um ano e gere análise com a IA local.',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const FamilyConsumptionScreen(),
                              ),
                            ),
                          ),
                          const Divider(height: 20),
                          const Text(
                            'Limite de receitas exibidas por consulta',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<int>(
                            expandedInsets: EdgeInsets.zero,
                            segments: const [
                              ButtonSegment(
                                value: 10,
                                label: Text('Até 10'),
                              ),
                              ButtonSegment(
                                value: 15,
                                label: Text('Até 15'),
                              ),
                              ButtonSegment(
                                value: 20,
                                label: Text('Até 20'),
                              ),
                            ],
                            selected: {
                              [10, 15, 20]
                                      .contains(_appSettings.maxRecipesResults)
                                  ? _appSettings.maxRecipesResults
                                  : 20
                            },
                            onSelectionChanged: (s) =>
                                _appSettings.setMaxRecipesResults(s.first),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await _bgService.clearRecipeInbox();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Cache e histórico de sugestões de receitas limpos.',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.cleaning_services_outlined,
                                size: 18),
                            label:
                                const Text('Limpar cache de receitas sugeridas'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),

                    // 5. SINCRONIZAÇÃO NA REDE LOCAL
                    const LanSyncSettings(),
                    const SizedBox(height: 26),

                    // 6. DADOS, BACKUP E PRIVACIDADE
                    Text(
                      'Backup, Dados e Privacidade',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    LiquidGlassCard(
                      child: Column(
                        children: [
                          ListTile(
                            leading: Icon(Icons.storage_rounded,
                                color: scheme.primary),
                            title: const Text(
                              'Armazenamento 100% local',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '${_items.length} produtos • $_receiptsCount compras registradas • $_eventsCount operações no histórico.',
                            ),
                          ),
                          const Divider(height: 1, indent: 56),
                          ListTile(
                            leading: const Icon(Icons.upload_file_rounded),
                            title: const Text('Exportar backup (JSON)'),
                            subtitle: const Text(
                              'Copia todos os seus produtos e histórico de compras para guardar ou transferir.',
                            ),
                            trailing: const Icon(Icons.copy_rounded, size: 20),
                            onTap: _exportBackup,
                          ),
                          const Divider(height: 1, indent: 56),
                          ListTile(
                            leading:
                                const Icon(Icons.settings_backup_restore_rounded),
                            title: const Text('Importar / Restaurar backup'),
                            subtitle: const Text(
                              'Restaure ou mescle dados a partir de um JSON exportado.',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _importBackup,
                          ),
                          const Divider(height: 1, indent: 56),
                          ListTile(
                            leading: const Icon(
                                Icons.remove_shopping_cart_outlined),
                            title: const Text('Desmarcar toda a lista de compras'),
                            subtitle: const Text(
                              'Mantém os produtos na despensa, mas limpa os itens marcados para compra.',
                            ),
                            onTap: _clearShoppingList,
                          ),
                          const Divider(height: 1, indent: 56),
                          ListTile(
                            leading: const Icon(
                                Icons.production_quantity_limits_rounded),
                            title: const Text('Excluir itens esgotados'),
                            subtitle: const Text(
                              'Remove da despensa todos os produtos com quantidade igual a zero.',
                            ),
                            onTap: _clearOutOfStock,
                          ),
                          const Divider(height: 1, indent: 56),
                          ListTile(
                            leading: const Icon(Icons.restart_alt_rounded),
                            title:
                                const Text('Restaurar preferências originais'),
                            subtitle: const Text(
                              'Volta tema, unidades padrão e limites ao estado inicial sem apagar seus produtos.',
                            ),
                            onTap: _resetDefaultSettings,
                          ),
                          const Divider(height: 1, indent: 56),
                          ListTile(
                            leading: Icon(Icons.delete_forever_outlined,
                                color: scheme.error),
                            title: Text(
                              'Apagar todos os dados da despensa',
                              style: TextStyle(
                                color: scheme.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: const Text(
                              'Remove permanentemente todos os produtos e o histórico deste aparelho.',
                            ),
                            onTap: _confirmClearAllData,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),

                    // 7. SOBRE O APLICATIVO
                    Text(
                      'Sobre o Aplicativo',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    LiquidGlassCard(
                      child: Column(
                        children: [
                          const ListTile(
                            leading: Icon(Icons.info_outline),
                            title: Text('Despensa Smart • Versão 1.0.0'),
                            subtitle: Text(
                              'Visual Liquid Glass • Recomendações de receitas integradas ao TheMealDB.',
                            ),
                          ),
                          const Divider(height: 1, indent: 56),
                          ListTile(
                            leading: const Icon(Icons.slideshow_rounded),
                            title: const Text(
                                'Rever tela de apresentação e permissões'),
                            subtitle: const Text(
                              'Veja novamente os destaques do sistema e o assistente de permissões.',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _openOnboarding,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Compartilhe os dados pela rede local ativando o mesmo código da casa em cada aparelho.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
