# Firebase architecture and cost notes

## Data placement

- Firestore `games/{roomCode}`: authoritative game snapshot, durable room
  metadata, turn phase/version, pieces, finish order, and the latest committed
  action descriptor used to replay an animation.
- Firestore `users`, `users/*/rewardClaims`, `matchResults`, and `appConfig`:
  durable profile, progression, history, and configuration data.
- Realtime Database `gamePresence/{room}/{uid}/sessions/{session}`: ephemeral
  session presence. Each session installs `onDisconnect().remove()`, so no
  periodic heartbeat is needed and closing one tab does not remove another
  tab's session.
- Realtime Database `gameChat/{room}/latest`: ephemeral quick chat. A temporary
  Firestore fallback preserves chat until RTDB is configured.

Animation completion is not authoritative. A roll or move is fully validated
and committed in one Firestore transaction. Its action ID and turn version make
automatic transaction retries idempotent; subsequent state/phase validation
prevents a user retry from applying the same logical turn twice. Applied action
descriptors can safely remain in the snapshot until the next action. Old
two-phase action descriptors are detected and cleared after a guarded recovery
transaction that verifies the descriptor key before changing anything.

## Operation audit before this change

Firestore bills a document delivered to each active listener as a read. With
`P` players watching the game document, each write to that document therefore
caused approximately `P` listener reads in addition to any transaction read.

| Activity | Previous Firestore operations |
| --- | --- |
| Waiting-room presence | One write per player every 15 seconds; every write redelivered the full game document to all players |
| Waiting-room lease | Host wrote the full game document every 30 seconds |
| Active-match presence | One write per player every 15 seconds |
| Dice roll | Two transactions: animation start and result; about 2 writes, 2 transaction reads, and `2P` listener reads |
| Piece movement | Two transactions: animation start and final state; about 2 writes, 2 transaction reads, and `2P` listener reads |
| Turn timers | Local countdown itself was free, but timeout/AI automation used extra lease transactions/writes |
| AI action/takeover | Typically an extra lease transaction and sometimes a release write per automated action |
| Quick chat | One main-game-document write and `P` listener reads per message |
| Matchmaking | Indexed query up to 20 reads; missing-index fallback up to 100 reads, followed by sequential candidate transactions |
| Reconnect/disconnect | Presence writes to the main game document; reconnect and takeover could add more transactions |

Consequently, an idle waiting room generated about **10 writes/20 listener
reads per minute for two players**, or **18 writes/72 listener reads per minute
for four players**. Using representative complete matches (about 100 rolls and
75 moves over 20 minutes for two players; 200 rolls and 150 moves over 40
minutes for four players), the previous implementation was approximately:

- Two-player match: **500–600 Firestore writes and 1,300–1,600 reads**.
- Four-player match: **1,300–1,500 Firestore writes and 5,800–6,500 reads**.

These are estimates, not Firebase invoices. They exclude variable chat volume,
profile/history screens, transaction contention retries, and failed/offline
listener behavior.

## Operation estimate after this change

- Presence: zero routine Firestore operations. RTDB uses a small set/remove per
  connection/session and streaming bandwidth, with no heartbeat.
- Waiting-room lease: no immediate heartbeat and at most one Firestore write
  every five minutes while the host remains in the room.
- Roll/move: one transaction read, one write, and one listener delivery per
  player. AI lease transactions have been removed. Recovery clients are
  staggered so a later client usually observes the winner's snapshot before it
  attempts the same timeout/AI action; rare slow-network contention can still
  add transaction reads, but not duplicate state changes.
- Chat: zero Firestore operations after RTDB is configured. If RTDB is not yet
  available, the compatibility fallback retains the previous Firestore cost.
- Matchmaking: the primary indexed query is capped at 5 candidates and the
  temporary missing-index fallback at 20.

For the same representative matches, including a small allowance for room,
profile, result, and progression writes:

- Two-player match: approximately **185 writes and 535 reads**.
- Four-player match: approximately **370 writes and 1,765 reads**.

The biggest savings come from removing Firestore presence heartbeats, halving
the writes per game action, removing automation-lease writes, and moving chat
off the game document. Four-player matches benefit most because each avoided
main-document write previously produced four listener reads.

## Manual Firebase Console / CLI work

No Firebase service, data, rule, index, or deployment was changed remotely by
this work. Before releasing the new client:

1. In Firebase Console, confirm the default Realtime Database exists in
   `europe-west1` at
   `ludo-app-569c2-default-rtdb.europe-west1.firebasedatabase.app`. Create only
   that default instance if it does not exist, and do not enable backups or
   other paid features unless separately reviewed.
2. Review `database.rules.json`, then deploy only Realtime Database rules with
   your normal controlled release process. Validate both rule files in the
   Firebase Emulator Suite first; the Firebase CLI/emulators were not installed
   in the local environment used for this change.
3. Review `firestore.rules` before deploying it. Existing production rules may
   contain protections not present in this formerly unversioned repository;
   merge them instead of overwriting them blindly.
4. Deploy `firestore.indexes.json` (or create its two composite indexes in the
   Console) and wait until they are built. The game has a bounded fallback while
   the matchmaking index is unavailable.
5. Consider enabling Firebase App Check for the shipped Android/web apps after
   testing enforcement metrics. App Check reduces scripted abuse, but it does
   not make client-computed game outcomes trustworthy.

The checked-in `firebase.json` points at these rule/index files for future
controlled deployments. Do not run a broad `firebase deploy` without reviewing
all configured targets.

## Remaining authority/security boundary

Firestore rules ensure that unauthenticated outsiders cannot write game data
and constrain room joining. The app now uses atomic validation and shared rules,
but participating clients are still untrusted and remain authoritative for dice
RNG, movement requests, AI choices, match-result creation, and progression
claims. A modified client can fabricate legal-looking state or rewards. App
Check helps with abuse but cannot fix that trust boundary.

Realtime Database rules can authenticate the session owner/sender, but cannot
consult Firestore room membership. Any authenticated user who guesses a room
code could read that room's ephemeral presence/chat or post chat as themselves.
Keeping room codes unguessable and enabling App Check limits casual abuse; hard
membership enforcement requires a server-created RTDB membership claim or
moving chat authorization behind the proposed server endpoint.

The smallest practical fully authoritative follow-up is a small set of callable
Cloud Functions (or one minimal Cloud Run service) for `roll`, `move`,
`timeout/AI`, and `claimReward`. Each endpoint should authenticate the caller,
load the room in a server transaction, run the same rule vectors, use server RNG
and time, and write the result/action ID. Firestore rules can then deny clients
from changing authoritative gameplay/reward fields. This needs a billing and
operations decision, so it was intentionally not enabled or deployed here.
