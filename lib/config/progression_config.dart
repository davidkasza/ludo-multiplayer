class ProgressionReward {
  final int xp;
  final int coins;

  const ProgressionReward({
    required this.xp,
    required this.coins,
  });

  static const zero = ProgressionReward(xp: 0, coins: 0);

  ProgressionReward operator +(ProgressionReward other) {
    return ProgressionReward(
      xp: xp + other.xp,
      coins: coins + other.coins,
    );
  }

  ProgressionReward scaled(int percent) {
    if (percent <= 0) return zero;
    if (percent >= 100) return this;

    return ProgressionReward(
      xp: (xp * percent / 100).round(),
      coins: (coins * percent / 100).round(),
    );
  }

  factory ProgressionReward.fromMap(
      Object? value, {
        ProgressionReward fallback = zero,
      }) {
    if (value is! Map) return fallback;
    final map = Map<String, dynamic>.from(value);

    return ProgressionReward(
      xp: (map['xp'] as num?)?.toInt() ?? fallback.xp,
      coins: (map['coins'] as num?)?.toInt() ?? fallback.coins,
    );
  }

  Map<String, dynamic> toMap() => {
    'xp': xp,
    'coins': coins,
  };
}

class LevelProgress {
  final int level;
  final int currentLevelXp;
  final int nextLevelXp;
  final int earnedWithinLevel;
  final int requiredWithinLevel;

  const LevelProgress({
    required this.level,
    required this.currentLevelXp,
    required this.nextLevelXp,
    required this.earnedWithinLevel,
    required this.requiredWithinLevel,
  });

  double get fraction {
    if (requiredWithinLevel <= 0) return 1;
    return (earnedWithinLevel / requiredWithinLevel).clamp(0, 1).toDouble();
  }

  bool get isMaxLevel => nextLevelXp <= currentLevelXp;
}

class ProgressionConfig {
  final int version;
  final bool enabled;
  final bool sandboxRewardsEnabled;
  final int aiOnlyMultiplierPercent;
  final ProgressionReward matchCompleted;
  final ProgressionReward humanOpponentBonus;
  final Map<int, ProgressionReward> placementRewards;
  final List<int> levelThresholds;

  const ProgressionConfig({
    required this.version,
    required this.enabled,
    required this.sandboxRewardsEnabled,
    required this.aiOnlyMultiplierPercent,
    required this.matchCompleted,
    required this.humanOpponentBonus,
    required this.placementRewards,
    required this.levelThresholds,
  });

  static const defaults = ProgressionConfig(
    version: 1,
    enabled: true,
    sandboxRewardsEnabled: false,
    aiOnlyMultiplierPercent: 25,
    matchCompleted: ProgressionReward(xp: 20, coins: 5),
    humanOpponentBonus: ProgressionReward(xp: 15, coins: 5),
    placementRewards: {
      1: ProgressionReward(xp: 30, coins: 10),
      2: ProgressionReward(xp: 20, coins: 6),
      3: ProgressionReward(xp: 10, coins: 3),
      4: ProgressionReward(xp: 5, coins: 1),
    },
    levelThresholds: [
      0,
      100,
      250,
      450,
      700,
      1000,
      1400,
      1900,
      2500,
      3200,
      4000,
      5000,
      6200,
      7600,
      9200,
      11000,
      13000,
      15500,
      18500,
      22000,
    ],
  );

  factory ProgressionConfig.fromMap(Map<String, dynamic> map) {
    final defaultConfig = defaults;
    final rewards = map['rewards'] is Map
        ? Map<String, dynamic>.from(map['rewards'])
        : const <String, dynamic>{};

    final rawPlacements = rewards['placements'];
    final placementRewards = <int, ProgressionReward>{
      ...defaultConfig.placementRewards,
    };

    if (rawPlacements is Map) {
      Map<String, dynamic>.from(rawPlacements).forEach((key, value) {
        final placement = int.tryParse(key);
        if (placement == null || placement < 1) return;
        placementRewards[placement] = ProgressionReward.fromMap(
          value,
          fallback: placementRewards[placement] ?? ProgressionReward.zero,
        );
      });
    }

    final rawThresholds = map['levelThresholds'];
    final thresholds = rawThresholds is List
        ? rawThresholds
        .whereType<num>()
        .map((value) => value.toInt())
        .where((value) => value >= 0)
        .toSet()
        .toList()
        : List<int>.from(defaultConfig.levelThresholds);

    thresholds.sort();
    if (thresholds.isEmpty || thresholds.first != 0) {
      thresholds.insert(0, 0);
    }

    return ProgressionConfig(
      version: (map['version'] as num?)?.toInt() ?? defaultConfig.version,
      enabled: map['enabled'] as bool? ?? defaultConfig.enabled,
      sandboxRewardsEnabled: map['sandboxRewardsEnabled'] as bool? ??
          defaultConfig.sandboxRewardsEnabled,
      aiOnlyMultiplierPercent:
      ((map['aiOnlyMultiplierPercent'] as num?)?.toInt() ??
          defaultConfig.aiOnlyMultiplierPercent)
          .clamp(0, 100)
          .toInt(),
      matchCompleted: ProgressionReward.fromMap(
        rewards['matchCompleted'],
        fallback: defaultConfig.matchCompleted,
      ),
      humanOpponentBonus: ProgressionReward.fromMap(
        rewards['humanOpponentBonus'],
        fallback: defaultConfig.humanOpponentBonus,
      ),
      placementRewards: placementRewards,
      levelThresholds: thresholds,
    );
  }

  ProgressionReward rewardForMatch({
    required int placement,
    required int humanPlayerCount,
    required bool isSandbox,
  }) {
    if (!enabled || (isSandbox && !sandboxRewardsEnabled)) {
      return ProgressionReward.zero;
    }

    var reward = matchCompleted +
        (placementRewards[placement] ?? ProgressionReward.zero);

    if (humanPlayerCount >= 2) {
      reward = reward + humanOpponentBonus;
    } else {
      reward = reward.scaled(aiOnlyMultiplierPercent);
    }

    return reward;
  }

  LevelProgress progressForXp(int xp) {
    final safeXp = xp < 0 ? 0 : xp;
    int index = 0;

    for (int i = 0; i < levelThresholds.length; i++) {
      if (safeXp >= levelThresholds[i]) {
        index = i;
      } else {
        break;
      }
    }

    final current = levelThresholds[index];
    final hasNext = index + 1 < levelThresholds.length;
    final next = hasNext ? levelThresholds[index + 1] : current;

    return LevelProgress(
      level: index + 1,
      currentLevelXp: current,
      nextLevelXp: next,
      earnedWithinLevel: safeXp - current,
      requiredWithinLevel: hasNext ? next - current : 0,
    );
  }
}