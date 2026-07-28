import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

mixin LudoAuthMixin on ChangeNotifier {
  FirebaseAuth get auth;

  User? get user;
  set user(User? value);

  StreamSubscription<User?>? _authSubscription;

  Future<void> initAuth() async {
    try {
      await _authSubscription?.cancel();
      _authSubscription = null;

      // On Android and iOS Firebase normally restores this automatically.
      User? restoredUser = auth.currentUser;

      // Wait for Firebase's initial authentication-state event as well.
      restoredUser ??= await auth.authStateChanges().first;

      // Only create a guest when Firebase really has no persisted user.
      if (restoredUser == null) {
        final result = await auth.signInAnonymously();
        restoredUser = result.user;
      }

      user = restoredUser;

      // Keep the controller synchronized after linking, signing in,
      // signing out, token refreshes, and user reloads.
      _authSubscription = auth.userChanges().listen(
            (firebaseUser) {
          user = firebaseUser;

          if (kDebugMode) {
            final providers = firebaseUser?.providerData
                .map((provider) => provider.providerId)
                .toList();

            print(
              'Auth state updated: '
                  'uid=${firebaseUser?.uid}, '
                  'anonymous=${firebaseUser?.isAnonymous}, '
                  'providers=$providers',
            );
          }

          notifyListeners();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (kDebugMode) {
            print('Auth state stream error: $error');
            print(stackTrace);
          }
        },
      );

      if (kDebugMode) {
        final providers = restoredUser?.providerData
            .map((provider) => provider.providerId)
            .toList();

        print(
          'Auth initialized: '
              'uid=${restoredUser?.uid}, '
              'anonymous=${restoredUser?.isAnonymous}, '
              'providers=$providers',
        );
      }

      notifyListeners();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        print('Auth initialization error: $error');
        print(stackTrace);
      }
    }
  }

  void disposeAuth() {
    final subscription = _authSubscription;
    _authSubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }
}