# Ludo Game

A Flutter/Firebase multiplayer Ludo game with two-to-four seats, human and AI
players, public matchmaking, private room codes, reconnect/takeover support,
quick chat, profiles, progression, and match history.

## Local checks

```sh
flutter pub get
flutter analyze
flutter test
```

Both deployment workflows run analysis and tests before building. Deployment is
still triggered only by the repository's existing `main`-branch workflows.

## Firebase setup

The app keeps durable profiles, room snapshots, progression, and match results
in Cloud Firestore. Ephemeral session presence and quick chat use Firebase
Realtime Database so they do not repeatedly invalidate the full game snapshot.

Before using multiplayer, follow
[`docs/firebase_architecture.md`](docs/firebase_architecture.md). In particular,
enable the project's default Realtime Database instance and review/deploy the
checked-in Firestore/Realtime Database rules and Firestore indexes. Nothing in
this repository change deploys or enables a Firebase service automatically.
