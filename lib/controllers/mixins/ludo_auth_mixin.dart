import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

mixin LudoAuthMixin on ChangeNotifier {
  FirebaseAuth get auth;

  User? get user;
  set user(User? value);

  Future<void> initAuth() async {
    try {
      final res = await auth.signInAnonymously();
      user = res.user;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print("Auth error: $e");
      }
    }
  }
}