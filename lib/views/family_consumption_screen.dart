import 'dart:async';

import 'package:flutter/material.dart';

import '../data/pantry_database.dart';
import '../models/purchase_line.dart';
import '../services/family_mode_service.dart';
import '../services/local_recipe_ai_service.dart';
import '../sync/lan_sync.dart';
import 'widgets/liquid_glass.dart';

class FamilyConsumptionScreen extends StatefulWidget {
  const FamilyConsumptionScreen({super.key});

  @override
  State<FamilyConsumptionScreen> createState() =>
      _FamilyConsumptionScreenState();
}

class _FamilyConsumptionScreenState extends State<FamilyConsumptionScreen> {
  static const _allPeople = '__all_people__';
  static const _periods = <int, String>{
    7: '1 semana',
    30: '1 mês',
    90: '3 meses',
    180: '6 meses',
    365: '1 ano',
  };

  List<Map<String, dynamic>> _events = [];
  int _days = 7;
  String? _selectedPerson;
  String? _error;
  String? _aiReport;
  bool _loading = true;
  bool _generating = false;
  bool _familyEnabled = false;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = PantryDatabase.instance.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      await LanSync.instance.initialize();
      await FamilyModeService.instance.load();
      final events = await PantryDatabase.instance.exportChanges();
      if (mounted) {
        setState(() {
          _events = events
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _familyEnabled = FamilyModeService.instance.available;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar o consumo: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime get _periodStart {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: _days - 1));
  }

  List<Map<String, dynamic>> get _periodEvents => _events.where((event) {
    final date = DateTime.tryParse(event['date'] as String? ?? '')?.toLocal();
    final now = DateTime.now();
    return date != null && !date.isBefore(_periodStart) && !date.isAfter(now);
  }).toList();

  List<Map<String, dynamic>> get _purchases =>
      _periodEvents.where((event) => event['receipt'] is String).toList();

  List<Map<String, dynamic>> get _consumption => _periodEvents
      .where((event) => event['type'] == 'consume')
      .where(
        (event) =>
            !_familyEnabled ||
            _selectedPerson == null ||
            (event['person'] as String? ?? 'Sem identificação') ==
                _selectedPerson,
      )
      .toList();

  int get _spendingCents => _purchases.fold(0, (total, event) {
    final amount = (event['amount'] as num?)?.toDouble() ?? 0;
    final price = event['unitPriceCents'] as int? ?? 0;
    final discount = event['discountCents'] as int? ?? 0;
    return total + (amount * price).round() - discount;
  });

  int get _discountCents => _purchases.fold(
    0,
    (total, event) => total + (event['discountCents'] as int? ?? 0),
  );

  Map<String, double> get _consumptionByProduct {
    final totals = <String, double>{};
    for (final event in _consumption) {
      final name =
          event['name'] as String? ?? event['key'] as String? ?? 'Item';
      final unit = event['unit'] as String? ?? 'unidade';
      final amount = (event['amount'] as num?)?.toDouble() ?? 0;
      final key = '$name ($unit)';
      totals[key] = (totals[key] ?? 0) + amount;
    }
    return totals;
  }

  Map<String, Map<String, double>> get _consumptionByPerson {
    final totals = <String, Map<String, double>>{};
    for (final event in _periodEvents.where(
      (event) => event['type'] == 'consume',
    )) {
      final person = event['person'] as String? ?? 'Sem identificação';
      final unit = event['unit'] as String? ?? 'unidade';
      final personTotals = totals.putIfAbsent(person, () => {});
      personTotals[unit] =
          (personTotals[unit] ?? 0) +
          ((event['amount'] as num?)?.toDouble() ?? 0);
    }
    return totals;
  }

  Future<void> _generateReport() async {
    if (_generating) return;
    setState(() {
      _generating = true;
      _error = null;
      _aiReport = null;
    });
    final expenses = <String, Object?>{
      'compras': _purchases.length,
      'gasto_registrado_reais': _spendingCents / 100,
      'descontos_registrados_reais': _discountCents / 100,
      'itens_consumidos_por_produto_unidade': _consumptionByProduct,
    };
    if (_familyEnabled) {
      expenses['consumo_por_pessoa'] = _consumptionByPerson;
    }
    try {
      final report = await LocalRecipeAiService.instance
          .generateConsumptionReport(
            data: {
              'periodo': _periods[_days],
              'inicio': _periodStart.toIso8601String(),
              'fim': DateTime.now().toIso8601String(),
              ...expenses,
            },
          );
      if (mounted) setState(() => _aiReport = report);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Widget _metricCard(
    String title,
    String value,
    String detail,
    IconData icon,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: LiquidGlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = _consumptionByPerson.keys.toList()..sort();
    final products = _consumptionByProduct.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final wide = MediaQuery.sizeOf(context).width >= 700;

    return Scaffold(
      appBar: const LiquidGlassAppBar(title: Text('Consumo da casa')),
      body: LiquidGlassBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 900 : 640),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      LiquidGlassCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Período do relatório',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _periods.entries
                                  .map(
                                    (period) => ChoiceChip(
                                      label: Text(period.value),
                                      selected: _days == period.key,
                                      onSelected: (_) => setState(() {
                                        _days = period.key;
                                        _aiReport = null;
                                      }),
                                    ),
                                  )
                                  .toList(),
                            ),
                            if (_familyEnabled) ...[
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedPerson ?? _allPeople,
                                decoration: const InputDecoration(
                                  labelText: 'Filtrar consumo por pessoa',
                                  prefixIcon: Icon(
                                    Icons.people_outline_rounded,
                                  ),
                                ),
                                items: [
                                  const DropdownMenuItem<String>(
                                    value: _allPeople,
                                    child: Text('Toda a casa'),
                                  ),
                                  ...people.map(
                                    (person) => DropdownMenuItem<String>(
                                      value: person,
                                      child: Text(person),
                                    ),
                                  ),
                                ],
                                onChanged: (value) => setState(() {
                                  _selectedPerson = value == _allPeople
                                      ? null
                                      : value;
                                  _aiReport = null;
                                }),
                              ),
                            ] else ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Ative o modo família e a sincronização local para identificar quem registrou cada consumo.',
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _metricCard(
                        'Gastos registrados em compras',
                        money(_spendingCents / 100),
                        '${_purchases.map((event) => event['receipt']).toSet().length} compras • descontos: ${money(_discountCents / 100)}',
                        Icons.payments_outlined,
                      ),
                      _metricCard(
                        'Registros de consumo',
                        '${_consumption.length}',
                        '${_periods[_days]} • quantidades agrupadas por unidade',
                        Icons.shopping_basket_outlined,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _familyEnabled
                            ? 'Consumo por pessoa'
                            : 'Consumo por produto',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_familyEnabled) ...[
                        if (people.isEmpty)
                          const LiquidGlassCard(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Ainda não há consumos identificados por pessoa no período.',
                            ),
                          ),
                        for (final person in people.where(
                          (person) =>
                              _selectedPerson == null ||
                              person == _selectedPerson,
                        ))
                          _metricCard(
                            person,
                            _consumptionByPerson[person]!.entries
                                .map(
                                  (entry) =>
                                      '${quantity(entry.value)} ${entry.key}',
                                )
                                .join(' • '),
                            'Consumo registrado por unidade.',
                            Icons.person_outline_rounded,
                          ),
                      ],
                      if (products.isEmpty)
                        const LiquidGlassCard(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Nenhum consumo registrado neste período.',
                          ),
                        ),
                      for (final product in products)
                        _metricCard(
                          product.key,
                          quantity(product.value),
                          _familyEnabled
                              ? _personBreakdown(product.key)
                              : 'Quantidade consumida neste período.',
                          Icons.restaurant_outlined,
                        ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _generating ? null : _generateReport,
                        icon: _generating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_rounded),
                        label: Text(
                          _generating
                              ? 'Analisando neste aparelho...'
                              : 'Gerar relatório com IA local',
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      if (_aiReport != null) ...[
                        const SizedBox(height: 12),
                        LiquidGlassCard(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Análise do Gemma 4 E2B',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SelectableText(
                                _aiReport!,
                                style: const TextStyle(height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'Os gastos refletem compras finalizadas e registradas. O consumo é informado manualmente; compras sem preço não entram no total financeiro.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  String _personBreakdown(String product) {
    final parts = product.lastIndexOf(' (');
    final name = parts < 0 ? product : product.substring(0, parts);
    final unit = parts < 0
        ? ''
        : product.substring(parts + 2, product.length - 1);
    final totals = <String, double>{};
    for (final event in _consumption) {
      if ((event['name'] as String? ?? event['key'] as String? ?? 'Item') !=
              name ||
          (event['unit'] as String? ?? 'unidade') != unit) {
        continue;
      }
      final person = event['person'] as String? ?? 'Sem identificação';
      totals[person] =
          (totals[person] ?? 0) + ((event['amount'] as num?)?.toDouble() ?? 0);
    }
    return totals.entries
        .map((entry) => '${entry.key}: ${quantity(entry.value)} $unit')
        .join(' • ');
  }
}
