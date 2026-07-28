import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

mixin LudoAuthMixin on ChangeNotifier {
  FirebaseAuth get auth;

  User? get user;
  set user(User? value);

  Future<void> initAuth() async {
    try {
      final existingUser = auth.currentUser;

      if (existingUser != null) {
        user = existingUser;
      } else {
        final result = await auth.signInAnonymously();
        user = result.user;
      }

      notifyListeners();
    } catch (error) {
      if (kDebugMode) {
        print('Auth error: $error');
      }
    }
  }
}