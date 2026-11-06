import 'package:flutter/material.dart';

import '../models/pantry_item.dart';
import '../services/local_recipe_ai_service.dart';

extension PantryAdvicePresentation on PantryAdviceKind {
  ({String title, String description, IconData icon})
  get presentation => switch (this) {
    PantryAdviceKind.waste => (
      title: 'Aproveitar antes de vencer',
      icon: Icons.event_available_outlined,
      description:
          'Receba sugestões para aproveitar os itens próximos do vencimento.',
    ),
    PantryAdviceKind.shopping => (
      title: 'Planejar compras',
      icon: Icons.shopping_cart_outlined,
      description:
          'Receba sugestões de prioridades e compras complementares com base '
          'na sua lista e no estoque disponível.',
    ),
    PantryAdviceKind.quickMeals => (
      title: 'Refeições em 15 minutos',
      icon: Icons.timer_outlined,
      description:
          'Veja o que dá para preparar em cerca de 15 minutos com o estoque.',
    ),
    PantryAdviceKind.leftovers => (
      title: 'Reaproveitar sobras',
      icon: Icons.soup_kitchen_outlined,
      description:
          'Informe o que sobrou para receber ideias de como usar em outro prato.',
    ),
    PantryAdviceKind.substitutes => (
      title: 'Substituir ingrediente',
      icon: Icons.swap_horiz,
      description:
          'Informe o que está faltando para buscar alternativas na despensa.',
    ),
    PantryAdviceKind.batchPrep => (
      title: 'Adiantar o preparo',
      icon: Icons.schedule,
      description:
          'Receba um plano para adiantar etapas de várias refeições de uma vez.',
    ),
    PantryAdviceKind.snacks => (
      title: 'Montar lanches',
      icon: Icons.lunch_dining_outlined,
      description:
          'Veja ideias de lanches fáceis de levar com o que você já tem.',
    ),
    PantryAdviceKind.organize => (
      title: 'Organizar a despensa',
      icon: Icons.inventory_2_outlined,
      description:
          'Veja como agrupar os itens e dar visibilidade aos que vencem primeiro.',
    ),
  };
}

class PantryAdviceScreen extends StatefulWidget {
  const PantryAdviceScreen({
    super.key,
    required this.items,
    required this.kind,
  });

  final List<PantryItem> items;
  final PantryAdviceKind kind;

  @override
  State<PantryAdviceScreen> createState() => _PantryAdviceScreenState();
}

class _PantryAdviceScreenState extends State<PantryAdviceScreen> {
  String _ingredient = '';
  bool _generating = false;
  String? _advice;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final advice = await LocalRecipeAiService.instance.generatePantryAdvice(
        widget.items,
        kind: widget.kind,
        ingredient: _ingredient,
      );
      if (mounted) setState(() => _advice = advice);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on UnsupportedError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Falha ao gerar sugestões. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentation = widget.kind.presentation;
    final isSubstitution = widget.kind == PantryAdviceKind.substitutes;
    return Scaffold(
      appBar: AppBar(title: Text(presentation.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(presentation.description),
          if (widget.kind.requiresIngredient) ...[
            const SizedBox(height: 16),
            TextField(
              enabled: !_generating,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: isSubstitution
                    ? 'O que está faltando?'
                    : 'O que sobrou?',
                hintText: isSubstitution
                    ? 'Ex.: creme de leite'
                    : 'Ex.: arroz cozido',
              ),
              onChanged: (value) => _ingredient = value,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _generating ? null : _generate,
            child: Text(_generating ? 'Gerando…' : 'Gerar com IA local'),
          ),
          if (_generating) const LinearProgressIndicator(),
          if (_error case final error?) ...[
            const SizedBox(height: 16),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_advice case final advice?) ...[
            const SizedBox(height: 16),
            SelectableText(advice),
          ],
        ],
      ),
    );
  }
}
