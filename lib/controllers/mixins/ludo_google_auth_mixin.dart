import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../models/ludo_models.dart';
import '../../game/dice_skin.dart';

/// Outcomes intentionally remain UI-agnostic so profile screens can decide
/// whether to show a snackbar, a confirmation dialog, or nothing at all.
enum GoogleAccountResult {
  linked,
  signedIn,
  signedOut,
  conflict,
  cancelled,
  activeGameBlocked,
  error,
}

mixin LudoGoogleAuthMixin on ChangeNotifier {
  FirebaseAuth get auth;
  FirebaseFirestore get db;

  User? get user;
  set user(User? value);

  String get activeGameId;
  set activeGameId(String value);

  LudoGame? get resumableGame;
  set resumableGame(LudoGame? value);

  String get profileName;
  set profileName(String value);

  String get preferredDiceSkinId;
  set preferredDiceSkinId(String value);

  bool get profileLoaded;
  set profileLoaded(bool value);

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

  Future<void> loadMyProfile();

  bool googleAuthBusy = false;
  String googleAuthMessage = '';
  AuthCredential? _pendingGoogleCredential;
  bool _googleSignInInitialized = false;

  bool get isGoogleLinked {
    return user?.providerData.any(
          (provider) => provider.providerId == 'google.com',
        ) ==
        true;
  }

  String get googleEmail {
    final currentUser = user;
    if (currentUser == null) return '';

    for (final provider in currentUser.providerData) {
      if (provider.providerId == 'google.com') {
        return provider.email ?? currentUser.email ?? '';
      }
    }

    return currentUser.email ?? '';
  }

  bool get hasPendingGoogleConflict => _pendingGoogleCredential != null;

  Future<void> initializeGoogleAuth() async {
    if (kIsWeb || _googleSignInInitialized) return;

    await GoogleSignIn.instance.initialize();
    _googleSignInInitialized = true;
  }

  Future<GoogleAccountResult> connectGoogleAccount() async {
    if (googleAuthBusy) return GoogleAccountResult.error;
    if (isGoogleLinked) return GoogleAccountResult.linked;

    googleAuthBusy = true;
    googleAuthMessage = '';
    _pendingGoogleCredential = null;
    notifyListeners();

    try {
      final currentUser = auth.currentUser;
      if (currentUser == null) {
        googleAuthMessage = 'No Firebase user is currently available.';
        return GoogleAccountResult.error;
      }

      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        final result = await currentUser.linkWithPopup(provider);
        await _finishLinkedAccount(result.user);
        return GoogleAccountResult.linked;
      }

      final credential = await _createNativeGoogleCredential();
      if (credential == null) return GoogleAccountResult.cancelled;

      try {
        final result = await currentUser.linkWithCredential(credential);
        await _finishLinkedAccount(result.user);
        return GoogleAccountResult.linked;
      } on FirebaseAuthException catch (error) {
        if (error.code == 'credential-already-in-use' ||
            error.code == 'email-already-in-use' ||
            error.code == 'account-exists-with-different-credential') {
          _pendingGoogleCredential = error.credential ?? credential;
          googleAuthMessage =
              'This Google account already has Ludora progress.';
          return GoogleAccountResult.conflict;
        }
        rethrow;
      }
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return GoogleAccountResult.cancelled;
      }
      googleAuthMessage = error.description ?? 'Google Sign-In failed.';
      if (kDebugMode) print('Google Sign-In error: $error');
      return GoogleAccountResult.error;
    } on FirebaseAuthException catch (error) {
      googleAuthMessage = _friendlyFirebaseAuthError(error);
      if (kDebugMode) print('Google account link error: $error');
      return GoogleAccountResult.error;
    } catch (error) {
      googleAuthMessage = 'Google account connection failed.';
      if (kDebugMode) print('Google account link error: $error');
      return GoogleAccountResult.error;
    } finally {
      googleAuthBusy = false;
      notifyListeners();
    }
  }

  Future<GoogleAccountResult> mergeAndSignInWithExistingGoogle() async {
    if (googleAuthBusy) return GoogleAccountResult.error;
    final credential = _pendingGoogleCredential;
    final sourceUser = auth.currentUser;

    if (credential == null || sourceUser == null) {
      googleAuthMessage = 'The Google sign-in request has expired.';
      return GoogleAccountResult.error;
    }

    if (activeGameId.isNotEmpty) {
      googleAuthMessage =
          'Finish or forfeit the active match before switching accounts.';
      return GoogleAccountResult.activeGameBlocked;
    }

    googleAuthBusy = true;
    googleAuthMessage = '';
    notifyListeners();

    var accountSwitched = false;

    try {
      final sourceUid = sourceUser.uid;
      final sourceProfileSnapshot = await db
          .collection('users')
          .doc(sourceUid)
          .get();
      final sourceProfile = sourceProfileSnapshot.data() ?? <String, dynamic>{};

      final sourceHistorySnapshot = await db
          .collection('matchResults')
          .where('participantIds', arrayContains: sourceUid)
          .get();

      final historyCopies = sourceHistorySnapshot.docs
          .map(
            (document) => _StoredMatchResult(
              id: document.id,
              data: Map<String, dynamic>.from(document.data()),
            ),
          )
          .toList();

      final sourceRewardClaimsSnapshot = await db
          .collection('users')
          .doc(sourceUid)
          .collection('rewardClaims')
          .get();
      final rewardClaimCopies = sourceRewardClaimsSnapshot.docs
          .map(
            (document) => _StoredRewardClaim(
              id: document.id,
              data: Map<String, dynamic>.from(document.data()),
            ),
          )
          .toList();

      final signInResult = await auth.signInWithCredential(credential);
      final targetUser = signInResult.user;
      if (targetUser == null) {
        googleAuthMessage = 'Google returned no Firebase user.';
        return GoogleAccountResult.error;
      }

      user = targetUser;
      accountSwitched = true;
      _pendingGoogleCredential = null;

      await _mergeAnonymousProfile(
        sourceUid: sourceUid,
        sourceProfile: sourceProfile,
        targetUser: targetUser,
      );
      await _copyMatchHistory(
        sourceUid: sourceUid,
        targetUid: targetUser.uid,
        targetDisplayName: targetUser.displayName ?? '',
        matches: historyCopies,
      );
      await _copyRewardClaims(
        sourceUid: sourceUid,
        targetUid: targetUser.uid,
        claims: rewardClaimCopies,
      );

      await _reloadProfileAfterAuthChange();
      googleAuthMessage = historyCopies.isEmpty
          ? 'Signed in with Google.'
          : 'Google account connected and guest history merged.';
      return GoogleAccountResult.signedIn;
    } on FirebaseAuthException catch (error) {
      if (accountSwitched) {
        await _reloadProfileAfterAuthChange();
        googleAuthMessage =
            'Signed in with Google, but the guest merge was incomplete.';
      } else {
        googleAuthMessage = _friendlyFirebaseAuthError(error);
      }
      if (kDebugMode) print('Google merge sign-in error: $error');
      return GoogleAccountResult.error;
    } catch (error) {
      if (accountSwitched) {
        await _reloadProfileAfterAuthChange();
        googleAuthMessage =
            'Signed in with Google, but the guest merge was incomplete.';
      } else {
        googleAuthMessage = 'Could not merge the guest profile.';
      }
      if (kDebugMode) print('Google account merge error: $error');
      return GoogleAccountResult.error;
    } finally {
      googleAuthBusy = false;
      notifyListeners();
    }
  }

  Future<GoogleAccountResult> signOutToNewGuest() async {
    if (googleAuthBusy) return GoogleAccountResult.error;
    if (activeGameId.isNotEmpty) {
      googleAuthMessage =
          'Finish or forfeit the active match before signing out.';
      return GoogleAccountResult.activeGameBlocked;
    }

    googleAuthBusy = true;
    googleAuthMessage = '';
    notifyListeners();

    try {
      if (!kIsWeb) {
        try {
          await GoogleSignIn.instance.disconnect();
        } catch (_) {
          try {
            await GoogleSignIn.instance.signOut();
          } catch (_) {
            // Firebase sign-out below is the operation that actually matters.
          }
        }
      }

      await auth.signOut();
      final anonymousResult = await auth.signInAnonymously();
      user = anonymousResult.user;
      _pendingGoogleCredential = null;
      await _reloadProfileAfterAuthChange();
      googleAuthMessage = 'Signed out. A new guest profile is active.';
      return GoogleAccountResult.signedOut;
    } on FirebaseAuthException catch (error) {
      googleAuthMessage = _friendlyFirebaseAuthError(error);
      if (kDebugMode) print('Google sign-out error: $error');
      return GoogleAccountResult.error;
    } catch (error) {
      googleAuthMessage = 'Could not sign out.';
      if (kDebugMode) print('Google sign-out error: $error');
      return GoogleAccountResult.error;
    } finally {
      googleAuthBusy = false;
      notifyListeners();
    }
  }

  Future<AuthCredential?> _createNativeGoogleCredential() async {
    await initializeGoogleAuth();
    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleAuthentication = googleUser.authentication;
    final idToken = googleAuthentication.idToken;

    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'Google did not return an ID token.',
      );
    }

    return GoogleAuthProvider.credential(idToken: idToken);
  }

  Future<void> _finishLinkedAccount(User? linkedUser) async {
    if (linkedUser == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Linked account returned no Firebase user.',
      );
    }

    // Refresh providerData and the locally persisted Firebase user.
    await linkedUser.reload();

    final refreshedUser = auth.currentUser ?? linkedUser;
    user = refreshedUser;

    await db.collection('users').doc(refreshedUser.uid).set({
      'isAnonymous': refreshedUser.isAnonymous,
      'googleEmail': refreshedUser.email ?? '',
      'googleDisplayName': refreshedUser.displayName ?? '',
      'photoUrl': refreshedUser.photoURL ?? '',
      'authProviders': refreshedUser.providerData
          .map((provider) => provider.providerId)
          .toSet()
          .toList(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _reloadProfileAfterAuthChange();

    googleAuthMessage = 'Guest progress is now protected by Google.';

    if (kDebugMode) {
      print(
        'Google account linked: '
        'uid=${refreshedUser.uid}, '
        'anonymous=${refreshedUser.isAnonymous}, '
        'providers=${refreshedUser.providerData.map((p) => p.providerId).toList()}',
      );
    }
  }

  Future<void> _mergeAnonymousProfile({
    required String sourceUid,
    required Map<String, dynamic> sourceProfile,
    required User targetUser,
  }) async {
    final targetReference = db.collection('users').doc(targetUser.uid);

    await db.runTransaction((transaction) async {
      final targetSnapshot = await transaction.get(targetReference);
      final targetData = targetSnapshot.data() ?? <String, dynamic>{};
      final mergedSourceUids = List<String>.from(
        targetData['mergedSourceUids'] ?? const <String>[],
      );

      final alreadyMerged = mergedSourceUids.contains(sourceUid);
      if (!alreadyMerged) mergedSourceUids.add(sourceUid);

      final targetName = (targetData['displayName'] as String? ?? '').trim();
      final sourceName = (sourceProfile['displayName'] as String? ?? '').trim();
      final targetDiceSkin = DiceSkinResolver.normalizeId(
        targetData['diceSkinId'] is String
            ? targetData['diceSkinId'] as String
            : null,
      );
      final sourceDiceSkin = DiceSkinResolver.normalizeId(
        sourceProfile['diceSkinId'] is String
            ? sourceProfile['diceSkinId'] as String
            : null,
      );

      transaction.set(targetReference, {
        if (!targetSnapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
        'displayName': targetName.isNotEmpty
            ? targetName
            : sourceName.isNotEmpty
            ? sourceName
            : targetUser.displayName ?? '',
        'diceSkinId': targetData.containsKey('diceSkinId')
            ? targetDiceSkin
            : sourceDiceSkin,
        'activeGameId': targetData['activeGameId'] as String? ?? '',
        'isAnonymous': false,
        'googleEmail': targetUser.email ?? '',
        'googleDisplayName': targetUser.displayName ?? '',
        'photoUrl': targetUser.photoURL ?? '',
        'authProviders': targetUser.providerData
            .map((provider) => provider.providerId)
            .toSet()
            .toList(),
        'mergedSourceUids': mergedSourceUids,
        if (!alreadyMerged) ...{
          'xp': FieldValue.increment(
            (sourceProfile['xp'] as num?)?.toInt() ?? 0,
          ),
          'coins': FieldValue.increment(
            (sourceProfile['coins'] as num?)?.toInt() ?? 0,
          ),
          'rewardedMatches': FieldValue.increment(
            (sourceProfile['rewardedMatches'] as num?)?.toInt() ?? 0,
          ),
          'rewardedWins': FieldValue.increment(
            (sourceProfile['rewardedWins'] as num?)?.toInt() ?? 0,
          ),
          'rewardedPodiums': FieldValue.increment(
            (sourceProfile['rewardedPodiums'] as num?)?.toInt() ?? 0,
          ),
        },
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _copyMatchHistory({
    required String sourceUid,
    required String targetUid,
    required String targetDisplayName,
    required List<_StoredMatchResult> matches,
  }) async {
    if (matches.isEmpty || sourceUid == targetUid) return;

    for (int offset = 0; offset < matches.length; offset += 400) {
      final batch = db.batch();
      final chunk = matches.skip(offset).take(400);

      for (final match in chunk) {
        final data = Map<String, dynamic>.from(match.data);
        final participants = _replaceUidInList(
          List<String>.from(data['participantIds'] ?? const <String>[]),
          sourceUid,
          targetUid,
        );
        final ranking = _replaceUidInList(
          List<String>.from(data['ranking'] ?? const <String>[]),
          sourceUid,
          targetUid,
        );

        final playerNames = _replaceUidInMap(
          data['playerNames'],
          sourceUid,
          targetUid,
        );
        playerNames[targetUid] =
            playerNames[targetUid]?.toString().trim().isNotEmpty == true
            ? playerNames[targetUid]
            : targetDisplayName.isNotEmpty
            ? targetDisplayName
            : 'Player';

        final preferredColors = _replaceUidInMap(
          data['preferredColors'],
          sourceUid,
          targetUid,
        );
        final playerSeats = _replaceUidInMap(
          data['playerSeats'],
          sourceUid,
          targetUid,
        );

        final copyId = '${match.id}__merged__$sourceUid';
        final reference = db.collection('matchResults').doc(copyId);

        batch.set(reference, {
          ...data,
          'participantIds': participants,
          'ranking': ranking,
          'playerNames': playerNames,
          'preferredColors': preferredColors,
          'playerSeats': playerSeats,
          'originalMatchId': match.id,
          'mergedFromUid': sourceUid,
          'mergedIntoUid': targetUid,
          'mergedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();
    }
  }

  Future<void> _copyRewardClaims({
    required String sourceUid,
    required String targetUid,
    required List<_StoredRewardClaim> claims,
  }) async {
    if (claims.isEmpty || sourceUid == targetUid) return;

    final targetCollection = db
        .collection('users')
        .doc(targetUid)
        .collection('rewardClaims');
    final existingSnapshot = await targetCollection.get();
    final existingIds = existingSnapshot.docs.map((doc) => doc.id).toSet();

    final writes = <_PendingClaimWrite>[];
    for (final claim in claims) {
      final copyId = '${claim.id}__merged__$sourceUid';
      for (final targetId in <String>[claim.id, copyId]) {
        if (existingIds.add(targetId)) {
          writes.add(
            _PendingClaimWrite(
              id: targetId,
              data: {
                ...claim.data,
                'matchId': targetId,
                'originalMatchId': claim.id,
                'mergedFromUid': sourceUid,
                'mergedIntoUid': targetUid,
                'mergedAt': FieldValue.serverTimestamp(),
              },
            ),
          );
        }
      }
    }

    for (int offset = 0; offset < writes.length; offset += 400) {
      final batch = db.batch();
      for (final write in writes.skip(offset).take(400)) {
        batch.set(targetCollection.doc(write.id), write.data);
      }
      await batch.commit();
    }
  }

  List<String> _replaceUidInList(
    List<String> source,
    String oldUid,
    String newUid,
  ) {
    final result = <String>[];
    for (final value in source) {
      final replaced = value == oldUid ? newUid : value;
      if (!result.contains(replaced)) result.add(replaced);
    }
    return result;
  }

  Map<String, dynamic> _replaceUidInMap(
    Object? raw,
    String oldUid,
    String newUid,
  ) {
    final result = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};

    if (result.containsKey(oldUid)) {
      result.putIfAbsent(newUid, () => result[oldUid]);
      result.remove(oldUid);
    }

    return result;
  }

  Future<void> _reloadProfileAfterAuthChange() async {
    profileName = '';
    preferredDiceSkinId = DiceSkinResolver.classicId;
    activeGameId = '';
    resumableGame = null;
    profileXp = 0;
    profileCoins = 0;
    rewardedMatches = 0;
    rewardedWins = 0;
    rewardedPodiums = 0;
    profileLoaded = false;
    activeGameChecked = false;
    notifyListeners();
    await loadMyProfile();
  }

  String _friendlyFirebaseAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'operation-not-allowed':
        return 'Enable Google in Firebase Authentication first.';
      case 'network-request-failed':
        return 'Network error during Google Sign-In.';
      case 'invalid-credential':
        return 'Google returned an invalid credential.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'provider-already-linked':
        return 'Google is already linked to this profile.';
      default:
        return error.message ?? 'Google authentication failed.';
    }
  }
}

class _StoredMatchResult {
  final String id;
  final Map<String, dynamic> data;

  const _StoredMatchResult({required this.id, required this.data});
}

class _StoredRewardClaim {
  final String id;
  final Map<String, dynamic> data;

  const _StoredRewardClaim({required this.id, required this.data});
}

class _PendingClaimWrite {
  final String id;
  final Map<String, dynamic> data;

  const _PendingClaimWrite({required this.id, required this.data});
}
