import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/security/sandbox_access.dart';

void main() {
  test('Sandbox accepts only the verified owner account', () {
    expect(
      SandboxAccess.isAllowedIdentity(
        email: 'KASZADAVID1998@GMAIL.COM',
        emailVerified: true,
      ),
      isTrue,
    );
    expect(
      SandboxAccess.isAllowedIdentity(
        email: SandboxAccess.ownerEmail,
        emailVerified: false,
      ),
      isFalse,
    );
    expect(
      SandboxAccess.isAllowedIdentity(
        email: 'other@example.com',
        emailVerified: true,
      ),
      isFalse,
    );
    expect(
      SandboxAccess.isAllowedIdentity(email: null, emailVerified: true),
      isFalse,
    );
  });
}
