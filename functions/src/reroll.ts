export interface RerollPricing {
  costs: readonly number[];
  maxUsesPerMatch: number;
}

const REROLL_COSTS = Object.freeze([50, 60, 70]);

/**
 * The sole default balance configuration. The backend copies it into each
 * match snapshot so clients can display the server-authored price without
 * maintaining their own price table or performing another read.
 */
export const DEFAULT_REROLL_PRICING: RerollPricing = Object.freeze({
  costs: REROLL_COSTS,
  maxUsesPerMatch: REROLL_COSTS.length,
});

function isValidPricing(value: unknown): value is {costs: number[]; maxUsesPerMatch: number} {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const pricing = value as Record<string, unknown>;
  if (!Array.isArray(pricing.costs) || pricing.costs.length === 0) return false;
  if (!Number.isSafeInteger(pricing.maxUsesPerMatch) || pricing.maxUsesPerMatch !== pricing.costs.length) {
    return false;
  }
  return pricing.costs.every((cost) => Number.isSafeInteger(cost) && cost > 0);
}

export function rerollPricingFromData(value: unknown): RerollPricing {
  if (!isValidPricing(value)) return DEFAULT_REROLL_PRICING;
  return Object.freeze({
    costs: Object.freeze([...value.costs]),
    maxUsesPerMatch: value.maxUsesPerMatch,
  });
}

export function rerollPricingForStorage(
  pricing: RerollPricing = DEFAULT_REROLL_PRICING,
): {costs: number[]; maxUsesPerMatch: number} {
  return {
    costs: [...pricing.costs],
    maxUsesPerMatch: pricing.maxUsesPerMatch,
  };
}

export function rerollCostAfterUses(pricing: RerollPricing, uses: number): number | null {
  if (!Number.isInteger(uses) || uses < 0 || uses >= pricing.maxUsesPerMatch) {
    return null;
  }
  return pricing.costs[uses] ?? null;
}

export function canAffordReroll(pricing: RerollPricing, uses: number, coins: number): boolean {
  const cost = rerollCostAfterUses(pricing, uses);
  return cost != null && Number.isSafeInteger(coins) && coins >= cost;
}
