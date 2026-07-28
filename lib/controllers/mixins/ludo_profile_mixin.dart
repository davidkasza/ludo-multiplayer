import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/ludo_models.dart';
import '../../models/profile_models.dart';
import '../../config/progression_config.dart';

mixin LudoProfileMixin on ChangeNotifier {
  FirebaseFirestore get db;
  User? get user;

  String get profileName;
  set profileName(String value);

  bool get profileLoaded;
  set profileLoaded(bool value);

  String get activeGameId;
  set activeGameId(String value);

  LudoGame? get resumableGame;
  set resumableGame(LudoGame? value);

  bool get activeGameChecked;
  set activeGameChecked(bool value);

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

  Future<ProgressionReward?> claimProgressionFromResult(String matchId);

  Future<void> loadMyProfile() async {
    final currentUser = user;
    if (currentUser == null) return;

    try {
      final reference = db.collection('users').doc(currentUser.uid);
      final snapshot = await reference.get();

      if (snapshot.exists && snapshot.data() != null) {
        final profile = PlayerProfile.fromMap(snapshot.id, snapshot.data()!);
        profileName = profile.displayName;
        activeGameId = profile.activeGameId;
        profileXp = profile.xp;
        profileCoins = profile.coins;
        rewardedMatches = profile.rewardedMatches;
        rewardedWins = profile.rewardedWins;
        rewardedPodiums = profile.rewardedPodiums;

        await reference.set({
          'isAnonymous': currentUser.isAnonymous,
          'lastSeenAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await reference.set({
          'displayName': '',
          'activeGameId': '',
          'xp': 0,
          'coins': 0,
          'rewardedMatches': 0,
          'rewardedWins': 0,
          'rewardedPodiums': 0,
          'isAnonymous': currentUser.isAnonymous,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastSeenAt': FieldValue.serverTimestamp(),
        });
      }

      await refreshResumableGame();
    } catch (error) {
      if (kDebugMode) {
        print('Profile loading error: $error');
      }
    } finally {
      profileLoaded = true;
      activeGameChecked = true;
      notifyListeners();
    }
  }

  Future<void> updateProfileName(String value) async {
    final currentUser = user;
    if (currentUser == null) return;

    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 15) return;

    profileName = normalized;
    notifyListeners();

    try {
      await db.collection('users').doc(currentUser.uid).set({
        'displayName': normalized,
        'isAnonymous': currentUser.isAnonymous,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      if (kDebugMode) {
        print('Profile name update error: $error');
      }
    }
  }

  Future<void> setMyActiveGame(String roomId) async {
    final currentUser = user;
    final normalized = roomId.trim().toUpperCase();
    if (currentUser == null || normalized.isEmpty) return;

    activeGameId = normalized;
    activeGameChecked = true;
    notifyListeners();

    try {
      await db.collection('users').doc(currentUser.uid).set({
        'activeGameId': normalized,
        'activeGameUpdatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      if (kDebugMode) print('Active game save error: $error');
    }
  }

  Future<void> clearMyActiveGame({String? expectedGameId}) async {
    final currentUser = user;
    if (currentUser == null) return;

    if (expectedGameId != null &&
        activeGameId.isNotEmpty &&
        activeGameId != expectedGameId) {
      return;
    }

    activeGameId = '';
    resumableGame = null;
    activeGameChecked = true;
    notifyListeners();

    try {
      await db.collection('users').doc(currentUser.uid).set({
        'activeGameId': '',
        'activeGameUpdatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      if (kDebugMode) print('Active game clear error: $error');
    }
  }

  Future<void> refreshResumableGame() async {
    final currentUser = user;
    final roomId = activeGameId;

    activeGameChecked = false;
    notifyListeners();

    if (currentUser == null || roomId.isEmpty) {
      resumableGame = null;
      activeGameChecked = true;
      notifyListeners();
      return;
    }

    try {
      final snapshot = await db.collection('games').doc(roomId).get();
      if (!snapshot.exists || snapshot.data() == null) {
        await claimProgressionFromResult(roomId);
        await clearMyActiveGame(expectedGameId: roomId);
        return;
      }

      final candidate = LudoGame.fromMap(snapshot.data()!);
      if (candidate.status == 'finished' &&
          candidate.players.contains(currentUser.uid)) {
        await claimProgressionFromResult(roomId);
        await clearMyActiveGame(expectedGameId: roomId);
        return;
      }

      final isValid = candidate.players.contains(currentUser.uid) &&
          (candidate.status == 'waiting' || candidate.status == 'playing');

      if (!isValid) {
        await clearMyActiveGame(expectedGameId: roomId);
        return;
      }

      resumableGame = candidate;
    } catch (error) {
      if (kDebugMode) print('Active game lookup error: $error');
    } finally {
      activeGameChecked = true;
      notifyListeners();
    }
  }

  Future<List<MatchHistoryEntry>> loadMyMatchHistory({
    int limit = 30,
  }) async {
    final currentUser = user;
    if (currentUser == null) return const [];

    QuerySnapshot<Map<String, dynamic>> snapshot;

    try {
      snapshot = await db
          .collection('matchResults')
          .where('participantIds', arrayContains: currentUser.uid)
          .orderBy('finishedAt', descending: true)
          .limit(limit)
          .get();
    } on FirebaseException catch (error) {
      if (error.code != 'failed-precondition') rethrow;

      snapshot = await db
          .collection('matchResults')
          .where('participantIds', arrayContains: currentUser.uid)
          .limit(100)
          .get();
    }

    final entries = snapshot.docs.map(MatchHistoryEntry.fromDocument).toList();
    entries.sort((left, right) {
      final leftDate = left.finishedAt?.toDate();
      final rightDate = right.finishedAt?.toDate();

      if (leftDate == null && rightDate == null) return 0;
      if (leftDate == null) return 1;
      if (rightDate == null) return -1;
      return rightDate.compareTo(leftDate);
    });

    return entries.take(limit).toList();
  }
}