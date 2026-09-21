import {createHash, randomBytes} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";

export const SANDBOX_OWNER_EMAIL = "kaszadavid1998@gmail.com";

type TokenLike = Record<string, unknown>;

export interface AuthIdentity {
  uid: string;
  token: TokenLike;
}

export function isSandboxOwnerToken(token: TokenLike | undefined): boolean {
  if (!token) return false;
  const email = typeof token.email === "string" ? token.email.trim().toLowerCase() : "";
  return email === SANDBOX_OWNER_EMAIL && token.email_verified === true;
}

export function requireAuthUid(auth: AuthIdentity | undefined): string {
  if (!auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in before performing this action.");
  }
  return auth.uid;
}

export function requireSandboxOwner(auth: AuthIdentity | undefined): void {
  requireAuthUid(auth);
  if (!isSandboxOwnerToken(auth?.token as TokenLike | undefined)) {
    throw new HttpsError(
      "permission-denied",
      "Sandbox mode is restricted to the verified owner account.",
    );
  }
}

export function newTransferSecret(): string {
  return randomBytes(32).toString("base64url");
}

export function hashTransferSecret(secret: string): string {
  return createHash("sha256").update(secret).digest("hex");
}
