import 'package:flutter/material.dart';

import '../../models/pantry_item.dart';
import 'liquid_glass.dart';

class PantryOverview extends StatelessWidget {
  final List<PantryItem> items;
  final VoidCallback onTapStocked;
  final VoidCallback onTapAgenda;
  final VoidCallback onTapShopping;

  const PantryOverview({
    super.key,
    required this.items,
    required this.onTapStocked,
    required this.onTapAgenda,
    required this.onTapShopping,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = [
      (
        icon: Icons.inventory_2_outlined,
        label: 'Em estoque',
        count: items.where((item) => item.quantity > 0).length,
        onTap: onTapStocked,
      ),
      (
        icon: Icons.calendar_today_outlined,
        label: 'Validade',
        count: items
            .where((item) => item.quantity > 0 && item.expiryDate != null)
            .length,
        onTap: onTapAgenda,
      ),
      (
        icon: Icons.shopping_bag_outlined,
        label: 'Compras',
        count: items.where((item) => item.inShoppingList).length,
        onTap: onTapShopping,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sua despensa',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: 16),
        LiquidGlassCard(
          borderRadius: 24,
          padding: const EdgeInsets.all(4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final metric in metrics)
                Expanded(
                  child: InkWell(
                    onTap: metric.onTap,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 12,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            metric.icon,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${metric.count}',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            metric.label,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
