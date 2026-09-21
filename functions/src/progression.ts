import {randomUUID, timingSafeEqual} from "node:crypto";
import {FieldValue, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {hashTransferSecret, newTransferSecret} from "./auth";

interface Reward {
  xp: number;
  coins: number;
}

interface ProgressionConfig {
  version: number;
  enabled: boolean;
  sandboxRewardsEnabled: boolean;
  aiOnlyMultiplierPercent: number;
  matchCompleted: Reward;
  humanOpponentBonus: Reward;
  placements: Record<number, Reward>;
}

const DEFAULT_CONFIG: ProgressionConfig = {
  version: 1,
  enabled: true,
  sandboxRewardsEnabled: false,
  aiOnlyMultiplierPercent: 25,
  matchCompleted: {xp: 20, coins: 5},
  humanOpponentBonus: {xp: 15, coins: 5},
  placements: {
    1: {xp: 30, coins: 10},
    2: {xp: 20, coins: 6},
    3: {xp: 10, coins: 3},
    4: {xp: 5, coins: 1},
  },
};

function safeInteger(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.trunc(value) : fallback;
}

function reward(value: unknown, fallback: Reward): Reward {
  if (!value || typeof value !== "object" || Array.isArray(value)) return fallback;
  const map = value as Record<string, unknown>;
  return {
    xp: Math.max(0, safeInteger(map.xp, fallback.xp)),
    coins: Math.max(0, safeInteger(map.coins, fallback.coins)),
  };
}

function configFrom(raw: unknown): ProgressionConfig {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return DEFAULT_CONFIG;
  const map = raw as Record<string, unknown>;
  const rewards = map.rewards && typeof map.rewards === "object" && !Array.isArray(map.rewards)
    ? map.rewards as Record<string, unknown> : {};
  const placements = {...DEFAULT_CONFIG.placements};
  const rawPlacements = rewards.placements;
  if (rawPlacements && typeof rawPlacements === "object" && !Array.isArray(rawPlacements)) {
    for (const [key, value] of Object.entries(rawPlacements)) {
      const placement = Number(key);
      if (Number.isInteger(placement) && placement >= 1 && placement <= 4) {
        placements[placement] = reward(value, placements[placement] ?? {xp: 0, coins: 0});
      }
    }
  }
  return {
    version: Math.max(1, safeInteger(map.version, DEFAULT_CONFIG.version)),
    enabled: typeof map.enabled === "boolean" ? map.enabled : DEFAULT_CONFIG.enabled,
    sandboxRewardsEnabled: typeof map.sandboxRewardsEnabled === "boolean"
      ? map.sandboxRewardsEnabled : DEFAULT_CONFIG.sandboxRewardsEnabled,
    aiOnlyMultiplierPercent: Math.max(0, Math.min(100,
      safeInteger(map.aiOnlyMultiplierPercent, DEFAULT_CONFIG.aiOnlyMultiplierPercent))),
    matchCompleted: reward(rewards.matchCompleted, DEFAULT_CONFIG.matchCompleted),
    humanOpponentBonus: reward(rewards.humanOpponentBonus, DEFAULT_CONFIG.humanOpponentBonus),
    placements,
  };
}

function add(left: Reward, right: Reward): Reward {
  return {xp: left.xp + right.xp, coins: left.coins + right.coins};
}

function calculateReward(
  config: ProgressionConfig,
  placement: number,
  humanPlayerCount: number,
  sandbox: boolean,
): Reward {
  if (!config.enabled || (sandbox && !config.sandboxRewardsEnabled)) return {xp: 0, coins: 0};
  let value = add(config.matchCompleted, config.placements[placement] ?? {xp: 0, coins: 0});
  if (humanPlayerCount >= 2) value = add(value, config.humanOpponentBonus);
  else {
    value = {
      xp: Math.round(value.xp * config.aiOnlyMultiplierPercent / 100),
      coins: Math.round(value.coins * config.aiOnlyMultiplierPercent / 100),
    };
  }
  return value;
}

export async function claimMatchRewardIntent(
  db: Firestore,
  uid: string,
  rawData: unknown,
): Promise<Record<string, unknown>> {
  const data = rawData && typeof rawData === "object" ? rawData as Record<string, unknown> : {};
  const matchId = typeof data.matchId === "string" ? data.matchId.trim() : "";
  if (!/^[A-Za-z0-9_-]{5,200}$/.test(matchId)) {
    throw new HttpsError("invalid-argument", "matchId is malformed.");
  }
  const resultRef = db.collection("matchResults").doc(matchId);
  const configRef = db.collection("appConfig").doc("progression");
  const userRef = db.collection("users").doc(uid);
  const claimRef = userRef.collection("rewardClaims").doc(matchId);
  return db.runTransaction(async (transaction: Transaction) => {
    const existingClaim = await transaction.get(claimRef);
    if (existingClaim.exists) {
      const existing = existingClaim.data() ?? {};
      return {
        awarded: false,
        duplicate: true,
        xp: safeInteger(existing.xp, 0),
        coins: safeInteger(existing.coins, 0),
      };
    }
    const [resultSnapshot, configSnapshot, profileSnapshot] = await Promise.all([
      transaction.get(resultRef),
      transaction.get(configRef),
      transaction.get(userRef),
    ]);
    if (!resultSnapshot.exists) throw new HttpsError("not-found", "Match result not found.");
    const result = resultSnapshot.data()!;
    if (result.authorityVersion !== 1) {
      throw new HttpsError(
        "failed-precondition",
        "Legacy client-authored results are not eligible for new rewards.",
      );
    }
    const participants = Array.isArray(result.participantIds)
      ? result.participantIds.filter((id: unknown): id is string => typeof id === "string") : [];
    const ranking = Array.isArray(result.ranking)
      ? result.ranking.filter((id: unknown): id is string => typeof id === "string") : [];
    if (!participants.includes(uid)) throw new HttpsError("permission-denied", "You did not participate in this match.");
    const placementIndex = ranking.indexOf(uid);
    if (placementIndex < 0) throw new HttpsError("failed-precondition", "The match ranking is incomplete.");
    const config = configFrom(configSnapshot.data());
    const placement = placementIndex + 1;
    const humanPlayerCount = Math.max(0, safeInteger(result.humanPlayerCount, participants.length));
    const sandbox = result.isTestModeActive === true;
    const awarded = calculateReward(config, placement, humanPlayerCount, sandbox);
    const now = Timestamp.now();
    transaction.set(userRef, {
      ...(!profileSnapshot.exists ? {
        displayName: "",
        activeGameId: "",
        createdAt: now,
      } : {}),
      xp: FieldValue.increment(awarded.xp),
      coins: FieldValue.increment(awarded.coins),
      rewardedMatches: FieldValue.increment(1),
      ...(placement === 1 ? {rewardedWins: FieldValue.increment(1)} : {}),
      ...(placement <= 3 ? {rewardedPodiums: FieldValue.increment(1)} : {}),
      progressionConfigVersion: config.version,
      lastRewardAt: now,
      updatedAt: now,
    }, {merge: true});
    transaction.create(claimRef, {
      matchId,
      placement,
      humanPlayerCount,
      isSandbox: sandbox,
      xp: awarded.xp,
      coins: awarded.coins,
      configVersion: config.version,
      claimedAt: now,
    });
    return {awarded: true, xp: awarded.xp, coins: awarded.coins, placement};
  });
}

export async function prepareAccountTransferIntent(
  db: Firestore,
  sourceUid: string,
): Promise<{transferId: string; secret: string}> {
  const transferId = randomUUID();
  const secret = newTransferSecret();
  const now = Timestamp.now();
  await db.collection("accountTransfers").doc(transferId).create({
    sourceUid,
    secretHash: hashTransferSecret(secret),
    createdAt: now,
    expiresAt: Timestamp.fromMillis(now.toMillis() + 10 * 60 * 1000),
    claimedBy: "",
    completedAt: null,
  });
  return {transferId, secret};
}

function secretsMatch(expectedHash: string, suppliedSecret: string): boolean {
  const suppliedHash = hashTransferSecret(suppliedSecret);
  const left = Buffer.from(expectedHash, "hex");
  const right = Buffer.from(suppliedHash, "hex");
  return left.length === right.length && timingSafeEqual(left, right);
}

export async function completeAccountTransferIntent(
  db: Firestore,
  targetUid: string,
  rawData: unknown,
): Promise<Record<string, unknown>> {
  const data = rawData && typeof rawData === "object" ? rawData as Record<string, unknown> : {};
  const transferId = typeof data.transferId === "string" ? data.transferId : "";
  const secret = typeof data.secret === "string" ? data.secret : "";
  if (!/^[0-9a-f-]{36}$/.test(transferId) || secret.length < 32 || secret.length > 128) {
    throw new HttpsError("invalid-argument", "Account transfer credentials are malformed.");
  }
  const transferRef = db.collection("accountTransfers").doc(transferId);
  const sourceUid = await db.runTransaction(async (transaction: Transaction) => {
    const snapshot = await transaction.get(transferRef);
    if (!snapshot.exists) throw new HttpsError("not-found", "Account transfer not found.");
    const transfer = snapshot.data()!;
    if (transfer.completedAt != null && transfer.claimedBy === targetUid) return String(transfer.sourceUid);
    if (!(transfer.expiresAt instanceof Timestamp) || transfer.expiresAt.toMillis() < Date.now()) {
      throw new HttpsError("deadline-exceeded", "The account transfer has expired.");
    }
    if (typeof transfer.secretHash !== "string" || !secretsMatch(transfer.secretHash, secret)) {
      throw new HttpsError("permission-denied", "Invalid account transfer secret.");
    }
    if (transfer.claimedBy && transfer.claimedBy !== targetUid) {
      throw new HttpsError("permission-denied", "This account transfer was claimed by another account.");
    }
    if (transfer.sourceUid === targetUid) throw new HttpsError("failed-precondition", "Source and target accounts are identical.");
    transaction.update(transferRef, {claimedBy: targetUid, claimedAt: Timestamp.now()});
    return String(transfer.sourceUid);
  });

  const [sourceProfileSnapshot, targetProfileSnapshot, sourceHistory, sourceClaims] = await Promise.all([
    db.collection("users").doc(sourceUid).get(),
    db.collection("users").doc(targetUid).get(),
    db.collection("matchResults").where("participantIds", "array-contains", sourceUid).get(),
    db.collection("users").doc(sourceUid).collection("rewardClaims").get(),
  ]);
  const sourceProfile = sourceProfileSnapshot.data() ?? {};
  const targetProfile = targetProfileSnapshot.data() ?? {};
  const targetName = typeof targetProfile.displayName === "string" ? targetProfile.displayName.trim() : "";
  const sourceName = typeof sourceProfile.displayName === "string" ? sourceProfile.displayName.trim() : "";
  await db.runTransaction(async (transaction: Transaction) => {
    const targetRef = db.collection("users").doc(targetUid);
    const mergeRef = targetRef.collection("accountMerges").doc(sourceUid);
    const [latestTarget, mergeSnapshot] = await Promise.all([
      transaction.get(targetRef),
      transaction.get(mergeRef),
    ]);
    const completedTransfers = Array.isArray(latestTarget.get("completedAccountTransfers"))
      ? latestTarget.get("completedAccountTransfers").filter((value: unknown): value is string => typeof value === "string")
      : [];
    const mergedSourceUids = Array.isArray(latestTarget.get("mergedSourceUids"))
      ? latestTarget.get("mergedSourceUids").filter((value: unknown): value is string => typeof value === "string")
      : [];
    const sourceAlreadyMerged = mergeSnapshot.exists || mergedSourceUids.includes(sourceUid);
    transaction.set(targetRef, {
      ...(!latestTarget.exists ? {createdAt: Timestamp.now()} : {}),
      ...(!targetName && sourceName ? {displayName: sourceName} : {}),
      ...(!targetProfile.diceSkinId && typeof sourceProfile.diceSkinId === "string"
        ? {diceSkinId: sourceProfile.diceSkinId} : {}),
      ...(!sourceAlreadyMerged ? {
        xp: FieldValue.increment(Math.max(0, safeInteger(sourceProfile.xp, 0))),
        coins: FieldValue.increment(Math.max(0, safeInteger(sourceProfile.coins, 0))),
        rewardedMatches: FieldValue.increment(Math.max(0, safeInteger(sourceProfile.rewardedMatches, 0))),
        rewardedWins: FieldValue.increment(Math.max(0, safeInteger(sourceProfile.rewardedWins, 0))),
        rewardedPodiums: FieldValue.increment(Math.max(0, safeInteger(sourceProfile.rewardedPodiums, 0))),
        mergedSourceUids: [...mergedSourceUids, sourceUid].slice(-50),
      } : {}),
      completedAccountTransfers: [...new Set([...completedTransfers, transferId])].slice(-20),
      updatedAt: Timestamp.now(),
    }, {merge: true});
    if (!mergeSnapshot.exists) {
      transaction.create(mergeRef, {
        sourceUid,
        transferId,
        mergedAt: Timestamp.now(),
      });
    }
  });

  const writes: Array<{path: string; data: Record<string, unknown>}> = [];
  for (const document of sourceHistory.docs) {
    const value = document.data();
    const replace = (raw: unknown): string[] => Array.isArray(raw)
      ? [...new Set(raw.filter((item): item is string => typeof item === "string").map((id) => id === sourceUid ? targetUid : id))]
      : [];
    const replaceMap = (raw: unknown): Record<string, unknown> => {
      const result = raw && typeof raw === "object" && !Array.isArray(raw) ? {...raw as Record<string, unknown>} : {};
      if (Object.prototype.hasOwnProperty.call(result, sourceUid)) {
        if (!Object.prototype.hasOwnProperty.call(result, targetUid)) result[targetUid] = result[sourceUid];
        delete result[sourceUid];
      }
      return result;
    };
    writes.push({
      path: `matchResults/${document.id}__merged__${sourceUid}`,
      data: {
        ...value,
        participantIds: replace(value.participantIds),
        ranking: replace(value.ranking),
        playerNames: replaceMap(value.playerNames),
        preferredColors: replaceMap(value.preferredColors),
        playerSeats: replaceMap(value.playerSeats),
        originalMatchId: document.id,
        mergedFromUid: sourceUid,
        mergedIntoUid: targetUid,
        mergedAt: Timestamp.now(),
      },
    });
  }
  for (const document of sourceClaims.docs) {
    writes.push({
      path: `users/${targetUid}/rewardClaims/${document.id}__merged__${sourceUid}`,
      data: {
        ...document.data(),
        originalMatchId: document.id,
        mergedFromUid: sourceUid,
        mergedIntoUid: targetUid,
        mergedAt: Timestamp.now(),
      },
    });
  }
  for (let offset = 0; offset < writes.length; offset += 400) {
    const batch = db.batch();
    for (const write of writes.slice(offset, offset + 400)) batch.set(db.doc(write.path), write.data, {merge: true});
    await batch.commit();
  }
  await transferRef.set({completedAt: Timestamp.now()}, {merge: true});
  return {completed: true, copiedMatches: sourceHistory.size, copiedClaims: sourceClaims.size};
}
