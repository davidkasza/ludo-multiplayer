import '../models/ludo_models.dart';
import 'classic_board.dart';

/// Pure, deterministic Ludo rules shared by the UI, bots, and persistence
/// layer. This class deliberately has no Firebase or Flutter dependencies.
class LudoRules {
  const LudoRules._();

  static const int basePosition = -1;
  static const int outerTrackLastPosition = 51;
  static const int goalPosition = 5;

  static const Set<int> safeGlobalPositions = {
    3,
    8,
    11,
    16,
    21,
    24,
    29,
    34,
    37,
    42,
    47,
    50,
  };

  static bool isValidMove(LudoPiece piece, int diceValue) {
    if (diceValue < 1 || diceValue > 6) return false;
    if (piece.inHome && piece.pos == goalPosition) return false;
    if (piece.pos == basePosition) return diceValue == 6;
    if (piece.inHome) return piece.pos + diceValue <= goalPosition;
    return piece.pos >= 0 && piece.pos <= outerTrackLastPosition;
  }

  static bool hasValidMove(Iterable<LudoPiece> pieces, int diceValue) {
    return pieces.any((piece) => isValidMove(piece, diceValue));
  }

  static List<ActiveMoveStep> buildMoveSteps(LudoPiece piece, int diceValue) {
    if (!isValidMove(piece, diceValue)) return const <ActiveMoveStep>[];

    final steps = <ActiveMoveStep>[
      ActiveMoveStep(pos: piece.pos, inHome: piece.inHome),
    ];
    var remaining = piece.pos == basePosition ? 1 : diceValue;
    var position = piece.pos;
    var inHome = piece.inHome;

    while (remaining-- > 0) {
      if (position == basePosition) {
        position = 0;
        inHome = false;
      } else if (inHome) {
        position++;
      } else {
        position++;
        if (position > outerTrackLastPosition) {
          position = 0;
          inHome = true;
        }
      }
      steps.add(ActiveMoveStep(pos: position, inHome: inHome));
    }

    return steps;
  }

  static ActiveMoveStep destination(LudoPiece piece, int diceValue) {
    final steps = buildMoveSteps(piece, diceValue);
    return steps.isEmpty
        ? ActiveMoveStep(pos: piece.pos, inHome: piece.inHome)
        : steps.last;
  }

  static bool reachesGoal(LudoPiece before, ActiveMoveStep after) {
    return after.inHome &&
        after.pos == goalPosition &&
        !(before.inHome && before.pos == goalPosition);
  }

  static bool hasCompletedAllPieces(Iterable<LudoPiece> pieces) {
    return pieces.isNotEmpty &&
        pieces.every((piece) => piece.inHome && piece.pos == goalPosition);
  }

  static bool grantsExtraTurn({
    required int diceValue,
    required bool didCapture,
    required bool didReachGoal,
  }) {
    return diceValue == 6 || didCapture || didReachGoal;
  }

  static String nextActivePlayer({
    required List<String> players,
    required String currentPlayerId,
    required Iterable<String> finishedPlayers,
  }) {
    if (players.isEmpty) return '';
    final finished = finishedPlayers.toSet();
    final currentIndex = players.indexOf(currentPlayerId);
    final startIndex = currentIndex < 0 ? -1 : currentIndex;

    for (var offset = 1; offset <= players.length; offset++) {
      final candidate = players[(startIndex + offset) % players.length];
      if (!finished.contains(candidate)) return candidate;
    }
    return '';
  }

  static NoValidMoveTurn resolveNoValidMove({
    required List<String> players,
    required String currentPlayerId,
    required Iterable<String> finishedPlayers,
    required int diceValue,
  }) {
    final keepsTurn = diceValue == 6;
    return NoValidMoveTurn(
      nextPlayerId: keepsTurn
          ? currentPlayerId
          : nextActivePlayer(
              players: players,
              currentPlayerId: currentPlayerId,
              finishedPlayers: finishedPlayers,
            ),
      keepsTurn: keepsTurn,
    );
  }

  static List<String> finishOrderAfterMove({
    required List<String> players,
    required Iterable<String> currentFinishOrder,
    required String movingPlayerId,
    required bool movingPlayerFinished,
  }) {
    final result = <String>[];
    for (final playerId in currentFinishOrder) {
      if (players.contains(playerId) && !result.contains(playerId)) {
        result.add(playerId);
      }
    }
    if (movingPlayerFinished && !result.contains(movingPlayerId)) {
      result.add(movingPlayerId);
    }

    final unfinished = players.where((id) => !result.contains(id)).toList();
    if (movingPlayerFinished && unfinished.length == 1) {
      result.add(unfinished.single);
    }
    return result;
  }

  static bool isMatchFinished({
    required List<String> players,
    required List<String> finishOrder,
  }) {
    return players.length >= 2 && finishOrder.length == players.length;
  }

  static CaptureResult applyCaptures({
    required Map<String, List<LudoPiece>> pieces,
    required Map<String, int> playerSeats,
    required List<String> players,
    required String movingPlayerId,
    required ActiveMoveStep destination,
  }) {
    final updated = <String, List<LudoPiece>>{
      for (final entry in pieces.entries)
        entry.key: List<LudoPiece>.from(entry.value),
    };
    if (destination.inHome) {
      return CaptureResult(pieces: updated, didCapture: false);
    }

    final movingSeat = _seatFor(players, playerSeats, movingPlayerId);
    final globalDestination = ClassicBoard.globalPathIndexForSeat(
      movingSeat,
      destination.pos,
    );
    if (safeGlobalPositions.contains(globalDestination)) {
      return CaptureResult(pieces: updated, didCapture: false);
    }

    var didCapture = false;
    final capturedPieces = <ActiveMoveCapture>[];
    for (final opponentId in players) {
      if (opponentId == movingPlayerId) continue;
      final opponentSeat = _seatFor(players, playerSeats, opponentId);
      updated[opponentId] = (updated[opponentId] ?? const <LudoPiece>[]).map((
        piece,
      ) {
        if (piece.pos == basePosition || piece.inHome) return piece;
        final globalPosition = ClassicBoard.globalPathIndexForSeat(
          opponentSeat,
          piece.pos,
        );
        if (globalPosition != globalDestination) return piece;
        didCapture = true;
        capturedPieces.add(
          ActiveMoveCapture(
            playerId: opponentId,
            pieceId: piece.id,
            from: ActiveMoveStep(pos: piece.pos, inHome: piece.inHome),
          ),
        );
        return piece.copyWith(pos: basePosition, inHome: false);
      }).toList();
    }
    return CaptureResult(
      pieces: updated,
      didCapture: didCapture,
      capturedPieces: capturedPieces,
    );
  }

  static bool needsLegacyActionRecovery(LudoGame game) {
    return needsActionRecovery(
      activeDiceRoll: game.activeDiceRoll,
      activeMove: game.activeMove,
    );
  }

  static bool needsActionRecovery({
    ActiveDiceRoll? activeDiceRoll,
    ActiveMove? activeMove,
  }) {
    return (activeDiceRoll != null && !activeDiceRoll.stateApplied) ||
        (activeMove != null && !activeMove.stateApplied);
  }

  static int _seatFor(
    List<String> players,
    Map<String, int> playerSeats,
    String playerId,
  ) {
    return (playerSeats[playerId] ?? players.indexOf(playerId))
        .clamp(0, 3)
        .toInt();
  }
}

class CaptureResult {
  final Map<String, List<LudoPiece>> pieces;
  final bool didCapture;
  final List<ActiveMoveCapture> capturedPieces;

  const CaptureResult({
    required this.pieces,
    required this.didCapture,
    this.capturedPieces = const <ActiveMoveCapture>[],
  });
}

class NoValidMoveTurn {
  final String nextPlayerId;
  final bool keepsTurn;

  const NoValidMoveTurn({required this.nextPlayerId, required this.keepsTurn});
}
