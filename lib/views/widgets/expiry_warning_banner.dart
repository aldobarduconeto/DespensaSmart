import 'package:flutter/material.dart';
import '../../models/pantry_item.dart';
import '../../services/app_settings_service.dart';
import '../../services/date_formatter.dart';
import 'liquid_glass.dart';

class ExpiryWarningBanner extends StatelessWidget {
  final List<PantryItem> expiringItems;
  final VoidCallback? onRecipes;
  const ExpiryWarningBanner({
    super.key,
    required this.expiringItems,
    this.onRecipes,
  });

  @override
  Widget build(BuildContext context) {
    if (expiringItems.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final displayedItems = expiringItems.take(3).toList();
    final remainingCount = expiringItems.length - displayedItems.length;
    final days = AppSettingsService.instance.expiryWarningDays;

    return LiquidGlassCard(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(18),
      borderRadius: 24,
      tint: scheme.tertiaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.tertiary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: scheme.tertiary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Confira a validade',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...displayedItems.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Text(
                '• ${item.name} ${item.isExpired() ? '(vencido)' : '(vence ${DateFormatter.format(item.expiryDate!)})'}',
                style: TextStyle(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (remainingCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '... e mais $remainingCount itens',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
          if (expiringItems.any((item) => !item.isExpired())) ...[
            const SizedBox(height: 12),
            Text(
              'Use primeiro os produtos que vencem nos próximos $days dias.',
              style: TextStyle(
                color: scheme.onTertiaryContainer.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
            if (onRecipes != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRecipes,
                icon: const Icon(Icons.restaurant_menu, size: 18),
                label: const Text('Ver receitas para aproveitar'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
