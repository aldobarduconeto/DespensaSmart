import 'dart:async';

import 'package:flutter/material.dart';

import '../data/pantry_database.dart';
import '../models/pantry_item.dart';
import '../models/purchase_line.dart';
import '../services/app_settings_service.dart';
import '../services/local_model_manager.dart';
import '../services/local_recipe_ai_service.dart';
import '../services/pantry_savings_service.dart';
import 'local_ai_settings_screen.dart';
import 'widgets/liquid_glass.dart';
import 'widgets/stock_dialog.dart';

class SavingsAnalysisScreen extends StatefulWidget {
  const SavingsAnalysisScreen({super.key});

  @override
  State<SavingsAnalysisScreen> createState() => _SavingsAnalysisScreenState();
}

class _SavingsAnalysisScreenState extends State<SavingsAnalysisScreen> {
  static const _periods = <int, String>{
    7: '7 dias',
    30: '30 dias',
    90: '90 dias',
    0: 'Tudo',
  };

  final _db = PantryDatabase.instance;
  final _savingsService = PantrySavingsService.instance;
  final _aiService = LocalRecipeAiService.instance;

  int _selectedDays = 30;
  List<PantryItem> _items = [];
  List<Map<String, dynamic>> _events = [];
  PantrySavingsSummary? _summary;
  bool _loading = true;
  String? _error;

  bool _isAiModelReady = false;
  LinkedModelInfo? _linkedModel;
  bool _generatingAiReport = false;
  String? _aiReport;
  String? _aiError;

  StreamSubscription<void>? _changesSub;

  @override
  void initState() {
    super.initState();
    _changesSub = _db.changes.listen((_) => _loadData());
    _loadData();
    _checkModelStatus();
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
  }

  Future<void> _checkModelStatus() async {
    try {
      final installed = await _aiService.isModelInstalled();
      final linked = await LocalModelManager.instance.getLinkedModelInfo();
      if (mounted) {
        setState(() {
          _isAiModelReady = installed;
          _linkedModel = linked;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final items = await _db.allItems();
      final rawEvents = await _db.exportChanges();
      final events = rawEvents
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (mounted) {
        setState(() {
          _items = items;
          _events = events;
          _summary = _savingsService.calculateSavings(
            pantryItems: items,
            rawEvents: events,
            days: _selectedDays,
            expiryWarningDays: AppSettingsService.instance.expiryWarningDays,
          );
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar os dados financeiros: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _recalculateSummary() {
    _summary = _savingsService.calculateSavings(
      pantryItems: _items,
      rawEvents: _events,
      days: _selectedDays,
      expiryWarningDays: AppSettingsService.instance.expiryWarningDays,
    );
  }

  Future<void> _generateAiAnalysis() async {
    setState(() {
      _generatingAiReport = true;
      _aiError = null;
    });
    try {
      final summary = _summary ?? _savingsService.calculateSavings(
        pantryItems: _items,
        rawEvents: _events,
        days: _selectedDays,
        expiryWarningDays: AppSettingsService.instance.expiryWarningDays,
      );
      final report = await _aiService.generateSavingsReport(
        savingsData: summary.toAiData(),
      );
      if (mounted) {
        setState(() {
          _aiReport = report;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aiError = 'Falha ao gerar relatório: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _generatingAiReport = false);
    }
  }

  Future<void> _openModelScannerDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _ModelScannerBottomSheet(),
    );
    await _checkModelStatus();
  }

  Future<void> _consumeItem(PantryItem item) async {
    final selection = await showConsumptionDialog(context, item);
    if (selection != null && item.id != null) {
      try {
        await _db.consume(
          item.id!,
          selection.amount,
          person: selection.person,
          isWaste: selection.isWaste,
          wasteReason: selection.wasteReason,
        );
        await _loadData();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 800;

    return Scaffold(
      appBar: LiquidGlassAppBar(
        title: const Text('Economias da Despensa'),
        actions: [
          IconButton(
            tooltip: 'Buscar e Vincular Modelo Local',
            icon: const Icon(Icons.link_rounded),
            onPressed: _openModelScannerDialog,
          ),
          IconButton(
            tooltip: 'Configurações de IA',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LocalAiSettingsScreen()),
              );
              await _checkModelStatus();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LiquidGlassBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 920 : 640),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, style: TextStyle(color: scheme.error)),
                        ),
                      )
                    : _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = _summary ?? _savingsService.calculateSavings(
      pantryItems: _items,
      rawEvents: _events,
      days: _selectedDays,
      expiryWarningDays: AppSettingsService.instance.expiryWarningDays,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      children: [
        // 1. FILTER TABS (PERIOD SELECTION)
        LiquidGlassCard(
          padding: const EdgeInsets.all(8),
          borderRadius: 20,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
            segments: _periods.entries.map((e) {
              return ButtonSegment<int>(
                value: e.key,
                label: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600)),
              );
            }).toList(),
            selected: {_selectedDays},
            onSelectionChanged: (val) {
              setState(() {
                _selectedDays = val.first;
                _recalculateSummary();
                _aiReport = null; // Clear previous period's report
              });
            },
          ),
        ),
        const SizedBox(height: 16),

        // 2. HERO TOTAL SAVINGS CARD
        LiquidGlassCard(
          prominent: true,
          padding: const EdgeInsets.all(22),
          borderRadius: 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.savings_rounded,
                      size: 32,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Economia Total Acumulada',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          money(summary.totalAccumulatedSavingsCents / 100),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.primary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Descontos obtidos em compras somados ao valor aproveitado antes do vencimento.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
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
                    icon: Icons.trending_up_rounded,
                    label: 'Aproveitamento: ${(summary.stockUtilizationRate * 100).toStringAsFixed(0)}%',
                    color: scheme.primary,
                  ),
                  LiquidGlassPill(
                    icon: Icons.calendar_month_rounded,
                    label: 'Projeção anual: ${money(summary.projectedAnnualSavingsCents / 100)}',
                    color: scheme.secondary,
                  ),
                  if (_linkedModel != null && _linkedModel!.isAvailable)
                    LiquidGlassPill(
                      icon: Icons.offline_bolt_rounded,
                      label: 'Modelo local vinculado',
                      color: scheme.tertiary,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 3. 4-GRID KEY FINANCIAL METRICS
        Row(
          children: [
            Expanded(
              child: _buildMetricMiniCard(
                context,
                title: 'Descontos em Compras',
                value: money(summary.discountsEarnedCents / 100),
                icon: Icons.local_offer_outlined,
                color: Colors.teal,
                subtitle: 'Total economizado em notas fiscais',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricMiniCard(
                context,
                title: 'Desperdício Evitado',
                value: money(summary.avoidedWasteCents / 100),
                icon: Icons.verified_outlined,
                color: Colors.green,
                subtitle: 'Alimentos consumidos dentro do prazo',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricMiniCard(
                context,
                title: 'Estoque em Risco',
                value: money(summary.valueAtRiskCents / 100),
                icon: Icons.warning_amber_rounded,
                color: summary.valueAtRiskCents > 0 ? Colors.orange : Colors.grey,
                subtitle: '${summary.opportunities.length} item(ns) vencendo/vencidos',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricMiniCard(
                context,
                title: 'Patrimônio Despensa',
                value: money(summary.inventoryValueCents / 100),
                icon: Icons.kitchen_rounded,
                color: Colors.blueGrey,
                subtitle: 'Valor total em estoque hoje',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 4. LOCAL AI SAVINGS ANALYSIS CARD
        _buildAiSection(context, summary),
        const SizedBox(height: 24),

        // 5. IMMEDIATE SAVINGS OPPORTUNITIES (ITEMS EXPIRING SOON)
        Text(
          'Oportunidades Imediatas de Economia',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Evite perder dinheiro consumindo ou preparando estes itens antes que estraguem.',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        if (summary.opportunities.isEmpty)
          LiquidGlassCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Parabéns! Nenhum item próximo do vencimento com risco de perda financeira.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          )
        else
          LiquidGlassCard(
            padding: EdgeInsets.zero,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: summary.opportunities.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
              itemBuilder: (ctx, index) {
                final opp = summary.opportunities[index];
                final isExpired = opp.daysUntilExpiry < 0;
                return ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isExpired
                          ? scheme.error.withValues(alpha: 0.12)
                          : Colors.orange.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isExpired ? Icons.delete_outline_rounded : Icons.timer_outlined,
                      color: isExpired ? scheme.error : Colors.orange.shade800,
                    ),
                  ),
                  title: Text(
                    opp.item.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${opp.reason} • Valor em risco: ${money(opp.estimatedLossCents / 100)}',
                    style: TextStyle(
                      color: isExpired ? scheme.error : scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () => _consumeItem(opp.item),
                    child: const Text('Consumir'),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 24),

        // 6. PRICE COMPARISON & BARGAIN TRACKER
        Text(
          'Melhores Preços e Descontos Obtidos',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Comparação de preços históricos e descontos capturados no checkout.',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        if (summary.priceInsights.isEmpty)
          LiquidGlassCard(
            padding: const EdgeInsets.all(18),
            child: const Text(
              'Registre compras com preços e descontos para alimentar o histórico comparativo.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          )
        else
          LiquidGlassCard(
            padding: EdgeInsets.zero,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: summary.priceInsights.take(8).length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
              itemBuilder: (ctx, index) {
                final price = summary.priceInsights[index];
                return ListTile(
                  title: Text(price.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    'Menor pago: ${money(price.lowestPriceCents / 100)} • Mais recente: ${money(price.latestPriceCents / 100)}',
                  ),
                  trailing: price.hasDiscountHistory
                      ? Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            'Economizou ${money(price.totalDiscountsCents / 100)}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          backgroundColor: scheme.primary.withValues(alpha: 0.12),
                        )
                      : null,
                );
              },
            ),
          ),
        const SizedBox(height: 24),

        // 7. ANNUAL SAVINGS SIMULATOR
        LiquidGlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_graph_rounded, color: scheme.primary, size: 26),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Meta de Otimização Doméstica',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Comprando com atenção aos descontos e zerando o desperdício por validade, '
                'sua família pode poupar até ${money(summary.projectedAnnualSavingsCents / 100)} ao longo do ano.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildMetricMiniCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LiquidGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAiSection(BuildContext context, PantrySavingsSummary summary) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LiquidGlassCard(
      prominent: true,
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Consultor Financeiro da Despensa (IA Local)',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    Text(
                      _isAiModelReady
                          ? (_linkedModel != null
                              ? 'Modelo vinculado: ${_linkedModel!.fileName}'
                              : 'Modelo local pronto no aparelho')
                          : 'Vincule seu modelo local para análise inteligente offline',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (!_isAiModelReady) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Conecte o modelo Gemma 4 E2B ou qualquer modelo compatível para gerar relatórios com dicas de economia, substituições e diagnóstico.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _openModelScannerDialog,
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Buscar e Vincular Modelo Rapidamente'),
                  ),
                ],
              ),
            ),
          ] else ...[
            if (_aiReport != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: SelectableText(
                  _aiReport!,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
              const SizedBox(height: 14),
            ],

            if (_aiError != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_aiError!, style: TextStyle(color: scheme.error)),
              ),
            ],

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _generatingAiReport ? null : _generateAiAnalysis,
                icon: _generatingAiReport
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.insights_rounded),
                label: Text(
                  _generatingAiReport
                      ? 'Processando localmente no aparelho...'
                      : (_aiReport == null ? 'Gerar Análise com IA Local' : 'Atualizar Análise'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelScannerBottomSheet extends StatefulWidget {
  const _ModelScannerBottomSheet();

  @override
  State<_ModelScannerBottomSheet> createState() => _ModelScannerBottomSheetState();
}

class _ModelScannerBottomSheetState extends State<_ModelScannerBottomSheet> {
  final _manager = LocalModelManager.instance;
  final _pathController = TextEditingController();

  bool _scanning = false;
  bool _linking = false;
  String? _statusMessage;
  String? _error;
  List<LocalModelCandidate> _candidates = [];
  LinkedModelInfo? _currentLinked;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
    _startScan();
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    final info = await _manager.getLinkedModelInfo();
    if (mounted) setState(() => _currentLinked = info);
  }

  Future<void> _startScan({bool forceRefresh = false}) async {
    setState(() {
      _scanning = true;
      _error = null;
      _statusMessage = 'Escaneando Downloads, Documentos e pastas de modelos...';
      _candidates = [];
    });

    try {
      final results = await _manager.scanForModels(
        forceRefresh: forceRefresh,
        onCandidateFound: (candidate) {
          if (mounted) {
            setState(() {
              _candidates = List.of(_candidates)..add(candidate);
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _candidates = results;
          _statusMessage = results.isEmpty
              ? 'Nenhum modelo (.litertlm, .task, .bin) encontrado automaticamente. Você pode colar o caminho manual abaixo.'
              : '${results.length} modelo(s) encontrado(s).';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Erro na busca: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _linkFile(String path) async {
    setState(() {
      _linking = true;
      _error = null;
    });
    try {
      await _manager.linkModel(path);
      await _loadCurrent();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Modelo vinculado com sucesso ao aplicativo!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Falha ao vincular: $e');
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  Future<void> _unlink() async {
    setState(() => _linking = true);
    try {
      await _manager.unlinkModel();
      await _loadCurrent();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Modelo desvinculado.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Erro ao desvincular: $e');
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.offline_bolt_rounded, color: scheme.primary, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Vincular Modelo Local',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_scanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: 'Repetir busca',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => _startScan(forceRefresh: true),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Otimização de busca rápida em diretórios locais. Conecta arquivos .litertlm, .task ou .bin sem precisar baixar novamente.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            if (_currentLinked != null && _currentLinked!.isAvailable) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentLinked!.fileName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Tamanho: ${_currentLinked!.formattedSize} • ${_currentLinked!.path}',
                            style: const TextStyle(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _linking ? null : _unlink,
                      child: const Text('Desvincular'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
              ),
              const SizedBox(height: 14),
            ],

            if (_statusMessage != null) ...[
              Text(
                _statusMessage!,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
            ],

            if (_candidates.isNotEmpty) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _candidates.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, index) {
                    final cand = _candidates[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        cand.isGemma ? Icons.auto_awesome : Icons.insert_drive_file_outlined,
                        color: cand.isGemma ? scheme.primary : scheme.outline,
                      ),
                      title: Text(
                        cand.fileName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${cand.formattedSize} • ${cand.directory}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: _linking ? null : () => _linkFile(cand.path),
                        child: const Text('Vincular'),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],

            const Text(
              'Ou digite/cole o caminho absoluto do arquivo:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    decoration: const InputDecoration(
                      hintText: 'C:\\modelos\\gemma-4-E2B-it.litertlm',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _linking
                      ? null
                      : () {
                          final text = _pathController.text.trim();
                          if (text.isNotEmpty) _linkFile(text);
                        },
                  child: _linking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Vincular'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
