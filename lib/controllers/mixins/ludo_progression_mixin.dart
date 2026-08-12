import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../config/progression_config.dart';
import '../../models/ludo_models.dart';

mixin LudoProgressionMixin on ChangeNotifier {
  FirebaseFirestore get db;
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
      final snapshot = await db.collection('appConfig').doc('progression').get();
      if (snapshot.exists && snapshot.data() != null) {
        progressionConfig = ProgressionConfig.fromMap(snapshot.data()!);
      }
    } on FirebaseException catch (error) {
      if (kDebugMode) {
        print('Progression config fallback (${error.code}): ${error.message}');
      }
    } catch (error) {
      if (kDebugMode) print('Progression config fallback: $error');
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

    final humanPlayerCount = game.players
        .where((playerId) => !playerId.startsWith('bot_'))
        .length;

    return _claimProgression(
      matchId: matchId,
      data: _ProgressionMatchData(
        placement: game.placementFor(currentUser.uid),
        humanPlayerCount: humanPlayerCount,
        isSandbox: game.isTestModeActive,
      ),
    );
  }

  Future<ProgressionReward?> claimProgressionFromResult(
      String matchId,
      ) async {
    final currentUser = user;
    if (currentUser == null || matchId.isEmpty) return null;

    try {
      final snapshot = await db.collection('matchResults').doc(matchId).get();
      final map = snapshot.data();
      if (!snapshot.exists || map == null) return null;

      final participants = map['participantIds'] is Iterable
          ? (map['participantIds'] as Iterable).whereType<String>().toList()
          : <String>[];
      final ranking = map['ranking'] is Iterable
          ? (map['ranking'] as Iterable).whereType<String>().toList()
          : <String>[];
      if (!participants.contains(currentUser.uid)) return null;

      final placementIndex = ranking.indexOf(currentUser.uid);
      if (placementIndex < 0) return null;

      return await _claimProgression(
        matchId: matchId,
        data: _ProgressionMatchData(
          placement: placementIndex + 1,
          humanPlayerCount:
          (map['humanPlayerCount'] as num?)?.toInt() ?? participants.length,
          isSandbox: map['isTestModeActive'] == true,
        ),
      );
    } catch (error) {
      if (kDebugMode) print('Progression result lookup error: $error');
      return null;
    }
  }

  Future<ProgressionReward?> _claimProgression({
    required String matchId,
    required _ProgressionMatchData data,
  }) async {
    final currentUser = user;
    if (currentUser == null || data.placement <= 0) return null;

    final reward = progressionConfig.rewardForMatch(
      placement: data.placement,
      humanPlayerCount: data.humanPlayerCount,
      isSandbox: data.isSandbox,
    );

    final userReference = db.collection('users').doc(currentUser.uid);
    final claimReference = userReference.collection('rewardClaims').doc(matchId);

    try {
      final awarded = await db.runTransaction<bool>((transaction) async {
        final existingClaim = await transaction.get(claimReference);
        if (existingClaim.exists) return false;

        final profileSnapshot = await transaction.get(userReference);
        final profileExists = profileSnapshot.exists;

        transaction.set(
          userReference,
          {
            if (!profileExists) ...{
              'displayName': '',
              'activeGameId': '',
              'createdAt': FieldValue.serverTimestamp(),
            },
            'isAnonymous': currentUser.isAnonymous,
            'xp': FieldValue.increment(reward.xp),
            'coins': FieldValue.increment(reward.coins),
            'rewardedMatches': FieldValue.increment(1),
            if (data.placement == 1) 'rewardedWins': FieldValue.increment(1),
            if (data.placement <= 3)
              'rewardedPodiums': FieldValue.increment(1),
            'progressionConfigVersion': progressionConfig.version,
            'lastRewardAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        transaction.set(claimReference, {
          'matchId': matchId,
          'placement': data.placement,
          'humanPlayerCount': data.humanPlayerCount,
          'isSandbox': data.isSandbox,
          'xp': reward.xp,
          'coins': reward.coins,
          'configVersion': progressionConfig.version,
          'claimedAt': FieldValue.serverTimestamp(),
        });

        return true;
      });

      if (!awarded) return null;

      profileXp += reward.xp;
      profileCoins += reward.coins;
      rewardedMatches += 1;
      if (data.placement == 1) rewardedWins += 1;
      if (data.placement <= 3) rewardedPodiums += 1;
      notifyListeners();
      return reward;
    } catch (error) {
      if (kDebugMode) print('Progression claim error: $error');
      return null;
    }
  }
}

class _ProgressionMatchData {
  final int placement;
  final int humanPlayerCount;
  final bool isSandbox;

  const _ProgressionMatchData({
    required this.placement,
    required this.humanPlayerCount,
    required this.isSandbox,
  });
}
