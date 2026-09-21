import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {expect} from "chai";

import {
  applyCaptures,
  buildMoveSteps,
  finishOrderAfterMove,
  grantsExtraTurn,
  isValidMove,
  nextActivePlayer,
  Piece,
  resolveNoValidMove,
} from "../src/ludo_rules";

describe("server Ludo rules", () => {
  const fixture = JSON.parse(readFileSync(
    resolve(__dirname, "../../../test/fixtures/ludo_rules_cases.json"),
    "utf8",
  )) as {
    validMoves: Array<{piece: Piece; dice: number; valid: boolean}>;
    destinations: Array<{piece: Piece; dice: number; pos: number; inHome: boolean}>;
  };

  it("matches the shared move fixtures", () => {
    for (const entry of fixture.validMoves) {
      expect(isValidMove(entry.piece, entry.dice)).to.equal(entry.valid);
    }
    for (const entry of fixture.destinations) {
      const steps = buildMoveSteps(entry.piece, entry.dice);
      expect(steps.at(-1)).to.deep.equal({pos: entry.pos, inHome: entry.inHome});
    }
  });

  it("captures stacked opponents only on unsafe squares", () => {
    const captured = applyCaptures(
      {
        a: [{id: 1, pos: 1, inHome: false}],
        b: [{id: 2, pos: 27, inHome: false}, {id: 3, pos: 27, inHome: false}],
      },
      {a: 0, b: 2},
      ["a", "b"],
      "a",
      {pos: 1, inHome: false},
    );
    expect(captured.capturedPieces.map((item) => item.pieceId)).to.deep.equal([2, 3]);
    expect(captured.pieces.b.every((piece) => piece.pos === -1)).to.equal(true);

    const safe = applyCaptures(
      {a: [{id: 1, pos: 3, inHome: false}], b: [{id: 1, pos: 29, inHome: false}]},
      {a: 0, b: 2},
      ["a", "b"],
      "a",
      {pos: 3, inHome: false},
    );
    expect(safe.didCapture).to.equal(false);
  });

  it("keeps Dart-compatible turn, extra-turn, and finish behavior", () => {
    expect(grantsExtraTurn(6, false, false)).to.equal(true);
    expect(grantsExtraTurn(2, true, false)).to.equal(true);
    expect(grantsExtraTurn(2, false, true)).to.equal(true);
    expect(nextActivePlayer(["a", "b", "c", "d"], "a", ["b", "c"])).to.equal("d");
    expect(resolveNoValidMove(["a", "b"], "a", [], 6)).to.deep.equal({nextPlayerId: "a", keepsTurn: true});
    expect(finishOrderAfterMove(["a", "b", "c"], ["a"], "b", true)).to.deep.equal(["a", "b", "c"]);
  });
});
