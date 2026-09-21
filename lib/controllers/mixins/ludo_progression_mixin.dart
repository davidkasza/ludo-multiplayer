import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../config/progression_config.dart';
import '../../models/ludo_models.dart';
import '../../services/gameplay_functions.dart';

mixin LudoProgressionMixin on ChangeNotifier {
  FirebaseFirestore get db;
  GameplayFunctions get gameplayFunctions;
  User? get user;

  ProgressionConfig get progressionConfig;
  set progressionConfig(ProgressionConfig value);

  bool get progressionConfigLoaded;
  set progressionConfigLoaded(bool value);

  int get profileXp;
  set profileXp(int value);

  int get profileCoins;
  set profileCoins(int value);

  int get rewardedMatches;
  set rewardedMatches(int value);

  int get rewardedWins;
  set rewardedWins(int value);

  int get rewardedPodiums;
  set rewardedPodiums(int value);

  LevelProgress get levelProgress => progressionConfig.progressForXp(profileXp);

  Future<void> loadProgressionConfig() async {
    progressionConfig = ProgressionConfig.defaults;
    try {
      final snapshot = await db
          .collection('appConfig')
          .doc('progression')
          .get();
      if (snapshot.exists && snapshot.data() != null) {
        progressionConfig = ProgressionConfig.fromMap(snapshot.data()!);
      }
    } catch (error) {
      if (kDebugMode) debugPrint('Progression config fallback: $error');
    } finally {
      progressionConfigLoaded = true;
      notifyListeners();
    }
  }

  Future<ProgressionReward?> claimProgressionForGame(
    String matchId,
    LudoGame game,
  ) async {
    final currentUser = user;
    if (currentUser == null ||
        matchId.isEmpty ||
        !game.players.contains(currentUser.uid) ||
        game.status != 'finished') {
      return null;
    }
    return _claimProgression(matchId);
  }

  Future<ProgressionReward?> claimProgressionFromResult(String matchId) {
    if (user == null || matchId.isEmpty) {
      return Future<ProgressionReward?>.value();
    }
    return _claimProgression(matchId);
  }

  Future<ProgressionReward?> _claimProgression(String matchId) async {
    try {
      final result = await gameplayFunctions.claimMatchReward(matchId);
      if (result['awarded'] != true) return null;
      final reward = ProgressionReward(
        xp: (result['xp'] as num?)?.toInt() ?? 0,
        coins: (result['coins'] as num?)?.toInt() ?? 0,
      );
      profileXp += reward.xp;
      profileCoins += reward.coins;
      rewardedMatches += 1;
      final placement = (result['placement'] as num?)?.toInt() ?? 0;
      if (placement == 1) rewardedWins += 1;
      if (placement >= 1 && placement <= 3) rewardedPodiums += 1;
      notifyListeners();
      return reward;
    } catch (error) {
      if (kDebugMode) debugPrint('Progression claim error: $error');
      return null;
    }
  }
}
