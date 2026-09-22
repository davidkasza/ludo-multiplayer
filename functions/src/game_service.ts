import {randomInt} from "node:crypto";
import {
  DocumentData,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {isSandboxOwnerToken} from "./auth";
import {
  applyCaptures,
  buildMoveSteps,
  destination,
  finishOrderAfterMove,
  grantsExtraTurn,
  hasCompletedAllPieces,
  hasValidMove,
  isMatchFinished,
  isValidMove,
  nextActivePlayer,
  Piece,
  reachesGoal,
  resolveNoValidMove,
  SAFE_GLOBAL_POSITIONS,
  globalPathIndexForSeat,
} from "./ludo_rules";
import {
  canAffordReroll,
  DEFAULT_REROLL_PRICING,
  RerollPricing,
  rerollCostAfterUses,
  rerollPricingForStorage,
  rerollPricingFromData,
} from "./reroll";

export const ROLL_DECISION_SECONDS = 30;
export const MOVE_DECISION_SECONDS = 30;
export const REROLL_DECISION_PHASE = "waitingForRerollDecision";
export const REROLL_WINDOW_MILLIS = 3000;
const DICE_ROLL_PRESENTATION_MILLIS = 800;
const ACTIVE_GAME_MILLIS = 24 * 60 * 60 * 1000;
const FINISHED_GAME_MILLIS = 60 * 60 * 1000;
const RECENT_ACTION_LIMIT = 16;

export interface ActionIntent {
  roomCode: string;
  expectedTurnVersion: number;
  actionId: string;
}

export interface CallerIdentity {
  uid: string;
  token?: Record<string, unknown>;
}

interface GameState {
  players: string[];
  playerNames: Record<string, string>;
  preferredColors: Record<string, string>;
  playerSeats: Record<string, number>;
  pieces: Record<string, Piece[]>;
  currentTurn: string;
  diceValue: number;
  hasRolled: boolean;
  status: string;
  winnerUid: string;
  finishOrder: string[];
  boardId: string;
  isTestModeActive: boolean;
  maxPlayers: number;
  turnPhase: string;
  turnVersion: number;
  rerollsUsed: Record<string, number>;
  rerollPricing: RerollPricing;
  lastActionId: string;
  recentActionIds: string[];
  aiControlledPlayers: string[];
  pendingReconnectPlayers: string[];
  forfeitedPlayers: string[];
  turnStartedAt?: Timestamp;
  turnDeadlineAt?: Timestamp;
  rerollAvailableAt?: Timestamp;
  rerollDeadlineAt?: Timestamp;
  turnDurationSeconds: number;
  startedAt?: Timestamp;
  activeMove?: Record<string, unknown> | null;
  activeDiceRoll?: Record<string, unknown> | null;
}

interface ActionResult {
  applied: boolean;
  duplicate?: boolean;
  actionId: string;
  turnVersion: number;
  actionType?: string;
  [key: string]: unknown;
}

export type DiceRoller = () => number;

function secureDiceRoll(): number {
  return randomInt(1, 7);
}

function generatedDiceValue(rollDie: DiceRoller): number {
  const value = rollDie();
  if (!Number.isInteger(value) || value < 1 || value > 6) {
    throw new HttpsError("internal", "The secure dice generator returned an invalid value.");
  }
  return value;
}

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value;
}

function parseIntent(raw: unknown): ActionIntent {
  const data = raw && typeof raw === "object" ? raw as Record<string, unknown> : {};
  const roomCode = requireString(data.roomCode, "roomCode").trim().toUpperCase();
  const actionId = requireString(data.actionId, "actionId").trim();
  const expectedTurnVersion = Number(data.expectedTurnVersion);
  if (!/^[A-Z0-9]{5}$/.test(roomCode)) {
    throw new HttpsError("invalid-argument", "roomCode is malformed.");
  }
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(actionId)) {
    throw new HttpsError("invalid-argument", "actionId is malformed.");
  }
  if (!Number.isSafeInteger(expectedTurnVersion) || expectedTurnVersion < 0) {
    throw new HttpsError("invalid-argument", "expectedTurnVersion is malformed.");
  }
  return {roomCode, actionId, expectedTurnVersion};
}

interface RollBoundIntent extends ActionIntent {
  expectedActionId: string;
}

function parseRollBoundIntent(raw: unknown): RollBoundIntent {
  const intent = parseIntent(raw);
  const data = raw as Record<string, unknown>;
  const expectedActionId = requireString(data.expectedActionId, "expectedActionId").trim();
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(expectedActionId)) {
    throw new HttpsError("invalid-argument", "expectedActionId is malformed.");
  }
  return {...intent, expectedActionId};
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter((item): item is string => typeof item === "string" && item.length > 0))];
}

function stringMap(value: unknown): Record<string, string> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return Object.fromEntries(
    Object.entries(value).filter((entry): entry is [string, string] => typeof entry[1] === "string"),
  );
}

function numberMap(value: unknown): Record<string, number> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const result: Record<string, number> = {};
  for (const [key, raw] of Object.entries(value)) {
    if (typeof raw === "number" && Number.isInteger(raw)) result[key] = raw;
  }
  return result;
}

function rerollUsageMap(
  value: unknown,
  players: readonly string[],
  maximum: number,
): Record<string, number> {
  const source = numberMap(value);
  const result: Record<string, number> = {};
  for (const playerId of players) {
    const uses = source[playerId];
    if (Number.isInteger(uses) && uses >= 0 && uses <= maximum) {
      result[playerId] = uses;
    }
  }
  return result;
}

function parsePieces(raw: unknown, players: readonly string[]): Record<string, Piece[]> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new HttpsError("data-loss", "The game has malformed piece state.");
  }
  const source = raw as Record<string, unknown>;
  const result: Record<string, Piece[]> = {};
  for (const playerId of players) {
    const values = source[playerId];
    if (!Array.isArray(values) || values.length !== 4) {
      throw new HttpsError("data-loss", `Invalid pieces for participant ${playerId}.`);
    }
    const ids = new Set<number>();
    result[playerId] = values.map((rawPiece) => {
      if (!rawPiece || typeof rawPiece !== "object" || Array.isArray(rawPiece)) {
        throw new HttpsError("data-loss", "A piece entry is malformed.");
      }
      const map = rawPiece as Record<string, unknown>;
      const id = Number(map.id);
      const pos = Number(map.pos);
      const inHome = map.inHome === true;
      if (!Number.isInteger(id) || id < 1 || id > 4 || ids.has(id)) {
        throw new HttpsError("data-loss", "Piece IDs are malformed.");
      }
      if (!Number.isInteger(pos) || (inHome ? pos < 0 || pos > 5 : pos < -1 || pos > 51)) {
        throw new HttpsError("data-loss", "A piece position is malformed.");
      }
      ids.add(id);
      return {id, pos, inHome};
    });
  }
  return result;
}

function parseGame(data: DocumentData): GameState {
  const players = stringArray(data.players);
  if (players.length < 2 || players.length > 4) {
    throw new HttpsError("data-loss", "The room participant list is malformed.");
  }
  const currentTurn = typeof data.currentTurn === "string" ? data.currentTurn : "";
  const status = typeof data.status === "string" ? data.status : "waiting";
  if (status === "playing" && !players.includes(currentTurn)) {
    throw new HttpsError("data-loss", "The current turn is not a participant.");
  }
  const diceValue = Number(data.diceValue ?? 0);
  const turnVersion = Number(data.turnVersion ?? 0);
  if (!Number.isInteger(diceValue) || diceValue < 0 || diceValue > 6 || !Number.isSafeInteger(turnVersion)) {
    throw new HttpsError("data-loss", "The room action state is malformed.");
  }
  const rerollPricing = rerollPricingFromData(data.rerollConfig);
  const activeRoll = data.activeDiceRoll && typeof data.activeDiceRoll === "object" ?
    data.activeDiceRoll as Record<string, unknown> : null;
  const legacyRollStart = activeRoll?.committedAt instanceof Timestamp ?
    activeRoll.committedAt.toMillis() : Number(activeRoll?.startedAt ?? 0);
  const legacyRollDuration = Number(activeRoll?.durationMs ?? DICE_ROLL_PRESENTATION_MILLIS);
  const rerollAvailableAt = data.rerollAvailableAt instanceof Timestamp ?
    data.rerollAvailableAt :
    Number.isSafeInteger(legacyRollStart) && legacyRollStart > 0 &&
      Number.isSafeInteger(legacyRollDuration) && legacyRollDuration > 0 ?
      Timestamp.fromMillis(legacyRollStart + legacyRollDuration) : undefined;
  const rerollDeadlineAt = data.rerollDeadlineAt instanceof Timestamp ?
    data.rerollDeadlineAt : rerollAvailableAt ?
      Timestamp.fromMillis(rerollAvailableAt.toMillis() + REROLL_WINDOW_MILLIS) : undefined;
  return {
    players,
    playerNames: stringMap(data.playerNames),
    preferredColors: stringMap(data.preferredColors),
    playerSeats: numberMap(data.playerSeats),
    pieces: parsePieces(data.pieces, players),
    currentTurn,
    diceValue,
    hasRolled: data.hasRolled === true,
    status,
    winnerUid: typeof data.winnerUid === "string" ? data.winnerUid : "",
    finishOrder: stringArray(data.finishOrder).filter((id) => players.includes(id)),
    boardId: typeof data.boardId === "string" ? data.boardId : "classic",
    isTestModeActive: data.isTestModeActive === true,
    maxPlayers: Number.isInteger(data.maxPlayers) ? Number(data.maxPlayers) : 2,
    turnPhase: data.turnPhase === "waitingForMove" || data.turnPhase === REROLL_DECISION_PHASE ?
      data.turnPhase : "waitingForRoll",
    turnVersion,
    rerollsUsed: rerollUsageMap(data.rerollsUsed, players, rerollPricing.maxUsesPerMatch),
    rerollPricing,
    lastActionId: typeof data.lastActionId === "string" ? data.lastActionId : "",
    recentActionIds: stringArray(data.recentActionIds).slice(-RECENT_ACTION_LIMIT),
    aiControlledPlayers: stringArray(data.aiControlledPlayers).filter((id) => players.includes(id)),
    pendingReconnectPlayers: stringArray(data.pendingReconnectPlayers).filter((id) => players.includes(id)),
    forfeitedPlayers: stringArray(data.forfeitedPlayers).filter((id) => players.includes(id)),
    turnStartedAt: data.turnStartedAt instanceof Timestamp ? data.turnStartedAt : undefined,
    turnDeadlineAt: data.turnDeadlineAt instanceof Timestamp ? data.turnDeadlineAt : undefined,
    rerollAvailableAt,
    rerollDeadlineAt,
    turnDurationSeconds: Number.isInteger(data.turnDurationSeconds) ? Number(data.turnDurationSeconds) : 0,
    startedAt: data.startedAt instanceof Timestamp ? data.startedAt : undefined,
    activeMove: data.activeMove && typeof data.activeMove === "object" ? data.activeMove : null,
    activeDiceRoll: data.activeDiceRoll && typeof data.activeDiceRoll === "object" ? data.activeDiceRoll : null,
  };
}

function assertParticipant(game: GameState, caller: CallerIdentity): void {
  if (!game.players.includes(caller.uid)) {
    throw new HttpsError("permission-denied", "Only room participants may perform gameplay actions.");
  }
  if (game.isTestModeActive && !isSandboxOwnerToken(caller.token)) {
    throw new HttpsError("permission-denied", "Sandbox gameplay is restricted to the verified owner account.");
  }
}

function assertCurrentVersion(game: GameState, intent: ActionIntent): void {
  if (game.recentActionIds.includes(intent.actionId) || game.lastActionId === intent.actionId) return;
  if (game.turnVersion !== intent.expectedTurnVersion) {
    throw new HttpsError("aborted", "The turn changed before this action was processed.");
  }
}

function duplicateResult(game: GameState, intent: ActionIntent): ActionResult | null {
  if (!game.recentActionIds.includes(intent.actionId) && game.lastActionId !== intent.actionId) return null;
  return {applied: false, duplicate: true, actionId: intent.actionId, turnVersion: game.turnVersion};
}

function recentActions(game: GameState, actionId: string): string[] {
  return [...game.recentActionIds.filter((id) => id !== actionId), actionId].slice(-RECENT_ACTION_LIMIT);
}

function profileCoinBalance(data: DocumentData | undefined): number {
  const coins = Number(data?.coins ?? 0);
  return Number.isSafeInteger(coins) && coins > 0 ? coins : 0;
}

function rerollsUsedBy(game: GameState, playerId: string): number {
  return game.rerollsUsed[playerId] ?? 0;
}

function assertCurrentRoll(game: GameState, expectedActionId: string): void {
  const activeActionId = typeof game.activeDiceRoll?.actionId === "string" ?
    game.activeDiceRoll.actionId : "";
  if (activeActionId !== expectedActionId) {
    throw new HttpsError("aborted", "The dice result has already changed.", {
      reason: "stale-action",
    });
  }
}

function deadlineExpired(game: GameState, now: Timestamp): boolean {
  const startedAt = game.turnStartedAt;
  if (startedAt && game.turnDurationSeconds > 0) {
    return startedAt.toMillis() + game.turnDurationSeconds * 1000 <= now.toMillis();
  }
  return game.turnDeadlineAt != null && game.turnDeadlineAt.toMillis() <= now.toMillis();
}

function rerollWindowExpired(game: GameState, now: Timestamp): boolean {
  return game.rerollDeadlineAt != null &&
    game.rerollDeadlineAt.toMillis() <= now.toMillis();
}

function turnTiming(now: Timestamp, seconds: number): Record<string, unknown> {
  return {
    turnStartedAt: now,
    turnDurationSeconds: seconds,
    turnDeadlineAt: Timestamp.fromMillis(now.toMillis() + seconds * 1000),
  };
}

function activity(now: Timestamp, finished = false): Record<string, unknown> {
  return {
    lastActivityAt: now,
    expiresAt: Timestamp.fromMillis(now.toMillis() + (finished ? FINISHED_GAME_MILLIS : ACTIVE_GAME_MILLIS)),
  };
}

function reconnectOrTakeoverFields(
  game: GameState,
  playerId: string,
  callerUid: string,
  didExpire: boolean,
  nextVersion: number,
  now: Timestamp,
): Record<string, unknown> {
  const ai = [...game.aiControlledPlayers];
  const pending = [...game.pendingReconnectPlayers];
  let systemEvent: Record<string, unknown> | undefined;
  const reconnectNow = callerUid === playerId && pending.includes(playerId) && !game.forfeitedPlayers.includes(playerId);
  if (reconnectNow) {
    const aiIndex = ai.indexOf(playerId);
    if (aiIndex >= 0) ai.splice(aiIndex, 1);
    const pendingIndex = pending.indexOf(playerId);
    if (pendingIndex >= 0) pending.splice(pendingIndex, 1);
    systemEvent = {
      id: `reconnected_${playerId}_${nextVersion}`,
      type: "playerReconnected",
      playerId,
      createdAtMs: now.toMillis(),
    };
  } else if (didExpire && !game.aiControlledPlayers.includes(playerId) && !playerId.startsWith("bot_")) {
    ai.push(playerId);
    systemEvent = {
      id: `takeover_${playerId}_${nextVersion}`,
      type: "aiTakeover",
      playerId,
      createdAtMs: now.toMillis(),
    };
  }
  return {
    aiControlledPlayers: [...new Set(ai)],
    pendingReconnectPlayers: [...new Set(pending)],
    ...(systemEvent ? {systemEvent} : {}),
  };
}

function applyRoll(
  game: GameState,
  callerUid: string,
  actionId: string,
  rolledValue: number,
  now: Timestamp,
  didExpire: boolean,
  options: {
    allowNoMoveRerollDecision?: boolean;
    preserveTurnTiming?: boolean;
    actionType?: "dice" | "reroll";
  } = {},
): {update: Record<string, unknown>; result: ActionResult} {
  const playerId = game.currentTurn;
  const nextVersion = game.turnVersion + 1;
  const validMove = hasValidMove(game.pieces[playerId] ?? [], rolledValue);
  const roll = {
    actionId,
    turnVersion: nextVersion,
    playerId,
    startedAt: now.toMillis(),
    durationMs: DICE_ROLL_PRESENTATION_MILLIS,
    result: rolledValue,
    stateApplied: true,
    committedAt: FieldValue.serverTimestamp(),
  };
  const update: Record<string, unknown> = {
    diceValue: rolledValue,
    rerollConfig: rerollPricingForStorage(game.rerollPricing),
    rerollAvailableAt: Timestamp.fromMillis(
      now.toMillis() + DICE_ROLL_PRESENTATION_MILLIS,
    ),
    rerollDeadlineAt: Timestamp.fromMillis(
      now.toMillis() + DICE_ROLL_PRESENTATION_MILLIS + REROLL_WINDOW_MILLIS,
    ),
    activeDiceRoll: roll,
    activeMove: null,
    automationLease: null,
    lastActionId: actionId,
    lastActionType: options.actionType ?? "dice",
    recentActionIds: recentActions(game, actionId),
    turnVersion: nextVersion,
    ...reconnectOrTakeoverFields(game, playerId, callerUid, didExpire, nextVersion, now),
    ...activity(now),
  };
  let keepsTurn = true;
  if (validMove) {
    Object.assign(update, {
      hasRolled: true,
      turnPhase: "waitingForMove",
      ...(!options.preserveTurnTiming ? turnTiming(now, MOVE_DECISION_SECONDS) : {}),
    });
  } else if (options.allowNoMoveRerollDecision) {
    Object.assign(update, {
      hasRolled: true,
      turnPhase: REROLL_DECISION_PHASE,
      ...(!options.preserveTurnTiming ? turnTiming(now, MOVE_DECISION_SECONDS) : {}),
    });
  } else {
    const resolution = resolveNoValidMove(game.players, playerId, game.finishOrder, rolledValue);
    keepsTurn = resolution.keepsTurn;
    Object.assign(update, {
      hasRolled: false,
      currentTurn: resolution.nextPlayerId,
      turnPhase: "waitingForRoll",
      rerollAvailableAt: null,
      rerollDeadlineAt: null,
      ...turnTiming(now, ROLL_DECISION_SECONDS),
    });
  }
  return {
    update,
    result: {
      applied: true,
      actionId,
      actionType: options.actionType ?? "dice",
      turnVersion: nextVersion,
      diceValue: rolledValue,
      hasValidMove: validMove,
      keepsTurn,
      awaitingRerollDecision: !validMove && options.allowNoMoveRerollDecision === true,
    },
  };
}

function applyNoValidMoveResolution(
  game: GameState,
  callerUid: string,
  actionId: string,
  now: Timestamp,
  didExpire: boolean,
): {update: Record<string, unknown>; result: ActionResult} {
  const playerId = game.currentTurn;
  const nextVersion = game.turnVersion + 1;
  const resolution = resolveNoValidMove(
    game.players,
    playerId,
    game.finishOrder,
    game.diceValue,
  );
  return {
    update: {
      hasRolled: false,
      currentTurn: resolution.nextPlayerId,
      turnPhase: "waitingForRoll",
      rerollAvailableAt: null,
      rerollDeadlineAt: null,
      automationLease: null,
      lastActionId: actionId,
      lastActionType: "noMovePass",
      recentActionIds: recentActions(game, actionId),
      turnVersion: nextVersion,
      ...turnTiming(now, ROLL_DECISION_SECONDS),
      ...reconnectOrTakeoverFields(game, playerId, callerUid, didExpire, nextVersion, now),
      ...activity(now),
    },
    result: {
      applied: true,
      actionId,
      actionType: "noMovePass",
      turnVersion: nextVersion,
      keepsTurn: resolution.keepsTurn,
    },
  };
}

function applyMove(
  game: GameState,
  callerUid: string,
  actionId: string,
  pieceId: number,
  now: Timestamp,
  didExpire: boolean,
): {update: Record<string, unknown>; result: ActionResult; matchResult?: Record<string, unknown>} {
  const playerId = game.currentTurn;
  const originalPieces = game.pieces[playerId] ?? [];
  const target = originalPieces.find((piece) => piece.id === pieceId);
  if (!target || !isValidMove(target, game.diceValue)) {
    throw new HttpsError("failed-precondition", "That piece cannot move for the current roll.");
  }
  const steps = buildMoveSteps(target, game.diceValue);
  if (steps.length < 2) throw new HttpsError("data-loss", "The move path is invalid.");
  const moveDestination = steps[steps.length - 1];
  const nextVersion = game.turnVersion + 1;
  const movedPieces = Object.fromEntries(
    Object.entries(game.pieces).map(([id, values]) => [id, values.map((piece) => ({...piece}))]),
  );
  const updatedPlayerPieces = originalPieces.map((piece) => piece.id === pieceId ? {
    ...piece,
    pos: moveDestination.pos,
    inHome: moveDestination.inHome,
  } : piece);
  movedPieces[playerId] = updatedPlayerPieces;
  const capture = applyCaptures(movedPieces, game.playerSeats, game.players, playerId, moveDestination);
  const didReachGoal = reachesGoal(target, moveDestination);
  const playerFinished = hasCompletedAllPieces(updatedPlayerPieces);
  const finishOrder = finishOrderAfterMove(game.players, game.finishOrder, playerId, playerFinished);
  const matchFinished = isMatchFinished(game.players, finishOrder);
  const extraTurn = grantsExtraTurn(game.diceValue, capture.didCapture, didReachGoal);
  const playerFinishedNow = playerFinished && !game.finishOrder.includes(playerId);
  const nextPlayer = matchFinished ? "" : (playerFinishedNow || !extraTurn)
    ? nextActivePlayer(game.players, playerId, finishOrder)
    : playerId;
  const activeMove = {
    actionId,
    turnVersion: nextVersion,
    playerId,
    pieceId,
    startedAt: now.toMillis(),
    stepDurationMs: 250,
    steps,
    ...(capture.capturedPieces.length > 0 ? {capturedPieces: capture.capturedPieces} : {}),
    stateApplied: true,
    committedAt: FieldValue.serverTimestamp(),
  };
  const update: Record<string, unknown> = {
    pieces: capture.pieces,
    currentTurn: nextPlayer,
    hasRolled: false,
    status: matchFinished ? "finished" : "playing",
    winnerUid: finishOrder[0] ?? "",
    finishOrder,
    activeMove,
    activeDiceRoll: null,
    rerollAvailableAt: null,
    rerollDeadlineAt: null,
    automationLease: null,
    turnPhase: "waitingForRoll",
    turnStartedAt: matchFinished ? null : now,
    turnDurationSeconds: matchFinished ? 0 : ROLL_DECISION_SECONDS,
    turnDeadlineAt: matchFinished ? null : Timestamp.fromMillis(now.toMillis() + ROLL_DECISION_SECONDS * 1000),
    turnVersion: nextVersion,
    lastActionId: actionId,
    lastActionType: "move",
    recentActionIds: recentActions(game, actionId),
    matchmakingOpen: false,
    ...reconnectOrTakeoverFields(game, playerId, callerUid, didExpire, nextVersion, now),
    ...activity(now, matchFinished),
    ...(matchFinished ? {finishedAt: now} : {}),
  };
  const humanPlayerCount = game.players.filter((id) => !id.startsWith("bot_")).length;
  const matchResult = matchFinished ? {
    authorityVersion: 1,
    participantIds: game.players,
    ranking: finishOrder,
    playerNames: game.playerNames,
    preferredColors: game.preferredColors,
    playerSeats: game.playerSeats,
    boardId: game.boardId,
    isTestModeActive: game.isTestModeActive,
    playerCount: game.players.length,
    humanPlayerCount,
    botPlayerCount: game.players.length - humanPlayerCount,
    startedAt: game.startedAt ?? now,
    finishedAt: now,
    createdAt: now,
  } : undefined;
  return {
    update,
    matchResult,
    result: {
      applied: true,
      actionId,
      actionType: "move",
      turnVersion: nextVersion,
      didCapture: capture.didCapture,
      didReachGoal,
      playerFinishedNow,
      matchFinished,
      extraTurn: !matchFinished && nextPlayer === playerId,
    },
  };
}

function ensurePlayable(game: GameState): void {
  if (game.status !== "playing") throw new HttpsError("failed-precondition", "The match is not active.");
  if (game.finishOrder.includes(game.currentTurn)) {
    throw new HttpsError("data-loss", "A finished player owns the current turn.");
  }
}

export async function rollDiceIntent(
  db: Firestore,
  caller: CallerIdentity,
  rawData: unknown,
  rollDie: DiceRoller = secureDiceRoll,
): Promise<ActionResult> {
  const intent = parseIntent(rawData);
  const data = rawData as Record<string, unknown>;
  const forcedValue = Number(data.forcedValue ?? 0);
  const roomRef = db.collection("games").doc(intent.roomCode);
  return db.runTransaction(async (transaction: Transaction) => {
    const snapshot = await transaction.get(roomRef);
    if (!snapshot.exists) throw new HttpsError("not-found", "Room not found.");
    const game = parseGame(snapshot.data()!);
    assertParticipant(game, caller);
    ensurePlayable(game);
    const duplicate = duplicateResult(game, intent);
    if (duplicate) return duplicate;
    assertCurrentVersion(game, intent);
    if (game.currentTurn !== caller.uid || game.hasRolled || game.turnPhase !== "waitingForRoll") {
      throw new HttpsError("failed-precondition", "It is not your roll phase.");
    }
    if (game.aiControlledPlayers.includes(caller.uid)) {
      throw new HttpsError("failed-precondition", "Request control back before rolling.");
    }
    let rolledValue = generatedDiceValue(rollDie);
    if (forcedValue !== 0) {
      if (!game.isTestModeActive || !isSandboxOwnerToken(caller.token)) {
        throw new HttpsError("permission-denied", "Forced dice are only available to the Sandbox owner.");
      }
      if (!Number.isInteger(forcedValue) || forcedValue < 1 || forcedValue > 6) {
        throw new HttpsError("invalid-argument", "forcedValue must be between 1 and 6.");
      }
      rolledValue = forcedValue;
    }
    const now = Timestamp.now();
    let allowNoMoveRerollDecision = false;
    if (!hasValidMove(game.pieces[caller.uid] ?? [], rolledValue)) {
      const profile = await transaction.get(db.collection("users").doc(caller.uid));
      allowNoMoveRerollDecision = canAffordReroll(
        game.rerollPricing,
        rerollsUsedBy(game, caller.uid),
        profileCoinBalance(profile.data()),
      );
    }
    const applied = applyRoll(game, caller.uid, intent.actionId, rolledValue, now, false, {
      allowNoMoveRerollDecision,
    });
    transaction.update(roomRef, applied.update);
    return applied.result;
  });
}

export async function useRerollIntent(
  db: Firestore,
  caller: CallerIdentity,
  rawData: unknown,
  rollDie: DiceRoller = secureDiceRoll,
): Promise<ActionResult> {
  const intent = parseRollBoundIntent(rawData);
  const roomRef = db.collection("games").doc(intent.roomCode);
  const profileRef = db.collection("users").doc(caller.uid);
  return db.runTransaction(async (transaction: Transaction) => {
    const snapshot = await transaction.get(roomRef);
    if (!snapshot.exists) throw new HttpsError("not-found", "Room not found.");
    const game = parseGame(snapshot.data()!);
    assertParticipant(game, caller);
    ensurePlayable(game);
    const duplicate = duplicateResult(game, intent);
    if (duplicate) {
      const profile = await transaction.get(profileRef);
      const uses = rerollsUsedBy(game, caller.uid);
      return {
        ...duplicate,
        actionType: "reroll",
        coinBalance: profileCoinBalance(profile.data()),
        rerollsUsed: uses,
        nextRerollCost: rerollCostAfterUses(game.rerollPricing, uses),
      };
    }
    assertCurrentVersion(game, intent);
    assertCurrentRoll(game, intent.expectedActionId);
    if (game.currentTurn !== caller.uid || !game.hasRolled ||
        (game.turnPhase !== "waitingForMove" && game.turnPhase !== REROLL_DECISION_PHASE) ||
        game.activeMove != null) {
      throw new HttpsError("failed-precondition", "The current dice result cannot be rerolled.", {
        reason: "reroll-unavailable",
      });
    }
    if (caller.uid.startsWith("bot_") || game.aiControlledPlayers.includes(caller.uid)) {
      throw new HttpsError("failed-precondition", "AI-controlled players cannot use Reroll.", {
        reason: "ai-controlled",
      });
    }
    const now = Timestamp.now();
    if (game.rerollAvailableAt == null || game.rerollDeadlineAt == null ||
        now.toMillis() < game.rerollAvailableAt.toMillis() ||
        now.toMillis() >= game.rerollDeadlineAt.toMillis()) {
      throw new HttpsError("failed-precondition", "The Reroll window has expired.", {
        reason: "reroll-window-expired",
      });
    }
    if (deadlineExpired(game, now)) {
      throw new HttpsError("failed-precondition", "The turn deadline has expired.", {
        reason: "deadline-expired",
      });
    }
    const used = rerollsUsedBy(game, caller.uid);
    const price = rerollCostAfterUses(game.rerollPricing, used);
    if (price == null) {
      throw new HttpsError("failed-precondition", "The match Reroll limit has been reached.", {
        reason: "reroll-limit-reached",
        maximum: game.rerollPricing.maxUsesPerMatch,
      });
    }
    const profile = await transaction.get(profileRef);
    const coins = profileCoinBalance(profile.data());
    if (coins < price) {
      throw new HttpsError("resource-exhausted", "There are not enough coins for this Reroll.", {
        reason: "insufficient-coins",
        requiredCoins: price,
        coinBalance: coins,
      });
    }
    const nextUses = used + 1;
    const nextBalance = coins - price;
    const rolledValue = generatedDiceValue(rollDie);
    const allowNoMoveRerollDecision = canAffordReroll(
      game.rerollPricing,
      nextUses,
      nextBalance,
    );
    const applied = applyRoll(game, caller.uid, intent.actionId, rolledValue, now, false, {
      allowNoMoveRerollDecision,
      preserveTurnTiming: true,
      actionType: "reroll",
    });
    transaction.update(profileRef, {coins: nextBalance});
    transaction.update(roomRef, {
      ...applied.update,
      rerollsUsed: {...game.rerollsUsed, [caller.uid]: nextUses},
    });
    return {
      ...applied.result,
      chargedCoins: price,
      coinBalance: nextBalance,
      rerollsUsed: nextUses,
      nextRerollCost: rerollCostAfterUses(game.rerollPricing, nextUses),
    };
  });
}

export async function passNoValidMoveIntent(
  db: Firestore,
  caller: CallerIdentity,
  rawData: unknown,
): Promise<ActionResult> {
  const intent = parseRollBoundIntent(rawData);
  const roomRef = db.collection("games").doc(intent.roomCode);
  return db.runTransaction(async (transaction: Transaction) => {
    const snapshot = await transaction.get(roomRef);
    if (!snapshot.exists) throw new HttpsError("not-found", "Room not found.");
    const game = parseGame(snapshot.data()!);
    assertParticipant(game, caller);
    ensurePlayable(game);
    const duplicate = duplicateResult(game, intent);
    if (duplicate) return duplicate;
    assertCurrentVersion(game, intent);
    assertCurrentRoll(game, intent.expectedActionId);
    if (game.currentTurn !== caller.uid || !game.hasRolled ||
        game.turnPhase !== REROLL_DECISION_PHASE || game.activeMove != null ||
        hasValidMove(game.pieces[caller.uid] ?? [], game.diceValue)) {
      throw new HttpsError("failed-precondition", "There is no no-move decision to pass.", {
        reason: "pass-unavailable",
      });
    }
    if (game.aiControlledPlayers.includes(caller.uid)) {
      throw new HttpsError("failed-precondition", "Request control back before passing.");
    }
    const now = Timestamp.now();
    if (!rerollWindowExpired(game, now)) {
      throw new HttpsError("failed-precondition", "The Reroll decision window is still active.", {
        reason: "reroll-window-active",
      });
    }
    if (deadlineExpired(game, now)) {
      throw new HttpsError("failed-precondition", "The turn deadline has expired.", {
        reason: "deadline-expired",
      });
    }
    const applied = applyNoValidMoveResolution(
      game,
      caller.uid,
      intent.actionId,
      now,
      false,
    );
    transaction.update(roomRef, applied.update);
    return applied.result;
  });
}

export async function movePieceIntent(
  db: Firestore,
  caller: CallerIdentity,
  rawData: unknown,
): Promise<ActionResult> {
  const intent = parseIntent(rawData);
  const pieceId = Number((rawData as Record<string, unknown>).pieceId);
  if (!Number.isInteger(pieceId) || pieceId < 1 || pieceId > 4) {
    throw new HttpsError("invalid-argument", "pieceId must be between 1 and 4.");
  }
  const roomRef = db.collection("games").doc(intent.roomCode);
  const resultRef = db.collection("matchResults").doc(intent.roomCode);
  return db.runTransaction(async (transaction: Transaction) => {
    const snapshot = await transaction.get(roomRef);
    if (!snapshot.exists) throw new HttpsError("not-found", "Room not found.");
    const game = parseGame(snapshot.data()!);
    assertParticipant(game, caller);
    ensurePlayable(game);
    const duplicate = duplicateResult(game, intent);
    if (duplicate) return duplicate;
    assertCurrentVersion(game, intent);
    if (game.currentTurn !== caller.uid || !game.hasRolled || game.turnPhase !== "waitingForMove") {
      throw new HttpsError("failed-precondition", "It is not your move phase.");
    }
    if (game.aiControlledPlayers.includes(caller.uid)) {
      throw new HttpsError("failed-precondition", "Request control back before moving.");
    }
    const now = Timestamp.now();
    const applied = applyMove(game, caller.uid, intent.actionId, pieceId, now, false);
    transaction.update(roomRef, applied.update);
    if (applied.matchResult) transaction.set(resultRef, applied.matchResult, {merge: true});
    return applied.result;
  });
}

function botPieceScore(game: GameState, playerId: string, piece: Piece): number {
  const target = destination(piece, game.diceValue);
  let score = 0;
  if (target.inHome && target.pos === 5) score += 10000;
  else if (target.inHome) score += 3000 + target.pos * 100;
  if (piece.pos === -1) score += 1800;
  if (!target.inHome) {
    const seat = game.playerSeats[playerId] ?? game.players.indexOf(playerId);
    const global = globalPathIndexForSeat(seat, target.pos);
    if (SAFE_GLOBAL_POSITIONS.has(global)) score += 450;
    score += target.pos * 12;
    if (!SAFE_GLOBAL_POSITIONS.has(global)) {
      for (const opponentId of game.players) {
        if (opponentId === playerId) continue;
        const opponentSeat = game.playerSeats[opponentId] ?? game.players.indexOf(opponentId);
        if ((game.pieces[opponentId] ?? []).some((opponent) =>
          opponent.pos >= 0 && !opponent.inHome && globalPathIndexForSeat(opponentSeat, opponent.pos) === global)) {
          score += 5000;
          break;
        }
      }
    }
  }
  return score;
}

function chooseBotPiece(game: GameState, playerId: string): Piece {
  const valid = (game.pieces[playerId] ?? []).filter((piece) => isValidMove(piece, game.diceValue));
  if (valid.length === 0) throw new HttpsError("data-loss", "The automated move has no legal piece.");
  valid.sort((left, right) => botPieceScore(game, playerId, right) - botPieceScore(game, playerId, left));
  const topScore = botPieceScore(game, playerId, valid[0]);
  const tied = valid.filter((piece) => botPieceScore(game, playerId, piece) === topScore);
  return tied[randomInt(0, tied.length)];
}

export async function processTurnTimeoutIntent(
  db: Firestore,
  caller: CallerIdentity,
  rawData: unknown,
  rollDie: DiceRoller = secureDiceRoll,
): Promise<ActionResult> {
  const intent = parseIntent(rawData);
  const roomRef = db.collection("games").doc(intent.roomCode);
  const resultRef = db.collection("matchResults").doc(intent.roomCode);
  return db.runTransaction(async (transaction: Transaction) => {
    const snapshot = await transaction.get(roomRef);
    if (!snapshot.exists) throw new HttpsError("not-found", "Room not found.");
    const game = parseGame(snapshot.data()!);
    assertParticipant(game, caller);
    ensurePlayable(game);
    const duplicate = duplicateResult(game, intent);
    if (duplicate) return duplicate;
    assertCurrentVersion(game, intent);
    const now = Timestamp.now();
    const expired = deadlineExpired(game, now);
    const rerollDecisionExpired = game.turnPhase === REROLL_DECISION_PHASE &&
      game.hasRolled && rerollWindowExpired(game, now);
    const automated = game.currentTurn.startsWith("bot_") || game.aiControlledPlayers.includes(game.currentTurn);
    if (!automated && !expired && !rerollDecisionExpired) {
      throw new HttpsError("failed-precondition", "No authoritative decision deadline has expired.");
    }
    if (game.turnPhase === "waitingForRoll" && !game.hasRolled) {
      const applied = applyRoll(
        game,
        caller.uid,
        intent.actionId,
        generatedDiceValue(rollDie),
        now,
        expired,
      );
      transaction.update(roomRef, applied.update);
      return applied.result;
    }
    if (game.turnPhase === REROLL_DECISION_PHASE && game.hasRolled) {
      const applied = applyNoValidMoveResolution(
        game,
        caller.uid,
        intent.actionId,
        now,
        expired,
      );
      transaction.update(roomRef, applied.update);
      return applied.result;
    }
    if (game.turnPhase === "waitingForMove" && game.hasRolled) {
      const chosen = chooseBotPiece(game, game.currentTurn);
      const applied = applyMove(game, caller.uid, intent.actionId, chosen.id, now, expired);
      transaction.update(roomRef, applied.update);
      if (applied.matchResult) transaction.set(resultRef, applied.matchResult, {merge: true});
      return applied.result;
    }
    throw new HttpsError("data-loss", "The turn phase is inconsistent.");
  });
}

function expectedSeatLayout(maxPlayers: number): number[] {
  if (maxPlayers === 3) return [0, 1, 2];
  if (maxPlayers === 4) return [0, 1, 2, 3];
  return [0, 2];
}

function defaultPieces(initialPos: number): Piece[] {
  return [1, 2, 3, 4].map((id) => ({id, pos: initialPos, inHome: false}));
}

export async function startGameIntent(
  db: Firestore,
  caller: CallerIdentity,
  rawData: unknown,
): Promise<ActionResult> {
  const intent = parseIntent(rawData);
  const roomRef = db.collection("games").doc(intent.roomCode);
  return db.runTransaction(async (transaction: Transaction) => {
    const snapshot = await transaction.get(roomRef);
    if (!snapshot.exists) throw new HttpsError("not-found", "Room not found.");
    const raw = snapshot.data()!;
    const players = stringArray(raw.players);
    if (!players.includes(caller.uid)) throw new HttpsError("permission-denied", "You are not in this room.");
    if (raw.hostUid !== caller.uid) throw new HttpsError("permission-denied", "Only the host can start the match.");
    if (raw.status !== "waiting") {
      if (raw.lastActionId === intent.actionId || stringArray(raw.recentActionIds).includes(intent.actionId)) {
        return {applied: false, duplicate: true, actionId: intent.actionId, turnVersion: Number(raw.turnVersion ?? 0)};
      }
      throw new HttpsError("failed-precondition", "The room is no longer waiting.");
    }
    const turnVersion = Number(raw.turnVersion ?? 0);
    if (turnVersion !== intent.expectedTurnVersion) throw new HttpsError("aborted", "The room changed before start.");
    const maxPlayers = Number(raw.maxPlayers ?? 2);
    const layout = expectedSeatLayout(maxPlayers);
    const seats = numberMap(raw.playerSeats);
    const names = stringMap(raw.playerNames);
    if (players.length !== maxPlayers || new Set(players.map((id) => seats[id])).size !== maxPlayers ||
        !layout.every((seat) => players.some((id) => seats[id] === seat))) {
      throw new HttpsError("failed-precondition", "The room is not ready or has malformed seats.");
    }
    if (players.some((id) => !names[id]?.trim())) {
      throw new HttpsError("failed-precondition", "Every participant must have a display name.");
    }
    const orderedPlayers = layout.map((seat) => players.find((id) => seats[id] === seat)!);
    const sandbox = raw.isTestModeActive === true;
    const knownBots = new Set(["bot_seat_0", "bot_seat_1", "bot_seat_2", "bot_seat_3"]);
    if (players.some((id) => id.startsWith("bot_") && !knownBots.has(id))) {
      throw new HttpsError("failed-precondition", "The room contains an invalid automated participant.");
    }
    if (sandbox) {
      if (!isSandboxOwnerToken(caller.token)) {
        throw new HttpsError("permission-denied", "Sandbox is restricted to the verified owner account.");
      }
      const humans = players.filter((id) => !id.startsWith("bot_"));
      if (humans.length !== 1 || humans[0] !== caller.uid) {
        throw new HttpsError("failed-precondition", "Sandbox matches must contain only the owner and bots.");
      }
    }
    const now = Timestamp.now();
    const nextVersion = turnVersion + 1;
    const pieces = Object.fromEntries(orderedPlayers.map((id) => [id, defaultPieces(sandbox ? 49 : -1)]));
    transaction.update(roomRef, {
      players: orderedPlayers,
      pieces,
      status: "playing",
      currentTurn: orderedPlayers[0],
      diceValue: 0,
      hasRolled: false,
      winnerUid: "",
      finishOrder: [],
      startedAt: now,
      finishedAt: null,
      activeMove: null,
      activeDiceRoll: null,
      rerollAvailableAt: null,
      rerollDeadlineAt: null,
      turnPhase: "waitingForRoll",
      ...turnTiming(now, ROLL_DECISION_SECONDS),
      turnVersion: nextVersion,
      rerollsUsed: {},
      rerollConfig: rerollPricingForStorage(DEFAULT_REROLL_PRICING),
      lastActionId: intent.actionId,
      lastActionType: "start",
      recentActionIds: [intent.actionId],
      aiControlledPlayers: [],
      pendingReconnectPlayers: [],
      forfeitedPlayers: [],
      automationLease: null,
      systemEvent: null,
      matchmakingOpen: false,
      openSeats: 0,
      ...activity(now),
    });
    return {applied: true, actionId: intent.actionId, actionType: "start", turnVersion: nextVersion};
  });
}

export async function requestTakeBackControlIntent(
  db: Firestore,
  caller: CallerIdentity,
  rawData: unknown,
): Promise<ActionResult> {
  const intent = parseIntent(rawData);
  const roomRef = db.collection("games").doc(intent.roomCode);
  return db.runTransaction(async (transaction: Transaction) => {
    const snapshot = await transaction.get(roomRef);
    if (!snapshot.exists) throw new HttpsError("not-found", "Room not found.");
    const game = parseGame(snapshot.data()!);
    assertParticipant(game, caller);
    ensurePlayable(game);
    const duplicate = duplicateResult(game, intent);
    if (duplicate) return duplicate;
    assertCurrentVersion(game, intent);
    if (game.forfeitedPlayers.includes(caller.uid)) {
      throw new HttpsError("failed-precondition", "A forfeited player cannot take back control.");
    }
    if (!game.aiControlledPlayers.includes(caller.uid)) {
      return {applied: false, actionId: intent.actionId, turnVersion: game.turnVersion};
    }
    const legacyInProgress = game.currentTurn === caller.uid &&
      ((game.activeMove && game.activeMove.stateApplied !== true) ||
       (game.activeDiceRoll && game.activeDiceRoll.stateApplied !== true));
    const now = Timestamp.now();
    if (legacyInProgress) {
      transaction.update(roomRef, {
        pendingReconnectPlayers: [...new Set([...game.pendingReconnectPlayers, caller.uid])],
        lastActionId: intent.actionId,
        lastActionType: "reconnectPending",
        recentActionIds: recentActions(game, intent.actionId),
        lastActivityAt: now,
      });
      return {applied: true, deferred: true, actionId: intent.actionId, turnVersion: game.turnVersion};
    }
    const nextVersion = game.turnVersion + 1;
    const update: Record<string, unknown> = {
      aiControlledPlayers: game.aiControlledPlayers.filter((id) => id !== caller.uid),
      pendingReconnectPlayers: game.pendingReconnectPlayers.filter((id) => id !== caller.uid),
      automationLease: null,
      systemEvent: {
        id: `reconnected_${caller.uid}_${nextVersion}`,
        type: "playerReconnected",
        playerId: caller.uid,
        createdAtMs: now.toMillis(),
      },
      lastActionId: intent.actionId,
      lastActionType: "reconnect",
      recentActionIds: recentActions(game, intent.actionId),
      lastActivityAt: now,
    };
    if (game.currentTurn === caller.uid) {
      Object.assign(update, {
        turnVersion: nextVersion,
        ...turnTiming(now, game.turnPhase === "waitingForMove" ? MOVE_DECISION_SECONDS : ROLL_DECISION_SECONDS),
      });
    }
    transaction.update(roomRef, update);
    return {applied: true, actionId: intent.actionId, turnVersion: game.currentTurn === caller.uid ? nextVersion : game.turnVersion};
  });
}

export async function forfeitMatchIntent(
  db: Firestore,
  caller: CallerIdentity,
  rawData: unknown,
): Promise<ActionResult> {
  const intent = parseIntent(rawData);
  const roomRef = db.collection("games").doc(intent.roomCode);
  return db.runTransaction(async (transaction: Transaction) => {
    const snapshot = await transaction.get(roomRef);
    if (!snapshot.exists) throw new HttpsError("not-found", "Room not found.");
    const game = parseGame(snapshot.data()!);
    assertParticipant(game, caller);
    ensurePlayable(game);
    const duplicate = duplicateResult(game, intent);
    if (duplicate) return duplicate;
    assertCurrentVersion(game, intent);
    if (game.finishOrder.includes(caller.uid)) {
      throw new HttpsError("failed-precondition", "A finished player cannot forfeit.");
    }
    const now = Timestamp.now();
    const nextVersion = game.turnVersion + 1;
    const update: Record<string, unknown> = {
      aiControlledPlayers: [...new Set([...game.aiControlledPlayers, caller.uid])],
      pendingReconnectPlayers: game.pendingReconnectPlayers.filter((id) => id !== caller.uid),
      forfeitedPlayers: [...new Set([...game.forfeitedPlayers, caller.uid])],
      systemEvent: {
        id: `forfeit_${caller.uid}_${nextVersion}`,
        type: "playerForfeited",
        playerId: caller.uid,
        createdAtMs: now.toMillis(),
      },
      lastActionId: intent.actionId,
      lastActionType: "forfeit",
      recentActionIds: recentActions(game, intent.actionId),
      lastActivityAt: now,
    };
    if (game.currentTurn === caller.uid) {
      Object.assign(update, {
        turnVersion: nextVersion,
        turnStartedAt: now,
        turnDurationSeconds: 0,
        turnDeadlineAt: now,
        automationLease: null,
      });
    }
    transaction.update(roomRef, update);
    return {applied: true, actionId: intent.actionId, turnVersion: game.currentTurn === caller.uid ? nextVersion : game.turnVersion};
  });
}

export async function recoverGameStateIntent(
  db: Firestore,
  caller: CallerIdentity,
  rawData: unknown,
): Promise<ActionResult> {
  const intent = parseIntent(rawData);
  const roomRef = db.collection("games").doc(intent.roomCode);
  return db.runTransaction(async (transaction: Transaction) => {
    const snapshot = await transaction.get(roomRef);
    if (!snapshot.exists) throw new HttpsError("not-found", "Room not found.");
    const game = parseGame(snapshot.data()!);
    assertParticipant(game, caller);
    ensurePlayable(game);
    const duplicate = duplicateResult(game, intent);
    if (duplicate) return duplicate;
    assertCurrentVersion(game, intent);
    const legacyAction = (game.activeMove && game.activeMove.stateApplied !== true) ||
      (game.activeDiceRoll && game.activeDiceRoll.stateApplied !== true);
    const missingDeadline = !game.turnStartedAt && !game.turnDeadlineAt;
    if (!legacyAction && !missingDeadline) {
      return {applied: false, actionId: intent.actionId, turnVersion: game.turnVersion};
    }
    const now = Timestamp.now();
    const nextVersion = game.turnVersion + 1;
    const phase = game.turnPhase === REROLL_DECISION_PHASE ?
      REROLL_DECISION_PHASE : game.hasRolled ? "waitingForMove" : "waitingForRoll";
    transaction.update(roomRef, {
      ...(legacyAction ? {activeMove: null, activeDiceRoll: null} : {}),
      automationLease: null,
      turnPhase: phase,
      ...turnTiming(now, phase === "waitingForMove" ? MOVE_DECISION_SECONDS : ROLL_DECISION_SECONDS),
      turnVersion: nextVersion,
      lastActionId: intent.actionId,
      lastActionType: "recovery",
      recentActionIds: recentActions(game, intent.actionId),
      lastActivityAt: now,
    });
    return {applied: true, actionId: intent.actionId, actionType: "recovery", turnVersion: nextVersion};
  });
}

export async function sandboxTeleportIntent(
  db: Firestore,
  caller: CallerIdentity,
  rawData: unknown,
): Promise<ActionResult> {
  if (!isSandboxOwnerToken(caller.token)) {
    throw new HttpsError("permission-denied", "Sandbox is restricted to the verified owner account.");
  }
  const intent = parseIntent(rawData);
  const map = rawData as Record<string, unknown>;
  const pieceId = Number(map.pieceId);
  const pos = Number(map.pos);
  const inHome = map.inHome === true;
  if (!Number.isInteger(pieceId) || pieceId < 1 || pieceId > 4 ||
      !Number.isInteger(pos) || (inHome ? pos < 0 || pos > 5 : pos < -1 || pos > 51)) {
    throw new HttpsError("invalid-argument", "Sandbox piece destination is malformed.");
  }
  const roomRef = db.collection("games").doc(intent.roomCode);
  return db.runTransaction(async (transaction: Transaction) => {
    const snapshot = await transaction.get(roomRef);
    if (!snapshot.exists) throw new HttpsError("not-found", "Room not found.");
    const game = parseGame(snapshot.data()!);
    assertParticipant(game, caller);
    if (!game.isTestModeActive) throw new HttpsError("failed-precondition", "This is not a Sandbox match.");
    const duplicate = duplicateResult(game, intent);
    if (duplicate) return duplicate;
    assertCurrentVersion(game, intent);
    const pieces = game.pieces[caller.uid];
    if (!pieces.some((piece) => piece.id === pieceId)) throw new HttpsError("not-found", "Piece not found.");
    transaction.update(roomRef, {
      [`pieces.${caller.uid}`]: pieces.map((piece) => piece.id === pieceId ? {...piece, pos, inHome} : piece),
      lastActionId: intent.actionId,
      lastActionType: "sandboxTeleport",
      recentActionIds: recentActions(game, intent.actionId),
      lastActivityAt: Timestamp.now(),
    });
    return {applied: true, actionId: intent.actionId, actionType: "sandboxTeleport", turnVersion: game.turnVersion};
  });
}

export function createInitialGameForTests(overrides: Partial<DocumentData> = {}): DocumentData {
  const players = ["player-a", "player-b"];
  return {
    players,
    playerNames: {"player-a": "A", "player-b": "B"},
    preferredColors: {"player-a": "blue", "player-b": "red"},
    playerSeats: {"player-a": 0, "player-b": 2},
    pieces: {"player-a": defaultPieces(-1), "player-b": defaultPieces(-1)},
    currentTurn: "player-a",
    diceValue: 0,
    hasRolled: false,
    status: "playing",
    winnerUid: "",
    finishOrder: [],
    boardId: "classic",
    isTestModeActive: false,
    maxPlayers: 2,
    turnPhase: "waitingForRoll",
    turnVersion: 1,
    rerollsUsed: {},
    rerollConfig: rerollPricingForStorage(DEFAULT_REROLL_PRICING),
    rerollAvailableAt: null,
    rerollDeadlineAt: null,
    lastActionId: "",
    recentActionIds: [],
    aiControlledPlayers: [],
    pendingReconnectPlayers: [],
    forfeitedPlayers: [],
    turnStartedAt: Timestamp.now(),
    turnDurationSeconds: 30,
    ...overrides,
  };
}
