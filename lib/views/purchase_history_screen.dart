import 'dart:async';
import 'package:flutter/material.dart';
import '../data/pantry_database.dart';
import '../models/purchase_line.dart';
import '../services/monthly_consumption.dart';
import 'widgets/liquid_glass.dart';

class PurchaseHistoryScreen extends StatefulWidget {
  final bool monthly;
  const PurchaseHistoryScreen({super.key, this.monthly = false});
  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  List<Map<String, dynamic>>? _events;
  String? _error;
  StreamSubscription<void>? _subscription;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  @override
  void initState() {
    super.initState();
    _subscription = PantryDatabase.instance.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await PantryDatabase.instance.exportChanges();
      if (mounted) {
        setState(() {
          _events =
              data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar o histórico.');
      }
    }
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  List<Map<String, dynamic>> _inMonth(DateTime month) => _events!.where((e) {
        final date = DateTime.tryParse(e['date'] as String? ?? '')?.toLocal();
        return date != null &&
            date.year == month.year &&
            date.month == month.month;
      }).toList();
  int _gross(Map<String, dynamic> e) =>
      ((e['amount'] as num) * (e['unitPriceCents'] as int)).round();
  int _total(List<Map<String, dynamic>> events, {bool discounts = false}) =>
      events.where((e) => e['receipt'] != null).fold(
          0,
          (sum, e) =>
              sum +
              (discounts
                  ? e['discountCents'] as int
                  : _gross(e) - (e['discountCents'] as int)));
  String _comparison(num current, num previous, {bool currency = false}) {
    String format(num n) => currency ? money(n / 100) : quantity(n);
    if (previous == 0) {
      return current == 0
          ? 'Sem registros nos dois meses'
          : 'Anterior: ${format(previous)} • sem base percentual';
    }
    final percent = (current - previous) / previous * 100;
    return 'Anterior: ${format(previous)} • ${percent > 0 ? '+' : ''}${percent.toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  Widget _card(String title, String value, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: LiquidGlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(subtitle),
            ],
          ),
        ),
      );

  List<Widget> _report() {
    final stats = MonthlyConsumption(_events!, _month);
    final current = _inMonth(_month);
    final previous = _inMonth(DateTime(_month.year, _month.month - 1));
    final groups = <String, List<double>>{};
    for (var i = 0; i < 2; i++) {
      for (final e in (i == 0 ? current : previous)
          .where((e) => e['type'] == 'consume')) {
        final key =
            '${e['name'] ?? e['key']} (${e['unit'] ?? 'unidade não informada'})';
        groups.putIfAbsent(key, () => [0, 0])[i] +=
            (e['amount'] as num).toDouble();
      }
    }
    final keys = groups.keys.toList()..sort();
    return [
      Row(children: [
        IconButton(
            tooltip: 'Mês anterior',
            onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1)),
            icon: const Icon(Icons.chevron_left)),
        Expanded(
            child: Text(
                '${_month.month.toString().padLeft(2, '0')}/${_month.year}',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800))),
        IconButton(
            tooltip: 'Próximo mês',
            onPressed: _month.year == DateTime.now().year &&
                    _month.month == DateTime.now().month
                ? null
                : () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1)),
            icon: const Icon(Icons.chevron_right))
      ]),
      const SizedBox(height: 8),
      const Text(
          'Comparação com o mês anterior. O mês atual inclui os registros feitos até agora.'),
      const SizedBox(height: 12),
      _card('Gastos em compras', money(_total(current) / 100),
          _comparison(_total(current), _total(previous), currency: true)),
      _card(
          'Descontos obtidos',
          money(_total(current, discounts: true) / 100),
          _comparison(_total(current, discounts: true),
              _total(previous, discounts: true),
              currency: true)),
      const SizedBox(height: 16),
      Text('Destaques de consumo',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800)),
      const Text(
          'Ranking entre produtos com consumo registrado no mês, separado por unidade. Empates são exibidos juntos.'),
      const SizedBox(height: 10),
      if (stats.byUnit.isEmpty)
        const Padding(
            padding: EdgeInsets.all(16),
            child:
                Text('Registre o consumo na despensa para ver os destaques.')),
      for (final unit in stats.byUnit.keys) ...[
        _card(
            'Mais consumido • $unit',
            stats.extremes(unit, most: true).join(', '),
            '${quantity(stats.byUnit[unit]![stats.extremes(unit, most: true).first]!)} $unit por produto no mês'),
        _card(
            'Menos consumido • $unit',
            stats.extremes(unit, most: false).join(', '),
            '${quantity(stats.byUnit[unit]![stats.extremes(unit, most: false).first]!)} $unit por produto no mês'),
        _card(
            'Média diária • $unit',
            '${quantity(stats.dailyAverage(unit))} $unit/dia',
            'Total consumido nesta unidade ÷ ${stats.days} dias. Inclui dias sem consumo.'),
      ],
      const SizedBox(height: 16),
      Text('Consumo por produto',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800)),
      const Text(
          'Quantidades registradas pela ação Consumir, separadas por produto e unidade.'),
      const SizedBox(height: 10),
      if (keys.isEmpty)
        const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nenhum consumo registrado nestes meses.')),
      for (final key in keys)
        _card(key, quantity(groups[key]![0]),
            '${_comparison(groups[key]![0], groups[key]![1])}\nMédia diária: ${quantity(groups[key]![0] / stats.days)} • ${stats.days} dias considerados'),
      const Text(
          'Registros antigos sem data ou preço não entram nos totais mensais.'),
    ];
  }

  List<Widget> _history() {
    final purchases = _events!.where((e) => e['receipt'] != null).toList()
      ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    final receipts = <String, List<Map<String, dynamic>>>{};
    for (final e in purchases) {
      receipts.putIfAbsent(e['receipt'] as String, () => []).add(e);
    }
    return [
      _card('Total gasto', money(_total(purchases) / 100),
          '${receipts.length} compras • descontos: ${money(_total(purchases, discounts: true) / 100)}'),
      if (purchases.isEmpty)
        const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
                'Nenhuma compra finalizada. Adicione produtos ao carrinho e finalize a compra.')),
      for (final lines in receipts.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: LiquidGlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Compra de ${_date(DateTime.parse(lines.first['date']).toLocal())}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                for (final e in lines)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e['name'] as String,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text(
                                '${quantity(e['amount'] as num)} ${e['unit']} × ${money((e['unitPriceCents'] as int) / 100)}'),
                            Text(
                                'Desconto: ${money((e['discountCents'] as int) / 100)} • Pago: ${money((_gross(e) - (e['discountCents'] as int)) / 100)}')
                          ])),
                const Divider(),
                Text('Total: ${money(_total(lines) / 100)}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: LiquidGlassAppBar(
          title:
              Text(widget.monthly ? 'Resumo mensal' : 'Histórico de compras'),
        ),
        body: LiquidGlassBackground(
          child: _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  TextButton(
                      onPressed: _load, child: const Text('Tentar novamente'))
                ]))
              : _events == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: widget.monthly ? _report() : _history()),
        ),
      );
}
