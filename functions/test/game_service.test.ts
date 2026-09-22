import {deleteApp, initializeApp} from "firebase-admin/app";
import {getFirestore, QueryDocumentSnapshot, Timestamp} from "firebase-admin/firestore";
import {expect} from "chai";
import {HttpsError} from "firebase-functions/v2/https";

import {
  createInitialGameForTests,
  movePieceIntent,
  passNoValidMoveIntent,
  processTurnTimeoutIntent,
  rollDiceIntent,
  sandboxTeleportIntent,
  startGameIntent,
  useRerollIntent,
} from "../src/game_service";
import {DEFAULT_REROLL_PRICING, rerollCostAfterUses} from "../src/reroll";
import {
  claimMatchRewardIntent,
  completeAccountTransferIntent,
  prepareAccountTransferIntent,
} from "../src/progression";

describe("authoritative gameplay service", () => {
  const app = initializeApp({projectId: "demo-ludora"}, "game-service-tests");
  const db = getFirestore(app);

  beforeEach(async () => {
    for (const collection of ["games", "users", "matchResults"]) {
      const snapshot = await db.collection(collection).get();
      await Promise.all(snapshot.docs.map((document: QueryDocumentSnapshot) => document.ref.delete()));
    }
    await db.collection("games").doc("ABCDE").set(createInitialGameForTests());
  });

  after(async () => deleteApp(app));

  async function seedRerollState({
    coins = 200,
    uses = 0,
    noValidMove = false,
    aiControlled = false,
  }: {
    coins?: number;
    uses?: number;
    noValidMove?: boolean;
    aiControlled?: boolean;
  } = {}): Promise<void> {
    await db.collection("users").doc("player-a").set({coins});
    await db.collection("games").doc("ABCDE").set(createInitialGameForTests({
      diceValue: 1,
      hasRolled: true,
      turnPhase: noValidMove ? "waitingForRerollDecision" : "waitingForMove",
      activeDiceRoll: {
        actionId: "initial_roll_1",
        turnVersion: 1,
        playerId: "player-a",
        startedAt: Date.now(),
        durationMs: 800,
        result: 1,
        stateApplied: true,
      },
      ...(noValidMove ? {} : {
        pieces: {
          "player-a": [
            {id: 1, pos: 0, inHome: false},
            {id: 2, pos: -1, inHome: false},
            {id: 3, pos: -1, inHome: false},
            {id: 4, pos: -1, inHome: false},
          ],
          "player-b": [1, 2, 3, 4].map((id) => ({id, pos: -1, inHome: false})),
        },
      }),
      rerollsUsed: uses > 0 ? {"player-a": uses} : {},
      aiControlledPlayers: aiControlled ? ["player-a"] : [],
      turnStartedAt: Timestamp.now(),
      turnDurationSeconds: 30,
    }));
  }

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

  it("charges 50, 60, and 70 coins, then rejects a fourth Reroll", async () => {
    await seedRerollState();
    let expectedVersion = 1;
    let expectedActionId = "initial_roll_1";
    const expectedBalances = [150, 90, 20];
    for (let index = 0; index < 3; index++) {
      const actionId = `reroll_action_${index + 1}`;
      const result = await useRerollIntent(db, {uid: "player-a"}, {
        roomCode: "ABCDE",
        expectedTurnVersion: expectedVersion,
        expectedActionId,
        actionId,
      }, () => index + 2);
      expect(result.chargedCoins).to.equal(rerollCostAfterUses(DEFAULT_REROLL_PRICING, index));
      expect(result.coinBalance).to.equal(expectedBalances[index]);
      expect(result.rerollsUsed).to.equal(index + 1);
      expectedVersion++;
      expectedActionId = actionId;
    }

    try {
      await useRerollIntent(db, {uid: "player-a"}, {
        roomCode: "ABCDE",
        expectedTurnVersion: expectedVersion,
        expectedActionId,
        actionId: "reroll_action_4",
      }, () => 6);
      expect.fail("Expected the fourth Reroll to be rejected");
    } catch (error) {
      expect((error as HttpsError).code).to.equal("failed-precondition");
    }
    expect((await db.collection("users").doc("player-a").get()).get("coins")).to.equal(20);
  });

  it("charges the same server-authored price published in the match snapshot", async () => {
    await seedRerollState({coins: 100});
    await db.collection("games").doc("ABCDE").update({
      rerollConfig: {costs: [41, 57], maxUsesPerMatch: 2},
    });
    const result = await useRerollIntent(db, {uid: "player-a"}, {
      roomCode: "ABCDE",
      expectedTurnVersion: 1,
      expectedActionId: "initial_roll_1",
      actionId: "configured_reroll_1",
    }, () => 2);
    expect(result.chargedCoins).to.equal(41);
    expect(result.coinBalance).to.equal(59);
    expect(result.nextRerollCost).to.equal(57);
    const game = (await db.collection("games").doc("ABCDE").get()).data()!;
    expect(game.rerollConfig).to.deep.equal({costs: [41, 57], maxUsesPerMatch: 2});
  });

  it("deduplicates a retried Reroll without charging twice", async () => {
    await seedRerollState({coins: 100});
    const intent = {
      roomCode: "ABCDE",
      expectedTurnVersion: 1,
      expectedActionId: "initial_roll_1",
      actionId: "reroll_retry_1",
    };
    const first = await useRerollIntent(db, {uid: "player-a"}, intent, () => 2);
    const retry = await useRerollIntent(db, {uid: "player-a"}, intent, () => 6);
    expect(first.coinBalance).to.equal(50);
    expect(retry.duplicate).to.equal(true);
    expect(retry.coinBalance).to.equal(50);
    expect((await db.collection("games").doc("ABCDE").get()).get("rerollsUsed.player-a")).to.equal(1);
  });

  it("rejects insufficient coins without changing room or profile state", async () => {
    await seedRerollState({coins: 49});
    try {
      await useRerollIntent(db, {uid: "player-a"}, {
        roomCode: "ABCDE",
        expectedTurnVersion: 1,
        expectedActionId: "initial_roll_1",
        actionId: "poor_reroll_1",
      }, () => 2);
      expect.fail("Expected insufficient coins");
    } catch (error) {
      expect((error as HttpsError).code).to.equal("resource-exhausted");
    }
    expect((await db.collection("users").doc("player-a").get()).get("coins")).to.equal(49);
    expect((await db.collection("games").doc("ABCDE").get()).get("turnVersion")).to.equal(1);
  });

  it("binds Reroll to its owner and exact authoritative roll", async () => {
    await seedRerollState();
    for (const attempt of [
      {caller: "player-b", version: 1, roll: "initial_roll_1", action: "other_user_1"},
      {caller: "player-a", version: 1, roll: "stale_roll_1", action: "stale_roll_try_1"},
      {caller: "player-a", version: 0, roll: "initial_roll_1", action: "stale_version_1"},
    ]) {
      try {
        await useRerollIntent(db, {uid: attempt.caller}, {
          roomCode: "ABCDE",
          expectedTurnVersion: attempt.version,
          expectedActionId: attempt.roll,
          actionId: attempt.action,
        }, () => 2);
        expect.fail("Expected stale or foreign Reroll to fail");
      } catch (error) {
        expect(["failed-precondition", "aborted"]).to.include((error as HttpsError).code);
      }
    }
    expect((await db.collection("users").doc("player-a").get()).get("coins")).to.equal(200);
  });

  it("does not let an AI-controlled player purchase Reroll", async () => {
    await seedRerollState({aiControlled: true});
    try {
      await useRerollIntent(db, {uid: "player-a"}, {
        roomCode: "ABCDE",
        expectedTurnVersion: 1,
        expectedActionId: "initial_roll_1",
        actionId: "ai_reroll_try_1",
      }, () => 2);
      expect.fail("Expected AI Reroll to fail");
    } catch (error) {
      expect((error as HttpsError).code).to.equal("failed-precondition");
    }
  });

  it("ignores forged client outcomes and uses the server dice generator", async () => {
    await seedRerollState();
    const result = await useRerollIntent(db, {uid: "player-a"}, {
      roomCode: "ABCDE",
      expectedTurnVersion: 1,
      expectedActionId: "initial_roll_1",
      actionId: "server_rng_1",
      diceValue: 6,
      price: 1,
      finalCoinBalance: 999999,
    }, () => 2);
    expect(result.diceValue).to.equal(2);
    expect(result.chargedCoins).to.equal(50);
    expect(result.coinBalance).to.equal(150);
  });

  it("supports Reroll with legal moves and with no legal moves", async () => {
    await seedRerollState();
    const originalDeadlineStart = (await db.collection("games").doc("ABCDE").get())
      .get("turnStartedAt").toMillis();
    await useRerollIntent(db, {uid: "player-a"}, {
      roomCode: "ABCDE",
      expectedTurnVersion: 1,
      expectedActionId: "initial_roll_1",
      actionId: "legal_reroll_1",
    }, () => 2);
    let game = (await db.collection("games").doc("ABCDE").get()).data()!;
    expect(game.turnPhase).to.equal("waitingForMove");
    expect(game.hasRolled).to.equal(true);
    expect(game.turnStartedAt.toMillis()).to.equal(originalDeadlineStart);

    await seedRerollState({noValidMove: true});
    await useRerollIntent(db, {uid: "player-a"}, {
      roomCode: "ABCDE",
      expectedTurnVersion: 1,
      expectedActionId: "initial_roll_1",
      actionId: "no_move_reroll_1",
    }, () => 1);
    game = (await db.collection("games").doc("ABCDE").get()).data()!;
    expect(game.turnPhase).to.equal("waitingForRerollDecision");
    expect(game.hasRolled).to.equal(true);
  });

  it("allows a no-move Continue without spending coins", async () => {
    await seedRerollState({noValidMove: true});
    await passNoValidMoveIntent(db, {uid: "player-a"}, {
      roomCode: "ABCDE",
      expectedTurnVersion: 1,
      expectedActionId: "initial_roll_1",
      actionId: "pass_no_move_1",
    });
    const game = (await db.collection("games").doc("ABCDE").get()).data()!;
    expect(game.currentTurn).to.equal("player-b");
    expect(game.hasRolled).to.equal(false);
    expect(game.rerollsUsed).to.deep.equal({});
    expect((await db.collection("users").doc("player-a").get()).get("coins")).to.equal(200);
  });

  it("times out a no-move decision without spending coins or a Reroll", async () => {
    await seedRerollState({noValidMove: true});
    await db.collection("games").doc("ABCDE").update({
      turnStartedAt: Timestamp.fromMillis(Date.now() - 31000),
    });
    await processTurnTimeoutIntent(db, {uid: "player-b"}, {
      roomCode: "ABCDE",
      expectedTurnVersion: 1,
      actionId: "timeout_pass_1",
    });
    const game = (await db.collection("games").doc("ABCDE").get()).data()!;
    expect(game.rerollsUsed).to.deep.equal({});
    expect(game.aiControlledPlayers).to.include("player-a");
    expect((await db.collection("users").doc("player-a").get()).get("coins")).to.equal(200);
  });

  it("offers a no-move decision only when the human can afford Reroll", async () => {
    await db.collection("users").doc("player-a").set({coins: 50});
    await rollDiceIntent(db, {uid: "player-a"}, {
      roomCode: "ABCDE",
      expectedTurnVersion: 1,
      actionId: "no_move_roll_1",
    }, () => 1);
    let game = (await db.collection("games").doc("ABCDE").get()).data()!;
    expect(game.turnPhase).to.equal("waitingForRerollDecision");
    expect(game.currentTurn).to.equal("player-a");

    await db.collection("games").doc("ABCDE").set(createInitialGameForTests());
    await db.collection("users").doc("player-a").set({coins: 49});
    await rollDiceIntent(db, {uid: "player-a"}, {
      roomCode: "ABCDE",
      expectedTurnVersion: 1,
      actionId: "ordinary_no_move_1",
    }, () => 1);
    game = (await db.collection("games").doc("ABCDE").get()).data()!;
    expect(game.turnPhase).to.equal("waitingForRoll");
    expect(game.currentTurn).to.equal("player-b");
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
      rerollsUsed: {"player-a": 2},
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
    expect(game.rerollsUsed).to.deep.equal({});
    expect(game.rerollConfig).to.deep.equal({
      costs: [50, 60, 70],
      maxUsesPerMatch: 3,
    });
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
