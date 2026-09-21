import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../models/ludo_models.dart';
import '../../game/dice_skin.dart';
import '../../services/gameplay_functions.dart';

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
  GameplayFunctions get gameplayFunctions;

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
      final transfer = await gameplayFunctions.prepareAccountTransfer();
      final transferId = transfer['transferId'] as String? ?? '';
      final transferSecret = transfer['secret'] as String? ?? '';
      if (transferId.isEmpty || transferSecret.isEmpty) {
        throw StateError('The secure account transfer could not be prepared.');
      }

      final signInResult = await auth.signInWithCredential(credential);
      final targetUser = signInResult.user;
      if (targetUser == null) {
        googleAuthMessage = 'Google returned no Firebase user.';
        return GoogleAccountResult.error;
      }

      user = targetUser;
      accountSwitched = true;
      _pendingGoogleCredential = null;

      final completedTransfer = await gameplayFunctions.completeAccountTransfer(
        transferId: transferId,
        secret: transferSecret,
      );

      await _reloadProfileAfterAuthChange();
      final copiedMatches =
          (completedTransfer['copiedMatches'] as num?)?.toInt() ?? 0;
      googleAuthMessage = copiedMatches == 0
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
