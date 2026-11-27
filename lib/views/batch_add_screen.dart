import 'package:flutter/material.dart';

import '../constants/categories.dart';
import '../data/pantry_database.dart';
import '../models/pantry_item.dart';
import '../services/date_formatter.dart';
import 'widgets/liquid_glass.dart';

class FoodPreset {
  const FoodPreset({
    required this.name,
    required this.category,
    required this.unit,
    required this.shelfLifeDays,
  });

  final String name;
  final String category;
  final String unit;
  final int shelfLifeDays;
}

class BatchItemDraft {
  BatchItemDraft({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
    this.expiryDate,
  });

  String name;
  double quantity;
  String unit;
  String category;
  DateTime? expiryDate;
}

class BatchAddScreen extends StatefulWidget {
  const BatchAddScreen({super.key});

  @override
  State<BatchAddScreen> createState() => _BatchAddScreenState();
}

class _BatchAddScreenState extends State<BatchAddScreen> {
  static const List<FoodPreset> _catalog = [
    // Grãos e Massas
    FoodPreset(name: 'Arroz', category: 'Grãos', unit: 'kg', shelfLifeDays: 365),
    FoodPreset(name: 'Feijão', category: 'Grãos', unit: 'kg', shelfLifeDays: 180),
    FoodPreset(name: 'Macarrão', category: 'Grãos', unit: 'pacote', shelfLifeDays: 365),
    FoodPreset(name: 'Farinha de Trigo', category: 'Grãos', unit: 'kg', shelfLifeDays: 180),
    FoodPreset(name: 'Fubá', category: 'Grãos', unit: 'kg', shelfLifeDays: 180),
    FoodPreset(name: 'Aveia', category: 'Grãos', unit: 'pacote', shelfLifeDays: 180),
    FoodPreset(name: 'Pão de Forma', category: 'Grãos', unit: 'pacote', shelfLifeDays: 10),
    FoodPreset(name: 'Pão Francês', category: 'Grãos', unit: 'unidade', shelfLifeDays: 2),

    // Laticínios e Ovos
    FoodPreset(name: 'Leite', category: 'Laticínios', unit: 'L', shelfLifeDays: 90),
    FoodPreset(name: 'Queijo Muçarela', category: 'Laticínios', unit: 'g', shelfLifeDays: 20),
    FoodPreset(name: 'Queijo Prato', category: 'Laticínios', unit: 'g', shelfLifeDays: 20),
    FoodPreset(name: 'Requeijão', category: 'Laticínios', unit: 'unidade', shelfLifeDays: 30),
    FoodPreset(name: 'Manteiga', category: 'Laticínios', unit: 'g', shelfLifeDays: 60),
    FoodPreset(name: 'Iogurte', category: 'Laticínios', unit: 'unidade', shelfLifeDays: 25),
    FoodPreset(name: 'Creme de Leite', category: 'Laticínios', unit: 'lata', shelfLifeDays: 180),
    FoodPreset(name: 'Leite Condensado', category: 'Laticínios', unit: 'lata', shelfLifeDays: 365),
    FoodPreset(name: 'Ovos', category: 'Outros', unit: 'unidade', shelfLifeDays: 21),

    // Carnes e Proteínas
    FoodPreset(name: 'Peito de Frango', category: 'Carnes', unit: 'kg', shelfLifeDays: 4),
    FoodPreset(name: 'Carne Moída', category: 'Carnes', unit: 'kg', shelfLifeDays: 3),
    FoodPreset(name: 'Bife Bovino', category: 'Carnes', unit: 'kg', shelfLifeDays: 3),
    FoodPreset(name: 'Bacon', category: 'Carnes', unit: 'g', shelfLifeDays: 30),
    FoodPreset(name: 'Linguiça', category: 'Carnes', unit: 'kg', shelfLifeDays: 15),
    FoodPreset(name: 'Presunto', category: 'Carnes', unit: 'g', shelfLifeDays: 10),
    FoodPreset(name: 'Hambúrguer', category: 'Congelados', unit: 'unidade', shelfLifeDays: 90),

    // Hortifrúti - Legumes e Verduras
    FoodPreset(name: 'Tomate', category: 'Legumes', unit: 'kg', shelfLifeDays: 7),
    FoodPreset(name: 'Cebola', category: 'Legumes', unit: 'kg', shelfLifeDays: 21),
    FoodPreset(name: 'Alho', category: 'Legumes', unit: 'unidade', shelfLifeDays: 45),
    FoodPreset(name: 'Batata', category: 'Legumes', unit: 'kg', shelfLifeDays: 20),
    FoodPreset(name: 'Cenoura', category: 'Legumes', unit: 'kg', shelfLifeDays: 14),
    FoodPreset(name: 'Alface', category: 'Legumes', unit: 'unidade', shelfLifeDays: 5),
    FoodPreset(name: 'Brócolis', category: 'Legumes', unit: 'unidade', shelfLifeDays: 6),
    FoodPreset(name: 'Pimentão', category: 'Legumes', unit: 'unidade', shelfLifeDays: 10),

    // Hortifrúti - Frutas
    FoodPreset(name: 'Banana', category: 'Frutas', unit: 'kg', shelfLifeDays: 6),
    FoodPreset(name: 'Maçã', category: 'Frutas', unit: 'kg', shelfLifeDays: 15),
    FoodPreset(name: 'Laranja', category: 'Frutas', unit: 'kg', shelfLifeDays: 14),
    FoodPreset(name: 'Limão', category: 'Frutas', unit: 'unidade', shelfLifeDays: 21),
    FoodPreset(name: 'Mamão', category: 'Frutas', unit: 'unidade', shelfLifeDays: 5),

    // Enlatados e Molhos
    FoodPreset(name: 'Molho de Tomate', category: 'Enlatados', unit: 'pacote', shelfLifeDays: 365),
    FoodPreset(name: 'Milho em Conserva', category: 'Enlatados', unit: 'lata', shelfLifeDays: 720),
    FoodPreset(name: 'Ervilha em Conserva', category: 'Enlatados', unit: 'lata', shelfLifeDays: 720),
    FoodPreset(name: 'Atum em Lata', category: 'Enlatados', unit: 'lata', shelfLifeDays: 720),
    FoodPreset(name: 'Sardinha em Lata', category: 'Enlatados', unit: 'lata', shelfLifeDays: 720),

    // Bebidas e Condimentos
    FoodPreset(name: 'Café', category: 'Bebidas', unit: 'g', shelfLifeDays: 180),
    FoodPreset(name: 'Açúcar', category: 'Outros', unit: 'kg', shelfLifeDays: 720),
    FoodPreset(name: 'Sal', category: 'Condimentos', unit: 'kg', shelfLifeDays: 720),
    FoodPreset(name: 'Azeite', category: 'Condimentos', unit: 'ml', shelfLifeDays: 365),
    FoodPreset(name: 'Óleo de Soja', category: 'Outros', unit: 'ml', shelfLifeDays: 365),
    FoodPreset(name: 'Vinagre', category: 'Condimentos', unit: 'ml', shelfLifeDays: 720),
    FoodPreset(name: 'Suco de Fruta', category: 'Bebidas', unit: 'L', shelfLifeDays: 90),
    FoodPreset(name: 'Refrigerante', category: 'Bebidas', unit: 'L', shelfLifeDays: 180),
  ];

  final _db = PantryDatabase.instance;
  final _drafts = <BatchItemDraft>[];
  final _inputController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  String _currentCategory = AppConstants.defaultCategory;
  String _currentUnit = AppConstants.defaultUnit;
  DateTime? _currentExpiry;
  bool _saving = false;

  @override
  void dispose() {
    _inputController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _onPresetSelected(FoodPreset preset) {
    setState(() {
      _inputController.text = preset.name;
      _currentCategory = preset.category;
      _currentUnit = preset.unit;
      _currentExpiry = DateTime.now().add(Duration(days: preset.shelfLifeDays));
    });
  }

  void _addCurrentDraft() {
    final name = _inputController.text.trim();
    if (name.isEmpty) return;

    final q = double.tryParse(_quantityController.text.trim().replaceAll(',', '.')) ?? 1.0;
    if (q <= 0) return;

    setState(() {
      _drafts.add(BatchItemDraft(
        name: name,
        quantity: q,
        unit: _currentUnit,
        category: _currentCategory,
        expiryDate: _currentExpiry,
      ));
      _inputController.clear();
      _quantityController.text = '1';
      _currentCategory = AppConstants.defaultCategory;
      _currentUnit = AppConstants.defaultUnit;
      _currentExpiry = null;
    });
  }

  Future<void> _pickDate(BatchItemDraft? draft) async {
    final now = DateTime.now();
    final current = draft?.expiryDate ?? _currentExpiry ?? now.add(const Duration(days: 14));
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() {
        if (draft != null) {
          draft.expiryDate = picked;
        } else {
          _currentExpiry = picked;
        }
      });
    }
  }

  Future<void> _saveAll() async {
    if (_drafts.isEmpty) return;
    setState(() => _saving = true);

    var added = 0;
    final errors = <String>[];

    for (final draft in _drafts) {
      try {
        await _db.add(PantryItem(
          name: draft.name,
          quantity: draft.quantity,
          unit: draft.unit,
          category: draft.category,
          expiryDate: draft.expiryDate,
        ));
        added++;
      } catch (e) {
        errors.add('${draft.name} (já existe ou inválido)');
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (errors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$added produtos cadastrados com sucesso na despensa!')),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$added adicionado(s). Alguns já existiam: ${errors.join(', ')}',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 700;

    return Scaffold(
      appBar: LiquidGlassAppBar(
        title: const Text('Entrada Rápida em Lote'),
        actions: [
          if (_drafts.isNotEmpty)
            FilledButton.icon(
              onPressed: _saving ? null : _saveAll,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text('Salvar (${_drafts.length})'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: LiquidGlassBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 800 : 640),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                // 1. ADD ROW CARD
                LiquidGlassCard(
                  prominent: true,
                  padding: const EdgeInsets.all(18),
                  borderRadius: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.bolt_rounded, color: scheme.primary, size: 26),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Adicionar Produto com Sugestão Automática',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Autocomplete name field
                      Autocomplete<FoodPreset>(
                        optionsBuilder: (textEditingValue) {
                          final query = textEditingValue.text.trim().toLowerCase();
                          if (query.isEmpty) return const [];
                          return _catalog.where((p) => p.name.toLowerCase().contains(query));
                        },
                        displayStringForOption: (option) => option.name,
                        onSelected: _onPresetSelected,
                        fieldViewBuilder: (ctx, controller, focusNode, onFieldSubmitted) {
                          _inputController.addListener(() {
                            if (controller.text != _inputController.text) {
                              controller.text = _inputController.text;
                            }
                          });
                          controller.addListener(() {
                            if (_inputController.text != controller.text) {
                              _inputController.text = controller.text;
                            }
                          });
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              labelText: 'Nome do alimento',
                              hintText: 'Ex.: Leite, Arroz, Maçã...',
                              prefixIcon: const Icon(Icons.fastfood_outlined),
                              border: const OutlineInputBorder(),
                              suffixIcon: controller.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded),
                                      onPressed: () {
                                        controller.clear();
                                        _inputController.clear();
                                        setState(() {});
                                      },
                                    )
                                  : null,
                            ),
                            onSubmitted: (_) => _addCurrentDraft(),
                          );
                        },
                      ),
                      const SizedBox(height: 12),

                      // Quantity, Unit, Category & Expiry row
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _quantityController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Qtd.',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 4,
                            child: DropdownButtonFormField<String>(
                              value: _currentUnit,
                              isDense: true,
                              decoration: const InputDecoration(
                                labelText: 'Unidade',
                                border: OutlineInputBorder(),
                              ),
                              items: AppConstants.units
                                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _currentUnit = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 5,
                            child: DropdownButtonFormField<String>(
                              value: _currentCategory,
                              isDense: true,
                              decoration: const InputDecoration(
                                labelText: 'Categoria',
                                border: OutlineInputBorder(),
                              ),
                              items: AppConstants.categories
                                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _currentCategory = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _pickDate(null),
                            icon: const Icon(Icons.calendar_today_outlined, size: 16),
                            label: Text(
                              _currentExpiry == null
                                  ? 'Definir validade'
                                  : 'Vence: ${DateFormatter.formatShort(_currentExpiry!)}',
                            ),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _addCurrentDraft,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Inserir na Lista'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 2. DRAFT ITEMS LIST
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Itens para Cadastrar (${_drafts.length})',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (_drafts.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _drafts.clear()),
                        child: const Text('Limpar lista'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_drafts.isEmpty)
                  LiquidGlassCard(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.playlist_add_rounded, size: 48, color: scheme.outline),
                          const SizedBox(height: 12),
                          const Text(
                            'Nenhum item adicionado à lista ainda.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Digite o nome de cada produto acima e toque em "Inserir na Lista". '
                            'Validades e categorias sugeridas são preenchidas automaticamente!',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  LiquidGlassCard(
                    padding: EdgeInsets.zero,
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _drafts.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
                      itemBuilder: (ctx, index) {
                        final draft = _drafts[index];
                        return ListTile(
                          title: Text(draft.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '${draft.quantity} ${draft.unit} • ${draft.category}'
                            '${draft.expiryDate != null ? ' • Vence: ${DateFormatter.formatShort(draft.expiryDate!)}' : ''}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            color: scheme.error,
                            onPressed: () => setState(() => _drafts.removeAt(index)),
                          ),
                        );
                      },
                    ),
                  ),

                if (_drafts.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _saveAll,
                      icon: _saving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        _saving
                            ? 'Salvando produtos...'
                            : 'Salvar Todos os ${_drafts.length} Itens na Despensa',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
