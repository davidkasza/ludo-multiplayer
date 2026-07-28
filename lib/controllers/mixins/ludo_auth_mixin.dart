import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

mixin LudoAuthMixin on ChangeNotifier {
  FirebaseAuth get auth;

  User? get user;
  set user(User? value);

  Future<void> initAuth() async {
    try {
      // Wait until Firebase Auth has restored the saved local session.
      User? restoredUser = await auth.authStateChanges().first;

      // Create an anonymous account only when there really is no saved user.
      if (restoredUser == null) {
        final result = await auth.signInAnonymously();
        restoredUser = result.user;
      }

      user = restoredUser;

      if (kDebugMode) {
        final providers = user?.providerData
            .map((provider) => provider.providerId)
            .toList();

        print(
          'Auth initialized: '
              'uid=${user?.uid}, '
              'anonymous=${user?.isAnonymous}, '
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
}