import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, serverTimestamp, setDoc, updateDoc} from "firebase/firestore";

const ownerEmail = "kaszadavid1998@gmail.com";

function baseGame(hostUid: string, sandbox = false): Record<string, unknown> {
  const opponent = "bot_seat_2";
  const pieces = () => [1, 2, 3, 4].map((id) => ({id, pos: sandbox ? 49 : -1, inHome: false}));
  return {
    players: [hostUid, opponent],
    playerNames: {[hostUid]: "Host", [opponent]: "Computer"},
    preferredColors: {[hostUid]: "blue", [opponent]: "red"},
    playerDiceSkins: {[hostUid]: "classic", [opponent]: "classic"},
    playerSeats: {[hostUid]: 0, [opponent]: 2},
    seatTypes: {"0": "human", "2": "computer"},
    hostUid,
    currentTurn: hostUid,
    diceValue: 0,
    hasRolled: false,
    status: "waiting",
    winnerUid: "",
    finishOrder: [],
    startedAt: null,
    finishedAt: null,
    boardId: "classic",
    isTestModeActive: sandbox,
    maxPlayers: 2,
    opponentType: "computer",
    isPublic: false,
    openSeats: 0,
    matchmakingOpen: false,
    createdAt: serverTimestamp(),
    lastActivityAt: serverTimestamp(),
    expiresAt: new Date(Date.now() + 10 * 60 * 1000),
    pieces: {[hostUid]: pieces(), [opponent]: pieces()},
    activeMove: null,
    activeDiceRoll: null,
    turnPhase: "waitingForRoll",
    turnDeadlineAt: null,
    turnStartedAt: null,
    turnDurationSeconds: 0,
    turnVersion: 0,
    lastActionId: "",
    lastActionType: "",
    aiControlledPlayers: [],
    pendingReconnectPlayers: [],
    forfeitedPlayers: [],
    automationLease: null,
    systemEvent: null,
    playerPresence: {},
  };
}

describe("Firestore authority rules", () => {
  let env: RulesTestEnvironment;

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-ludora",
      firestore: {
        rules: readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8"),
      },
    });
  });

  beforeEach(async () => env.clearFirestore());
  after(async () => env.cleanup());

  async function seedPlayingGame(): Promise<void> {
    await env.withSecurityRulesDisabled(async (context) => {
      const data = baseGame("player-a");
      await setDoc(doc(context.firestore(), "games/ABCDE"), {
        ...data,
        status: "playing",
        startedAt: new Date(),
        turnStartedAt: new Date(),
        turnDeadlineAt: new Date(Date.now() + 30000),
        turnDurationSeconds: 30,
        turnVersion: 1,
      });
      await setDoc(doc(context.firestore(), "users/player-a"), {
        displayName: "A",
        xp: 10,
        coins: 5,
        rewardedMatches: 1,
        rewardedWins: 0,
        rewardedPodiums: 1,
      });
    });
  }

  it("denies client-authored dice, movement, winner, and progression", async () => {
    await seedPlayingGame();
    const player = env.authenticatedContext("player-a").firestore();
    await assertFails(updateDoc(doc(player, "games/ABCDE"), {diceValue: 6, hasRolled: true}));
    await assertFails(updateDoc(doc(player, "games/ABCDE"), {"pieces.player-a": [
      {id: 1, pos: 51, inHome: false}, {id: 2, pos: -1, inHome: false},
      {id: 3, pos: -1, inHome: false}, {id: 4, pos: -1, inHome: false},
    ]}));
    await assertFails(updateDoc(doc(player, "games/ABCDE"), {"pieces.player-b": []}));
    await assertFails(updateDoc(doc(player, "games/ABCDE"), {status: "finished", winnerUid: "player-a"}));
    await assertFails(updateDoc(doc(player, "users/player-a"), {xp: 999999, coins: 999999}));
    await assertFails(setDoc(doc(player, "users/player-a/rewardClaims/forged"), {xp: 999999}));
  });

  it("rejects gameplay writes from a non-participant", async () => {
    await seedPlayingGame();
    const outsider = env.authenticatedContext("outsider").firestore();
    await assertFails(updateDoc(doc(outsider, "games/ABCDE"), {diceValue: 4}));
  });

  it("allows Sandbox creation only for the verified owner token", async () => {
    const owner = env.authenticatedContext("owner-uid", {
      email: ownerEmail,
      email_verified: true,
    }).firestore();
    await assertSucceeds(setDoc(doc(owner, "games/OWNER"), baseGame("owner-uid", true)));

    const other = env.authenticatedContext("other-uid", {
      email: "other@example.com",
      email_verified: true,
    }).firestore();
    await assertFails(setDoc(doc(other, "games/OTHER"), baseGame("other-uid", true)));

    const unverified = env.authenticatedContext("owner-unverified", {
      email: ownerEmail,
      email_verified: false,
    }).firestore();
    await assertFails(setDoc(doc(unverified, "games/UNVER"), baseGame("owner-unverified", true)));

    const anonymous = env.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(anonymous, "games/ANONX"), baseGame("anonymous", true)));
  });

  it("does not let client room-data manipulation bypass Sandbox authorization", async () => {
    const other = env.authenticatedContext("other-uid", {
      email: "other@example.com",
      email_verified: true,
    }).firestore();
    await assertSucceeds(setDoc(doc(other, "games/NORMAL"), baseGame("other-uid", false)));
    await assertFails(updateDoc(doc(other, "games/NORMAL"), {isTestModeActive: true}));
  });

  it("does not let room creation inject an arbitrary human participant", async () => {
    const attacker = env.authenticatedContext("attacker").firestore();
    const forged = baseGame("attacker");
    forged.players = ["attacker", "victim-uid"];
    forged.playerNames = {attacker: "Attacker", "victim-uid": "Victim"};
    forged.playerSeats = {attacker: 0, "victim-uid": 2};
    forged.pieces = {
      attacker: [1, 2, 3, 4].map((id) => ({id, pos: -1, inHome: false})),
      "victim-uid": [1, 2, 3, 4].map((id) => ({id, pos: -1, inHome: false})),
    };
    await assertFails(setDoc(doc(attacker, "games/FORGE"), forged));
  });

  it("does not let a joining player rewrite existing participant metadata", async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      const room = baseGame("host");
      room.players = ["host"];
      room.maxPlayers = 2;
      room.openSeats = 1;
      room.matchmakingOpen = true;
      room.playerNames = {host: "Host"};
      room.preferredColors = {host: "blue"};
      room.playerDiceSkins = {host: "classic"};
      room.playerSeats = {host: 0};
      room.pieces = {host: [1, 2, 3, 4].map((id) => ({id, pos: -1, inHome: false}))};
      await setDoc(doc(context.firestore(), "games/JOINX"), room);
    });
    const joiner = env.authenticatedContext("joiner").firestore();
    await assertFails(updateDoc(doc(joiner, "games/JOINX"), {
      players: ["host", "joiner"],
      playerNames: {host: "Hacked", joiner: "Joiner"},
      preferredColors: {host: "red", joiner: "green"},
      playerDiceSkins: {host: "gold", joiner: "classic"},
      playerSeats: {host: 0, joiner: 2},
      pieces: {
        host: [1, 2, 3, 4].map((id) => ({id, pos: 51, inHome: false})),
        joiner: [1, 2, 3, 4].map((id) => ({id, pos: -1, inHome: false})),
      },
      openSeats: 0,
      matchmakingOpen: false,
      lastActivityAt: serverTimestamp(),
      expiresAt: new Date(Date.now() + 10 * 60 * 1000),
    }));
  });

  it("allows a joining player to add only their own room metadata", async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      const room = baseGame("host");
      room.players = ["host"];
      room.maxPlayers = 2;
      room.openSeats = 1;
      room.matchmakingOpen = true;
      room.playerNames = {host: "Host"};
      room.preferredColors = {host: "blue"};
      room.playerDiceSkins = {host: "classic"};
      room.playerSeats = {host: 0};
      room.pieces = {host: [1, 2, 3, 4].map((id) => ({id, pos: -1, inHome: false}))};
      await setDoc(doc(context.firestore(), "games/JOINY"), room);
    });
    const joiner = env.authenticatedContext("joiner").firestore();
    await assertSucceeds(updateDoc(doc(joiner, "games/JOINY"), {
      players: ["host", "joiner"],
      playerNames: {host: "Host", joiner: "Joiner"},
      preferredColors: {host: "blue", joiner: "red"},
      playerDiceSkins: {host: "classic", joiner: "ocean"},
      playerSeats: {host: 0, joiner: 2},
      pieces: {
        host: [1, 2, 3, 4].map((id) => ({id, pos: -1, inHome: false})),
        joiner: [1, 2, 3, 4].map((id) => ({id, pos: -1, inHome: false})),
      },
      openSeats: 0,
      matchmakingOpen: false,
      lastActivityAt: serverTimestamp(),
      expiresAt: new Date(Date.now() + 10 * 60 * 1000),
    }));
  });

  it("keeps legitimate verified-owner waiting-room Sandbox settings writable", async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "games/SETUP"), baseGame("owner-uid", false));
    });
    const owner = env.authenticatedContext("owner-uid", {
      email: ownerEmail,
      email_verified: true,
    }).firestore();
    const sandboxPieces = () => [1, 2, 3, 4].map((id) => ({id, pos: 49, inHome: false}));
    await assertSucceeds(updateDoc(doc(owner, "games/SETUP"), {
      boardId: "classic",
      isTestModeActive: true,
      isPublic: false,
      pieces: {"owner-uid": sandboxPieces(), "bot_seat_2": sandboxPieces()},
      lastActivityAt: serverTimestamp(),
      expiresAt: new Date(Date.now() + 10 * 60 * 1000),
    }));
  });
});
