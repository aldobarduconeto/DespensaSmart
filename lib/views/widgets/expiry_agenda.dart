import 'package:flutter/material.dart';

import '../../models/pantry_item.dart';
import '../../services/date_formatter.dart';
import 'liquid_glass.dart';

Future<PantryItem?> showExpiryAgenda(
  BuildContext context,
  List<PantryItem> items,
) {
  final scheduled =
      items
          .where((item) => item.quantity > 0 && item.expiryDate != null)
          .toList()
        ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
  final sections = <String, List<PantryItem>>{
    'Vencidos': [],
    'Vencem em breve': [],
    'Próximas validades': [],
  };
  for (final item in scheduled) {
    final section = item.isExpired()
        ? 'Vencidos'
        : item.isExpiringSoon()
        ? 'Vencem em breve'
        : 'Próximas validades';
    sections[section]!.add(item);
  }

  return showModalBottomSheet<PantryItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.85,
      child: LiquidGlassCard(
        prominent: true,
        borderRadius: 32,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              ListTile(
                title: Text(
                  'Agenda de validade',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                trailing: IconButton(
                  tooltip: 'Fechar agenda',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: scheduled.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Nenhum ingrediente em estoque tem validade cadastrada.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : CustomScrollView(
                        slivers: [
                          for (final section in sections.entries)
                            if (section.value.isNotEmpty) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    16,
                                    20,
                                    4,
                                  ),
                                  child: Text(
                                    section.key,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                              ),
                              SliverList.builder(
                                itemCount: section.value.length,
                                itemBuilder: (context, index) {
                                  final item = section.value[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    title: Text(item.name),
                                    subtitle: Text(
                                      DateFormatter.format(item.expiryDate!),
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.pop(context, item),
                                  );
                                },
                              ),
                            ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
