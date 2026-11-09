import 'package:flutter/material.dart';
import '../../models/pantry_item.dart';
import '../../services/app_settings_service.dart';
import '../../services/date_formatter.dart';
import 'liquid_glass.dart';

class PantryItemCard extends StatelessWidget {
  final PantryItem item;
  final VoidCallback onConsume, onEdit, onDelete, onToggleShoppingList;
  final VoidCallback? onRestock;

  const PantryItemCard({
    super.key,
    required this.item,
    required this.onConsume,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleShoppingList,
    this.onRestock,
  });

  IconData _categoryIcon(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('horti') ||
        lower.contains('fruta') ||
        lower.contains('legume') ||
        lower.contains('verdura')) {
      return Icons.eco_outlined;
    }
    if (lower.contains('latic') ||
        lower.contains('leite') ||
        lower.contains('queijo')) {
      return Icons.egg_alt_outlined;
    }
    if (lower.contains('carne') || lower.contains('prote')) {
      return Icons.set_meal_outlined;
    }
    if (lower.contains('bebida')) {
      return Icons.local_drink_outlined;
    }
    if (lower.contains('limpeza')) {
      return Icons.cleaning_services_outlined;
    }
    if (lower.contains('grão') ||
        lower.contains('mercearia') ||
        lower.contains('ereal')) {
      return Icons.grain_rounded;
    }
    return Icons.inventory_2_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppSettingsService.instance.compactCards;
    final scheme = Theme.of(context).colorScheme;
    final expired = item.isExpired();
    final soon = item.isExpiringSoon();
    final empty = item.quantity == 0;
    final tone = expired
        ? scheme.error
        : soon
            ? scheme.tertiary
            : scheme.primary;
    final quantity = item.quantity % 1 == 0
        ? '${item.quantity.toInt()}'
        : double.parse(item.quantity.toStringAsPrecision(6)).toString();

    return LiquidGlassCard(
      padding: EdgeInsets.all(compact ? 12 : 16),
      borderRadius: compact ? 20 : 24,
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 40 : 48,
                height: compact ? 40 : 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tone.withValues(alpha: 0.22),
                      tone.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(compact ? 13 : 16),
                  border: Border.all(color: tone.withValues(alpha: 0.30)),
                ),
                child: Icon(
                  empty
                      ? Icons.shopping_basket_outlined
                      : _categoryIcon(item.category),
                  color: tone,
                  size: compact ? 20 : 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.category,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opções do item',
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  } else if (value == 'restock' && onRestock != null) {
                    onRestock!();
                  } else if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Editar item'),
                    ),
                  ),
                  if (onRestock != null)
                    const PopupMenuItem(
                      value: 'restock',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.add_box_outlined),
                        title: Text('Repor estoque'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Excluir item'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: compact ? 10 : 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LiquidGlassPill(
                icon: empty
                    ? Icons.production_quantity_limits_rounded
                    : Icons.scale_outlined,
                label: empty ? 'Estoque esgotado' : '$quantity ${item.unit}',
                color: empty ? scheme.error : scheme.primary,
              ),
              if (item.expiryDate != null && !empty)
                LiquidGlassPill(
                  icon: expired
                      ? Icons.error_outline_rounded
                      : soon
                          ? Icons.schedule_rounded
                          : Icons.event_available_outlined,
                  label: expired
                      ? 'Validade vencida'
                      : soon
                          ? 'Vence em breve (${DateFormatter.format(item.expiryDate!)})'
                          : 'Vence ${DateFormatter.format(item.expiryDate!)}',
                  color: tone,
                ),
              if (empty)
                LiquidGlassPill(
                  icon: Icons.priority_high_rounded,
                  label: 'Reposição necessária',
                  color: scheme.error,
                ),
            ],
          ),
          SizedBox(height: compact ? 6 : 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: empty ? null : onConsume,
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                label: const Text('Consumir'),
              ),
              if (onRestock != null)
                TextButton.icon(
                  onPressed: onRestock,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Repor'),
                ),
              TextButton.icon(
                onPressed: onToggleShoppingList,
                icon: Icon(
                  item.inShoppingList
                      ? Icons.playlist_add_check_rounded
                      : Icons.add_shopping_cart_rounded,
                  size: 18,
                ),
                label: Text(
                  item.inShoppingList
                      ? 'Na lista de compras'
                      : 'Adicionar às compras',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
