import {expect} from "chai";

import {HttpsError} from "firebase-functions/v2/https";

import {
  isSandboxOwnerToken,
  requireAuthUid,
  requireSandboxOwner,
  SANDBOX_OWNER_EMAIL,
} from "../src/auth";

describe("Sandbox authorization", () => {
  it("accepts only the verified owner email", () => {
    expect(isSandboxOwnerToken({email: SANDBOX_OWNER_EMAIL, email_verified: true})).to.equal(true);
    expect(isSandboxOwnerToken({email: SANDBOX_OWNER_EMAIL.toUpperCase(), email_verified: true})).to.equal(true);
  });

  it("rejects other, unverified, and missing identities", () => {
    expect(isSandboxOwnerToken({email: "other@example.com", email_verified: true})).to.equal(false);
    expect(isSandboxOwnerToken({email: SANDBOX_OWNER_EMAIL, email_verified: false})).to.equal(false);
    expect(isSandboxOwnerToken(undefined)).to.equal(false);
  });

  it("rejects unauthenticated and non-owner callable identities", () => {
    expect(() => requireAuthUid(undefined)).to.throw(HttpsError).with.property("code", "unauthenticated");
    expect(() => requireSandboxOwner({
      uid: "other",
      token: {email: "other@example.com", email_verified: true},
    })).to.throw(HttpsError).with.property("code", "permission-denied");
    expect(() => requireSandboxOwner({
      uid: "owner",
      token: {email: SANDBOX_OWNER_EMAIL, email_verified: true},
    })).not.to.throw();
  });
});
