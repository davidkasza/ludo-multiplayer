import {deleteApp, initializeApp} from "firebase-admin/app";
import {getFirestore, QueryDocumentSnapshot} from "firebase-admin/firestore";
import {expect} from "chai";
import {HttpsError} from "firebase-functions/v2/https";

import {
  createInitialGameForTests,
  movePieceIntent,
  rollDiceIntent,
  sandboxTeleportIntent,
  startGameIntent,
} from "../src/game_service";
import {
  claimMatchRewardIntent,
  completeAccountTransferIntent,
  prepareAccountTransferIntent,
} from "../src/progression";

describe("authoritative gameplay service", () => {
  const app = initializeApp({projectId: "demo-ludora"}, "game-service-tests");
  const db = getFirestore(app);

  beforeEach(async () => {
    const snapshot = await db.collection("games").get();
    await Promise.all(snapshot.docs.map((document: QueryDocumentSnapshot) => document.ref.delete()));
    await db.collection("games").doc("ABCDE").set(createInitialGameForTests());
  });

  after(async () => deleteApp(app));

  it("rejects a non-participant even when intent fields are otherwise valid", async () => {
    try {
      await rollDiceIntent(db, {uid: "outsider"}, {
        roomCode: "ABCDE",
        expectedTurnVersion: 1,
        actionId: "outside_action_1",
      });
      expect.fail("Expected permission denied");
    } catch (error) {
      expect(error).to.be.instanceOf(HttpsError);
      expect((error as HttpsError).code).to.equal("permission-denied");
    }
  });

  it("does not accept a client-selected dice value outside owner Sandbox", async () => {
    try {
      await rollDiceIntent(db, {uid: "player-a"}, {
        roomCode: "ABCDE",
        expectedTurnVersion: 1,
        actionId: "forced_action_1",
        forcedValue: 6,
      });
      expect.fail("Expected permission denied");
    } catch (error) {
      expect((error as HttpsError).code).to.equal("permission-denied");
    }
  });

  it("applies one secure roll and treats a retry as idempotent", async () => {
    const intent = {
      roomCode: "ABCDE",
      expectedTurnVersion: 1,
      actionId: "secure_action_1",
    };
    const first = await rollDiceIntent(db, {uid: "player-a"}, intent);
    expect(first.applied).to.equal(true);
    expect(first.diceValue).to.be.within(1, 6);
    const retry = await rollDiceIntent(db, {uid: "player-a"}, intent);
    expect(retry.duplicate).to.equal(true);
    const snapshot = await db.collection("games").doc("ABCDE").get();
    expect(snapshot.get("turnVersion")).to.equal(2);
  });

  it("validates movement, applies capture, and awards the extra turn", async () => {
    await db.collection("games").doc("ABCDE").set(createInitialGameForTests({
      diceValue: 1,
      hasRolled: true,
      turnPhase: "waitingForMove",
      pieces: {
        "player-a": [
          {id: 1, pos: 0, inHome: false},
          {id: 2, pos: -1, inHome: false},
          {id: 3, pos: -1, inHome: false},
          {id: 4, pos: -1, inHome: false},
        ],
        "player-b": [
          {id: 1, pos: 27, inHome: false},
          {id: 2, pos: -1, inHome: false},
          {id: 3, pos: -1, inHome: false},
          {id: 4, pos: -1, inHome: false},
        ],
      },
    }));
    const result = await movePieceIntent(db, {uid: "player-a"}, {
      roomCode: "ABCDE",
      expectedTurnVersion: 1,
      actionId: "capture_action_1",
      pieceId: 1,
    });
    expect(result.didCapture).to.equal(true);
    expect(result.extraTurn).to.equal(true);
    const game = (await db.collection("games").doc("ABCDE").get()).data()!;
    expect(game.currentTurn).to.equal("player-a");
    expect(game.pieces["player-b"][0].pos).to.equal(-1);
    expect(game.activeMove.capturedPieces).to.have.length(1);
  });

  it("commits finish order, winner, result, and an idempotent server reward", async () => {
    await db.collection("games").doc("ABCDE").set(createInitialGameForTests({
      diceValue: 1,
      hasRolled: true,
      turnPhase: "waitingForMove",
      pieces: {
        "player-a": [1, 2, 3].map((id) => ({id, pos: 5, inHome: true})).concat([
          {id: 4, pos: 4, inHome: true},
        ]),
        "player-b": [1, 2, 3, 4].map((id) => ({id, pos: -1, inHome: false})),
      },
    }));
    const result = await movePieceIntent(db, {uid: "player-a"}, {
      roomCode: "ABCDE",
      expectedTurnVersion: 1,
      actionId: "finish_action_1",
      pieceId: 4,
    });
    expect(result.matchFinished).to.equal(true);
    const game = (await db.collection("games").doc("ABCDE").get()).data()!;
    expect(game.status).to.equal("finished");
    expect(game.winnerUid).to.equal("player-a");
    expect(game.finishOrder).to.deep.equal(["player-a", "player-b"]);
    expect((await db.collection("matchResults").doc("ABCDE").get()).get("authorityVersion")).to.equal(1);

    const first = await claimMatchRewardIntent(db, "player-a", {matchId: "ABCDE"});
    const duplicate = await claimMatchRewardIntent(db, "player-a", {matchId: "ABCDE"});
    expect(first.awarded).to.equal(true);
    expect(duplicate.duplicate).to.equal(true);
    const profile = (await db.collection("users").doc("player-a").get()).data()!;
    expect(profile.rewardedMatches).to.equal(1);
  });

  it("does not mint rewards from a legacy client-authored result", async () => {
    await db.collection("matchResults").doc("LEGACY").set({
      participantIds: ["player-a", "player-b"],
      ranking: ["player-a", "player-b"],
      humanPlayerCount: 2,
      isTestModeActive: false,
    });
    try {
      await claimMatchRewardIntent(db, "player-a", {matchId: "LEGACY"});
      expect.fail("Expected the legacy result to be rejected");
    } catch (error) {
      expect((error as HttpsError).code).to.equal("failed-precondition");
    }
  });

  it("permits Sandbox teleport only for the verified owner identity", async () => {
    await db.collection("games").doc("ABCDE").set(createInitialGameForTests({
      players: ["owner-uid", "bot_seat_2"],
      playerNames: {"owner-uid": "Owner", "bot_seat_2": "Computer"},
      playerSeats: {"owner-uid": 0, "bot_seat_2": 2},
      pieces: {
        "owner-uid": [1, 2, 3, 4].map((id) => ({id, pos: 49, inHome: false})),
        "bot_seat_2": [1, 2, 3, 4].map((id) => ({id, pos: 49, inHome: false})),
      },
      currentTurn: "owner-uid",
      isTestModeActive: true,
    }));
    const result = await sandboxTeleportIntent(db, {
      uid: "owner-uid",
      token: {email: "kaszadavid1998@gmail.com", email_verified: true},
    }, {
      roomCode: "ABCDE",
      expectedTurnVersion: 1,
      actionId: "sandbox_action_1",
      pieceId: 1,
      pos: 3,
      inHome: true,
    });
    expect(result.applied).to.equal(true);
    const game = (await db.collection("games").doc("ABCDE").get()).data()!;
    expect(game.pieces["owner-uid"][0]).to.deep.include({pos: 3, inHome: true});
  });

  it("starts a complete room in canonical seat order with a server deadline", async () => {
    await db.collection("games").doc("ABCDE").set(createInitialGameForTests({
      players: ["player-b", "player-a"],
      currentTurn: "player-b",
      status: "waiting",
      hostUid: "player-a",
      maxPlayers: 2,
      turnVersion: 0,
      playerNames: {"player-a": "A", "player-b": "B"},
      playerSeats: {"player-a": 0, "player-b": 2},
    }));
    const result = await startGameIntent(db, {uid: "player-a"}, {
      roomCode: "ABCDE",
      expectedTurnVersion: 0,
      actionId: "start_action_1",
    });
    expect(result.applied).to.equal(true);
    const game = (await db.collection("games").doc("ABCDE").get()).data()!;
    expect(game.players).to.deep.equal(["player-a", "player-b"]);
    expect(game.currentTurn).to.equal("player-a");
    expect(game.turnDurationSeconds).to.equal(30);
    expect(game.turnDeadlineAt.toMillis()).to.be.greaterThan(game.turnStartedAt.toMillis());
  });

  it("cannot merge the same source progression twice through separate transfer tickets", async () => {
    await db.collection("users").doc("repeat-source").set({
      displayName: "Guest",
      xp: 80,
      coins: 30,
      rewardedMatches: 2,
      rewardedWins: 1,
      rewardedPodiums: 1,
    });
    const firstTicket = await prepareAccountTransferIntent(db, "repeat-source");
    const secondTicket = await prepareAccountTransferIntent(db, "repeat-source");
    await completeAccountTransferIntent(db, "repeat-target", firstTicket);
    await completeAccountTransferIntent(db, "repeat-target", secondTicket);
    const target = (await db.collection("users").doc("repeat-target").get()).data()!;
    expect(target.xp).to.equal(80);
    expect(target.coins).to.equal(30);
    expect(target.mergedSourceUids).to.deep.equal(["repeat-source"]);
  });
});
