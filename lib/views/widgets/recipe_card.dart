import '../../models/recipe.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'liquid_glass.dart';

class RecipeCard extends StatelessWidget {
  final Recipe recipe;
  const RecipeCard({super.key, required this.recipe});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = recipe.ingredients.isEmpty
        ? 0.0
        : recipe.matchingIngredients / recipe.ingredients.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LiquidGlassCard(
        borderRadius: 26,
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => RecipeDetails(recipe: recipe),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recipe.thumbnail.isNotEmpty)
              Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: recipe.thumbnail,
                    height: 185,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    memCacheWidth: 1000,
                    placeholder: (context, url) => const SizedBox(
                      height: 185,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => const SizedBox(
                      height: 90,
                      child: Center(child: Icon(Icons.restaurant, size: 40)),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: LiquidGlassCard(
                      blur: 14,
                      borderRadius: 999,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              size: 15, color: scheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            '${(ratio * 100).round()}% na despensa',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${recipe.matchingIngredients} de ${recipe.ingredients.length} ingredientes na sua despensa',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 7,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Ver ingredientes e preparo',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded,
                          size: 16, color: scheme.primary),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecipeDetails extends StatelessWidget {
  final Recipe recipe;
  const RecipeDetails({super.key, required this.recipe});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        builder: (_, controller) => LiquidGlassCard(
          borderRadius: 30,
          blur: 24,
          prominent: true,
          padding: EdgeInsets.zero,
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Text(
                recipe.name,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: LiquidGlassPill(
                  icon: Icons.kitchen_outlined,
                  label:
                      '${recipe.matchingIngredients} de ${recipe.ingredients.length} ingredientes disponíveis',
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Ingredientes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...recipe.ingredients.map(
                (ingredient) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.fiber_manual_record,
                          size: 10, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(ingredient)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Modo de preparo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                recipe.instructions.isEmpty
                    ? 'A API não forneceu instruções para esta receita.'
                    : recipe.instructions,
                style: const TextStyle(height: 1.5),
              ),
              if (recipe.sourceUrl.startsWith('http')) ...[
                const SizedBox(height: 16),
                SelectableText(
                  'Fonte: ${recipe.sourceUrl}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
