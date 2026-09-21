export const BASE_POSITION = -1;
export const OUTER_TRACK_LAST_POSITION = 51;
export const GOAL_POSITION = 5;
export const SAFE_GLOBAL_POSITIONS = new Set([3, 8, 11, 16, 21, 24, 29, 34, 37, 42, 47, 50]);
export const START_OFFSETS = [11, 24, 37, 50] as const;

export interface Piece {
  id: number;
  pos: number;
  inHome: boolean;
}

export interface MoveStep {
  pos: number;
  inHome: boolean;
}

export interface MoveCapture {
  playerId: string;
  pieceId: number;
  from: MoveStep;
}

export interface CaptureResult {
  pieces: Record<string, Piece[]>;
  didCapture: boolean;
  capturedPieces: MoveCapture[];
}

export function isValidMove(piece: Piece, diceValue: number): boolean {
  if (!Number.isInteger(diceValue) || diceValue < 1 || diceValue > 6) return false;
  if (piece.inHome && piece.pos === GOAL_POSITION) return false;
  if (piece.pos === BASE_POSITION) return diceValue === 6;
  if (piece.inHome) return piece.pos + diceValue <= GOAL_POSITION;
  return piece.pos >= 0 && piece.pos <= OUTER_TRACK_LAST_POSITION;
}

export function hasValidMove(pieces: readonly Piece[], diceValue: number): boolean {
  return pieces.some((piece) => isValidMove(piece, diceValue));
}

export function buildMoveSteps(piece: Piece, diceValue: number): MoveStep[] {
  if (!isValidMove(piece, diceValue)) return [];
  const steps: MoveStep[] = [{pos: piece.pos, inHome: piece.inHome}];
  let remaining = piece.pos === BASE_POSITION ? 1 : diceValue;
  let position = piece.pos;
  let inHome = piece.inHome;
  while (remaining-- > 0) {
    if (position === BASE_POSITION) {
      position = 0;
      inHome = false;
    } else if (inHome) {
      position += 1;
    } else {
      position += 1;
      if (position > OUTER_TRACK_LAST_POSITION) {
        position = 0;
        inHome = true;
      }
    }
    steps.push({pos: position, inHome});
  }
  return steps;
}

export function destination(piece: Piece, diceValue: number): MoveStep {
  const steps = buildMoveSteps(piece, diceValue);
  return steps.length === 0 ? {pos: piece.pos, inHome: piece.inHome} : steps[steps.length - 1];
}

export function reachesGoal(before: Piece, after: MoveStep): boolean {
  return after.inHome && after.pos === GOAL_POSITION && !(before.inHome && before.pos === GOAL_POSITION);
}

export function hasCompletedAllPieces(pieces: readonly Piece[]): boolean {
  return pieces.length > 0 && pieces.every((piece) => piece.inHome && piece.pos === GOAL_POSITION);
}

export function grantsExtraTurn(diceValue: number, didCapture: boolean, didReachGoal: boolean): boolean {
  return diceValue === 6 || didCapture || didReachGoal;
}

export function nextActivePlayer(
  players: readonly string[],
  currentPlayerId: string,
  finishedPlayers: readonly string[],
): string {
  if (players.length === 0) return "";
  const finished = new Set(finishedPlayers);
  const currentIndex = players.indexOf(currentPlayerId);
  const startIndex = currentIndex < 0 ? -1 : currentIndex;
  for (let offset = 1; offset <= players.length; offset += 1) {
    const candidate = players[(startIndex + offset) % players.length];
    if (!finished.has(candidate)) return candidate;
  }
  return "";
}

export function resolveNoValidMove(
  players: readonly string[],
  currentPlayerId: string,
  finishedPlayers: readonly string[],
  diceValue: number,
): {nextPlayerId: string; keepsTurn: boolean} {
  const keepsTurn = diceValue === 6;
  return {
    nextPlayerId: keepsTurn ? currentPlayerId : nextActivePlayer(players, currentPlayerId, finishedPlayers),
    keepsTurn,
  };
}

export function finishOrderAfterMove(
  players: readonly string[],
  currentFinishOrder: readonly string[],
  movingPlayerId: string,
  movingPlayerFinished: boolean,
): string[] {
  const result: string[] = [];
  for (const playerId of currentFinishOrder) {
    if (players.includes(playerId) && !result.includes(playerId)) result.push(playerId);
  }
  if (movingPlayerFinished && !result.includes(movingPlayerId)) result.push(movingPlayerId);
  const unfinished = players.filter((id) => !result.includes(id));
  if (movingPlayerFinished && unfinished.length === 1) result.push(unfinished[0]);
  return result;
}

export function isMatchFinished(players: readonly string[], finishOrder: readonly string[]): boolean {
  return players.length >= 2 && finishOrder.length === players.length;
}

export function globalPathIndexForSeat(seatIndex: number, relativePos: number): number {
  const safeSeat = Math.max(0, Math.min(3, Math.trunc(seatIndex)));
  return (START_OFFSETS[safeSeat] - relativePos + 52) % 52;
}

function seatFor(players: readonly string[], playerSeats: Record<string, number>, playerId: string): number {
  const rawSeat = playerSeats[playerId] ?? players.indexOf(playerId);
  return Math.max(0, Math.min(3, Math.trunc(rawSeat)));
}

export function applyCaptures(
  pieces: Record<string, Piece[]>,
  playerSeats: Record<string, number>,
  players: readonly string[],
  movingPlayerId: string,
  moveDestination: MoveStep,
): CaptureResult {
  const updated = Object.fromEntries(
    Object.entries(pieces).map(([id, values]) => [id, values.map((piece) => ({...piece}))]),
  );
  if (moveDestination.inHome) return {pieces: updated, didCapture: false, capturedPieces: []};
  const movingSeat = seatFor(players, playerSeats, movingPlayerId);
  const globalDestination = globalPathIndexForSeat(movingSeat, moveDestination.pos);
  if (SAFE_GLOBAL_POSITIONS.has(globalDestination)) {
    return {pieces: updated, didCapture: false, capturedPieces: []};
  }

  const capturedPieces: MoveCapture[] = [];
  for (const opponentId of players) {
    if (opponentId === movingPlayerId) continue;
    const opponentSeat = seatFor(players, playerSeats, opponentId);
    updated[opponentId] = (updated[opponentId] ?? []).map((piece) => {
      if (piece.pos === BASE_POSITION || piece.inHome) return piece;
      if (globalPathIndexForSeat(opponentSeat, piece.pos) !== globalDestination) return piece;
      capturedPieces.push({
        playerId: opponentId,
        pieceId: piece.id,
        from: {pos: piece.pos, inHome: piece.inHome},
      });
      return {...piece, pos: BASE_POSITION, inHome: false};
    });
  }
  return {pieces: updated, didCapture: capturedPieces.length > 0, capturedPieces};
}
