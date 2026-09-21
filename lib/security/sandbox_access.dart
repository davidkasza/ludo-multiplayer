import 'package:firebase_auth/firebase_auth.dart';

class SandboxAccess {
  const SandboxAccess._();

  static const String ownerEmail = 'kaszadavid1998@gmail.com';

  static bool isAllowedUser(User? user) {
    if (user == null) return false;
    return isAllowedIdentity(
      email: user.email,
      emailVerified: user.emailVerified,
    );
  }

  static bool isAllowedIdentity({
    required String? email,
    required bool emailVerified,
  }) {
    if (!emailVerified) return false;
    return (email ?? '').trim().toLowerCase() == ownerEmail;
  }
}
