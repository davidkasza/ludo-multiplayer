import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {setGlobalOptions} from "firebase-functions/v2";
import {CallableRequest, onCall} from "firebase-functions/v2/https";

import {requireAuthUid} from "./auth";
import {
  CallerIdentity,
  forfeitMatchIntent,
  movePieceIntent,
  passNoValidMoveIntent,
  processTurnTimeoutIntent,
  recoverGameStateIntent,
  requestTakeBackControlIntent,
  rollDiceIntent,
  sandboxTeleportIntent,
  startGameIntent,
  useRerollIntent,
} from "./game_service";
import {
  claimMatchRewardIntent,
  completeAccountTransferIntent,
  prepareAccountTransferIntent,
} from "./progression";

initializeApp();
const db = getFirestore();

setGlobalOptions({
  region: "europe-west1",
  memory: "256MiB",
  minInstances: 0,
  maxInstances: 10,
  timeoutSeconds: 20,
});

const callableOptions = {
  enforceAppCheck: false,
  consumeAppCheckToken: false,
} as const;

function caller(request: CallableRequest<unknown>): CallerIdentity {
  return {
    uid: requireAuthUid(request.auth),
    token: request.auth?.token as Record<string, unknown> | undefined,
  };
}

export const rollDice = onCall(callableOptions, (request) =>
  rollDiceIntent(db, caller(request), request.data));

export const movePiece = onCall(callableOptions, (request) =>
  movePieceIntent(db, caller(request), request.data));

export const useReroll = onCall(callableOptions, (request) =>
  useRerollIntent(db, caller(request), request.data));

export const passNoValidMove = onCall(callableOptions, (request) =>
  passNoValidMoveIntent(db, caller(request), request.data));

export const processTurnTimeout = onCall(callableOptions, (request) =>
  processTurnTimeoutIntent(db, caller(request), request.data));

export const startGame = onCall(callableOptions, (request) =>
  startGameIntent(db, caller(request), request.data));

export const requestTakeBackControl = onCall(callableOptions, (request) =>
  requestTakeBackControlIntent(db, caller(request), request.data));

export const forfeitMatch = onCall(callableOptions, (request) =>
  forfeitMatchIntent(db, caller(request), request.data));

export const recoverGameState = onCall(callableOptions, (request) =>
  recoverGameStateIntent(db, caller(request), request.data));

export const sandboxTeleportPiece = onCall(callableOptions, (request) =>
  sandboxTeleportIntent(db, caller(request), request.data));

export const claimMatchReward = onCall(callableOptions, (request) =>
  claimMatchRewardIntent(db, requireAuthUid(request.auth), request.data));

export const prepareAccountTransfer = onCall(callableOptions, (request) =>
  prepareAccountTransferIntent(db, requireAuthUid(request.auth)));

export const completeAccountTransfer = onCall(callableOptions, (request) =>
  completeAccountTransferIntent(db, requireAuthUid(request.auth), request.data));
