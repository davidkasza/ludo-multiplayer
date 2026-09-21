# Server-authoritative gameplay

Authoritative game actions are handled by Firebase Cloud Functions (2nd generation) in `europe-west1`. The Flutter client sends action intent and an expected turn version; it does not send dice values, destinations, captures, winners, turn results, XP, or coin rewards.

## Deployment order

This repository does not automatically deploy the new functions or rules. A coordinated release is required because older clients write gameplay state directly and will be rejected by the hardened Firestore rules.

1. Use a Firebase project on the Blaze plan. Second-generation functions require billing, although the functions are configured with zero minimum instances and conservative limits.
2. From `functions/`, run `npm ci`, `npm run lint`, `npm test`, and `npm run test:emulator` with JDK 21 or newer available for the Firestore emulator.
3. Begin a maintenance window that prevents legacy clients from starting new matches.
4. Deploy the callable functions first: `firebase deploy --only functions`.
5. Immediately deploy `firestore.rules`: `firebase deploy --only firestore:rules`.
6. Release the updated Android/web client that calls the functions in `europe-west1`, and make the update mandatory before gameplay.
7. Monitor callable errors, latency, Firestore transaction contention, and billing during rollout.

Do not leave a rollout window in which the new function/result schema is public while the old client-writable rules remain active. Old clients cannot play after the hardened rules are deployed, so a maintenance window and mandatory client update are required.

## App Check

The callables declare App Check options but enforcement is currently disabled. Before enabling enforcement, configure and validate the appropriate App Check providers for every supported platform, monitor valid/invalid request metrics, and then change the callable option deliberately. Authentication, room membership, phase, turn owner, and version checks are enforced independently of App Check.

## Sandbox authorization

Sandbox access requires Firebase Authentication with the verified email `kaszadavid1998@gmail.com`. The restriction is enforced in the Flutter UI, callable functions, room-start validation, and Firestore rules. No password, token, or credential is stored in this repository.

No stable Firebase UID for the owner account was present in repository configuration. A verified email check is therefore used. For stronger long-term administration, set an owner/admin custom claim from a trusted administrative environment and migrate the checks to that claim or to the account's immutable UID.

## Trust boundary

The server now owns dice generation, move validation, captures, turn transitions, finishing, match results, timeout/AI actions, and reward claims. New match results carry `authorityVersion: 1`; reward claims reject older client-authored result documents. Legacy match history remains readable, and rewards already recorded on a profile remain intact, but an unclaimed legacy result cannot mint a new reward after this migration. Waiting-room membership and permitted lobby settings remain client-writable under narrow Firestore rules. Presence and quick chat remain in Realtime Database and are not authoritative for gameplay.

The Dart rules implementation remains useful for UI previews and highlights, but the TypeScript rules module is authoritative. Shared fixtures exercise both implementations to reduce drift.

## Cost model

Each roll or move normally invokes one callable and performs one game-document read plus one game-document write in its Firestore transaction. A final move additionally writes one match-result document. A first reward claim reads the claim, match result, progression configuration, and profile, then writes the profile and immutable claim; retries read only the existing claim. No polling, scheduled function, per-animation write, or warm minimum instance is configured.
