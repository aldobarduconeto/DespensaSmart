import 'dart:async';
import 'package:flutter/material.dart';
import '../data/pantry_database.dart';
import '../models/pantry_item.dart';
import '../models/purchase_line.dart';
import 'purchase_history_screen.dart';
import 'widgets/liquid_glass.dart';
import 'widgets/purchase_dialog.dart';

class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({super.key});
  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  final _db = PantryDatabase.instance;
  StreamSubscription<void>? _subscription;
  List<PantryItem>? _items;
  final _cart = <int, PurchaseLine>{};
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _subscription = _db.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await _db.allItems();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar os produtos.');
      }
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _edit(PantryItem item) async {
    final line =
        await showPurchaseDialog(context, item, initial: _cart[item.id]);
    if (mounted && line != null) setState(() => _cart[item.id!] = line);
  }

  Future<void> _checkout() async {
    setState(() => _saving = true);
    try {
      await _db.checkout(_cart.values.toList());
      if (!mounted) return;
      setState(() => _cart.clear());
      _message(
        'Compra salva no histórico e adicionada à despensa. Confira a validade dos produtos.',
      );
      await _load();
    } catch (_) {
      _message(
        'Não foi possível finalizar. Confira os produtos e tente novamente.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _cart.values.fold<int>(0, (sum, e) => sum + e.paidCents);
    final discount =
        _cart.values.fold<int>(0, (sum, e) => sum + e.discountCents);
    final available = (_items ?? [])
        .where((e) => e.inShoppingList && !_cart.containsKey(e.id))
        .toList();
    return Scaffold(
      appBar: LiquidGlassAppBar(
        title: const Text('Carrinho de compras'),
        actions: [
          PopupMenuButton<bool>(
            tooltip: 'Compras e relatórios',
            onSelected: (monthly) => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PurchaseHistoryScreen(monthly: monthly),
              ),
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: false,
                child: Text('Histórico de compras'),
              ),
              PopupMenuItem(value: true, child: Text('Resumo mensal')),
            ],
          ),
        ],
      ),
      body: LiquidGlassBackground(
        child: _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              )
            : _items == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PurchaseHistoryScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.receipt_long),
                            label: const Text('Histórico de compras'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const PurchaseHistoryScreen(monthly: true),
                              ),
                            ),
                            icon: const Icon(Icons.insights),
                            label: const Text('Resumo mensal'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Seu carrinho',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (_cart.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            'Escolha produtos e informe a quantidade, o preço e o desconto.',
                          ),
                        ),
                      for (final line in _cart.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: LiquidGlassCard(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.item.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${quantity(line.amount)} ${line.item.unit} × ${money(line.unitPriceCents / 100)}',
                                ),
                                Text(
                                  'Desconto: ${money(line.discountCents / 100)} • Total: ${money(line.paidCents / 100)}',
                                ),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: _saving
                                          ? null
                                          : () => _edit(line.item),
                                      child: const Text('Editar'),
                                    ),
                                    TextButton(
                                      onPressed: _saving
                                          ? null
                                          : () => setState(
                                              () => _cart.remove(line.item.id)),
                                      child: const Text('Remover'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_cart.isNotEmpty)
                        LiquidGlassCard(
                          prominent: true,
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Descontos: ${money(discount / 100)}'),
                              Text(
                                'Total a pagar: ${money(total / 100)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _saving ? null : _checkout,
                                icon: const Icon(Icons.check),
                                label: Text(
                                  _saving ? 'Salvando...' : 'Finalizar compra',
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 22),
                      Text(
                        'Lista de compras',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      if (available.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Marque produtos na despensa ou escolha um produto abaixo.',
                          ),
                        ),
                      for (final item in available)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: LiquidGlassCard(
                            child: ListTile(
                              title: Text(
                                item.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                'Estoque: ${quantity(item.quantity)} ${item.unit}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Adicionar ao carrinho',
                                onPressed: _saving ? null : () => _edit(item),
                                icon: const Icon(Icons.add_shopping_cart),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _saving || _items!.isEmpty
                            ? null
                            : () async {
                                final item = await showDialog<PantryItem>(
                                  context: context,
                                  builder: (context) => SimpleDialog(
                                    title: const Text('Escolher produto'),
                                    children: [
                                      for (final item in _items!)
                                        SimpleDialogOption(
                                          onPressed: () =>
                                              Navigator.pop(context, item),
                                          child: Text(item.name),
                                        ),
                                    ],
                                  ),
                                );
                                if (mounted && item != null) await _edit(item);
                              },
                        icon: const Icon(Icons.add),
                        label: const Text('Escolher produto da despensa'),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Cadastre novos produtos na despensa. O carrinho é um rascunho desta tela; as compras finalizadas ficam salvas no histórico.',
                      ),
                    ],
                  ),
      ),
    );
  }
}
