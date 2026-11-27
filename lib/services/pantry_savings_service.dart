import '../models/pantry_item.dart';
import '../models/purchase_line.dart';

class ImmediateSavingsOpportunity {
  const ImmediateSavingsOpportunity({
    required this.item,
    required this.estimatedLossCents,
    required this.daysUntilExpiry,
    required this.reason,
  });

  final PantryItem item;
  final int estimatedLossCents;
  final int daysUntilExpiry;
  final String reason;
}

class ProductPriceInsight {
  const ProductPriceInsight({
    required this.name,
    required this.unit,
    required this.lowestPriceCents,
    required this.highestPriceCents,
    required this.latestPriceCents,
    required this.purchaseCount,
    required this.totalDiscountsCents,
  });

  final String name;
  final String unit;
  final int lowestPriceCents;
  final int highestPriceCents;
  final int latestPriceCents;
  final int purchaseCount;
  final int totalDiscountsCents;

  int get maxSavingsPerUnitCents => highestPriceCents - lowestPriceCents;
  bool get hasDiscountHistory => totalDiscountsCents > 0;
}

class PantrySavingsSummary {
  const PantrySavingsSummary({
    required this.periodDays,
    required this.periodStartDate,
    required this.totalAccumulatedSavingsCents,
    required this.discountsEarnedCents,
    required this.avoidedWasteCents,
    required this.actualWasteCents,
    required this.valueAtRiskCents,
    required this.inventoryValueCents,
    required this.totalSpentCents,
    required this.stockUtilizationRate,
    required this.opportunities,
    required this.priceInsights,
    required this.projectedAnnualSavingsCents,
  });

  final int periodDays;
  final DateTime periodStartDate;
  final int totalAccumulatedSavingsCents;
  final int discountsEarnedCents;
  final int avoidedWasteCents;
  final int actualWasteCents;
  final int valueAtRiskCents;
  final int inventoryValueCents;
  final int totalSpentCents;
  final double stockUtilizationRate;
  final List<ImmediateSavingsOpportunity> opportunities;
  final List<ProductPriceInsight> priceInsights;
  final int projectedAnnualSavingsCents;

  Map<String, Object?> toAiData() => {
        'periodo_dias': periodDays,
        'total_economizado': money(totalAccumulatedSavingsCents / 100),
        'descontos_obtidos_em_compras': money(discountsEarnedCents / 100),
        'desperdicio_evitado': money(avoidedWasteCents / 100),
        'desperdicio_real_perdas': money(actualWasteCents / 100),
        'estoque_em_risco_vencimento': money(valueAtRiskCents / 100),
        'patrimonio_na_despensa': money(inventoryValueCents / 100),
        'total_gasto_compras': money(totalSpentCents / 100),
        'taxa_aproveitamento_estoque':
            '${(stockUtilizationRate * 100).toStringAsFixed(1)}%',
        'projecao_economia_anual': money(projectedAnnualSavingsCents / 100),
        'itens_em_risco': opportunities
            .take(10)
            .map((o) => {
                  'item': o.item.name,
                  'quantidade': '${quantity(o.item.quantity)} ${o.item.unit}',
                  'valor_risco': money(o.estimatedLossCents / 100),
                  'dias_para_vencer': o.daysUntilExpiry,
                })
            .toList(),
        'produtos_com_variacao_preco': priceInsights
            .where((p) => p.maxSavingsPerUnitCents > 0)
            .take(8)
            .map((p) => {
                  'produto': p.name,
                  'menor_preco': money(p.lowestPriceCents / 100),
                  'maior_preco': money(p.highestPriceCents / 100),
                  'diferenca_unitaria': money(p.maxSavingsPerUnitCents / 100),
                })
            .toList(),
      };
}

class PantrySavingsService {
  PantrySavingsService._();
  static final instance = PantrySavingsService._();

  // In-memory cache for fast reuse when inputs haven't changed
  int _lastCacheKey = 0;
  PantrySavingsSummary? _cachedSummary;

  PantrySavingsSummary calculateSavings({
    required List<PantryItem> pantryItems,
    required List<Map<String, dynamic>> rawEvents,
    int days = 30,
    int expiryWarningDays = 7,
  }) {
    // Generate simple fast cache key
    final cacheKey = Object.hash(pantryItems.length, rawEvents.length, days, expiryWarningDays);
    if (_cachedSummary != null && _lastCacheKey == cacheKey) {
      return _cachedSummary!;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isAllTime = days <= 0;
    final periodStart = isAllTime
        ? DateTime(2000, 1, 1)
        : today.subtract(Duration(days: days - 1));

    // Fast O(1) item map by lowercase name
    final pantryItemsByName = <String, PantryItem>{};
    for (final item in pantryItems) {
      pantryItemsByName[item.name.toLowerCase()] = item;
    }

    // Single-pass processing for events
    var totalDiscountsCents = 0;
    var totalSpentCents = 0;
    var avoidedWasteCents = 0;
    var actualWasteCents = 0;
    var periodPurchaseCount = 0;
    var periodConsumeCount = 0;

    final allTimePrices = <String, List<int>>{};
    final allTimeLatestPrice = <String, int>{};
    final allTimeDiscounts = <String, int>{};

    for (var i = 0; i < rawEvents.length; i++) {
      final event = rawEvents[i];
      final receipt = event['receipt'];
      final eventType = event['type'];
      final nameRaw = (event['name'] as String? ?? event['key'] as String? ?? '').trim();
      final nameLower = nameRaw.toLowerCase();

      // Track prices across all time for product baseline
      if (receipt is String && event['unitPriceCents'] is num && nameLower.isNotEmpty) {
        final price = (event['unitPriceCents'] as num).toInt();
        allTimePrices.putIfAbsent(nameLower, () => []).add(price);
        allTimeLatestPrice[nameLower] = price;
        final disc = (event['discountCents'] as num?)?.toInt() ?? 0;
        if (disc > 0) {
          allTimeDiscounts[nameLower] = (allTimeDiscounts[nameLower] ?? 0) + disc;
        }
      }

      // Check period filter
      final dateStr = event['date'] as String?;
      if (dateStr == null || dateStr.isEmpty) continue;
      final date = DateTime.tryParse(dateStr)?.toLocal();
      if (date == null || date.isBefore(periodStart) || date.isAfter(now)) continue;

      if (receipt is String) {
        periodPurchaseCount++;
        final amount = (event['amount'] as num?)?.toDouble() ?? 0.0;
        final unitPrice = (event['unitPriceCents'] as num?)?.toInt() ?? 0;
        final discount = (event['discountCents'] as num?)?.toInt() ?? 0;
        final gross = (amount * unitPrice).round();
        totalDiscountsCents += discount;
        totalSpentCents += (gross - discount);
      } else if (eventType == 'consume') {
        periodConsumeCount++;
        final amount = (event['amount'] as num?)?.toDouble() ?? 0.0;
        final unitPrice = allTimeLatestPrice[nameLower] ?? 1000;
        final isWaste = event['isWaste'] == true;
        if (isWaste) {
          actualWasteCents += (amount * unitPrice).round();
        } else {
          avoidedWasteCents += (amount * unitPrice).round();
        }
      }
    }

    // Current inventory estimated valuation & risk valuation
    var inventoryValueCents = 0;
    var valueAtRiskCents = 0;
    final opportunities = <ImmediateSavingsOpportunity>[];

    for (var i = 0; i < pantryItems.length; i++) {
      final item = pantryItems[i];
      if (item.quantity <= 0) continue;
      final nameKey = item.name.trim().toLowerCase();
      final unitPrice = allTimeLatestPrice[nameKey] ??
          (allTimePrices[nameKey]?.isNotEmpty == true
              ? allTimePrices[nameKey]!.last
              : 1000);

      final itemTotalValue = (item.quantity * unitPrice).round();
      inventoryValueCents += itemTotalValue;

      if (item.expiryDate != null) {
        final exp = item.expiryDate!;
        final daysUntil = DateTime(exp.year, exp.month, exp.day).difference(today).inDays;

        if (daysUntil < 0) {
          valueAtRiskCents += itemTotalValue;
          opportunities.add(ImmediateSavingsOpportunity(
            item: item,
            estimatedLossCents: itemTotalValue,
            daysUntilExpiry: daysUntil,
            reason: 'Item vencido há ${-daysUntil} dia(s). Evite novo desperdício.',
          ));
        } else if (daysUntil <= expiryWarningDays) {
          valueAtRiskCents += itemTotalValue;
          opportunities.add(ImmediateSavingsOpportunity(
            item: item,
            estimatedLossCents: itemTotalValue,
            daysUntilExpiry: daysUntil,
            reason: daysUntil == 0
                ? 'Vence hoje! Use em preparos imediatos.'
                : 'Vence em $daysUntil dia(s). Consuma para garantir o valor.',
          ));
        }
      }
    }

    // Stock utilization rate
    final totalTransactions = periodConsumeCount + periodPurchaseCount;
    final stockUtilizationRate = totalTransactions > 0
        ? (periodConsumeCount / totalTransactions).clamp(0.0, 1.0)
        : (inventoryValueCents > 0 ? 0.85 : 1.0);

    // Product price insights & bargain tracker (using fast map lookup)
    final priceInsights = <ProductPriceInsight>[];
    for (final entry in allTimePrices.entries) {
      final nameLower = entry.key;
      final prices = entry.value;
      if (prices.isEmpty) continue;
      prices.sort();
      final lowest = prices.first;
      final highest = prices.last;
      final latest = allTimeLatestPrice[nameLower] ?? lowest;
      final discounts = allTimeDiscounts[nameLower] ?? 0;

      final matchedItem = pantryItemsByName[nameLower];
      final originalName = matchedItem?.name ?? nameLower;
      final originalUnit = matchedItem?.unit ?? 'un';

      priceInsights.add(ProductPriceInsight(
        name: originalName,
        unit: originalUnit,
        lowestPriceCents: lowest,
        highestPriceCents: highest,
        latestPriceCents: latest,
        purchaseCount: prices.length,
        totalDiscountsCents: discounts,
      ));
    }

    priceInsights.sort((a, b) => b.totalDiscountsCents.compareTo(a.totalDiscountsCents));
    opportunities.sort((a, b) => a.daysUntilExpiry.compareTo(b.daysUntilExpiry));

    // Projected annual savings
    final effectiveDays = isAllTime ? 90 : days.clamp(7, 365);
    final dailyDiscount = totalDiscountsCents / effectiveDays;
    final dailyWasteAvoided = (avoidedWasteCents * 0.25) / effectiveDays;
    final projectedAnnualSavings = ((dailyDiscount + dailyWasteAvoided) * 365).round();
    final totalAccumulatedSavings = (totalDiscountsCents +
            (avoidedWasteCents > 0 ? (avoidedWasteCents * 0.2).round() : 0) -
            actualWasteCents)
        .clamp(0, 999999999);

    final result = PantrySavingsSummary(
      periodDays: days,
      periodStartDate: periodStart,
      totalAccumulatedSavingsCents: totalAccumulatedSavings,
      discountsEarnedCents: totalDiscountsCents,
      avoidedWasteCents: avoidedWasteCents,
      actualWasteCents: actualWasteCents,
      valueAtRiskCents: valueAtRiskCents,
      inventoryValueCents: inventoryValueCents,
      totalSpentCents: totalSpentCents,
      stockUtilizationRate: stockUtilizationRate,
      opportunities: opportunities,
      priceInsights: priceInsights,
      projectedAnnualSavingsCents: projectedAnnualSavings,
    );

    _cachedSummary = result;
    _lastCacheKey = cacheKey;
    return result;
  }
}
