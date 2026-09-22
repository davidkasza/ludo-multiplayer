class RerollPricing {
  final List<int> costs;
  final int maxUsesPerMatch;

  const RerollPricing({required this.costs, required this.maxUsesPerMatch});

  factory RerollPricing.fromMap(Map<String, dynamic> map) {
    final rawCosts = map['costs'];
    final rawMaximum = map['maxUsesPerMatch'];
    if (rawCosts is! List || rawMaximum is! num) {
      throw const FormatException('Malformed Reroll pricing.');
    }
    final costs = <int>[];
    for (final value in rawCosts) {
      if (value is! num ||
          !value.isFinite ||
          value.toInt() != value ||
          value <= 0) {
        throw const FormatException('Malformed Reroll cost.');
      }
      costs.add(value.toInt());
    }
    if (!rawMaximum.isFinite) {
      throw const FormatException('Malformed Reroll limit.');
    }
    final maximum = rawMaximum.toInt();
    if (maximum != rawMaximum || maximum <= 0 || maximum != costs.length) {
      throw const FormatException('Malformed Reroll limit.');
    }
    return RerollPricing(
      costs: List.unmodifiable(costs),
      maxUsesPerMatch: maximum,
    );
  }

  int? costAfterUses(int uses) {
    if (uses < 0 || uses >= maxUsesPerMatch) return null;
    return costs[uses];
  }

  Map<String, dynamic> toMap() => {
    'costs': costs,
    'maxUsesPerMatch': maxUsesPerMatch,
  };
}

enum RerollAvailability {
  available,
  unavailableContext,
  aiControlled,
  rolling,
  requestPending,
  configurationUnavailable,
  limitReached,
  insufficientCoins,
}

/// Client-side presentation policy only. The callable backend repeats every
/// check and remains authoritative for eligibility, price, and coin balance.
RerollAvailability rerollAvailability({
  required bool isActionContext,
  required bool isHumanControlled,
  required bool isDiceRolling,
  required bool requestPending,
  required RerollPricing? pricing,
  required int uses,
  required int coins,
}) {
  if (!isActionContext) return RerollAvailability.unavailableContext;
  if (!isHumanControlled) return RerollAvailability.aiControlled;
  if (isDiceRolling) return RerollAvailability.rolling;
  if (requestPending) return RerollAvailability.requestPending;
  if (pricing == null) return RerollAvailability.configurationUnavailable;
  final cost = pricing.costAfterUses(uses);
  if (cost == null) return RerollAvailability.limitReached;
  if (coins < cost) return RerollAvailability.insufficientCoins;
  return RerollAvailability.available;
}
