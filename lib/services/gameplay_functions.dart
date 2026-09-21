import 'package:cloud_functions/cloud_functions.dart';

class GameplayFunctions {
  final FirebaseFunctions _functions;

  GameplayFunctions(this._functions);

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final result = await _functions.httpsCallable(name).call(data);
    final raw = result.data;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> rollDice({
    required String roomCode,
    required int expectedTurnVersion,
    required String actionId,
    int forcedValue = 0,
  }) {
    return _call('rollDice', {
      'roomCode': roomCode,
      'expectedTurnVersion': expectedTurnVersion,
      'actionId': actionId,
      if (forcedValue >= 1 && forcedValue <= 6) 'forcedValue': forcedValue,
    });
  }

  Future<Map<String, dynamic>> movePiece({
    required String roomCode,
    required int pieceId,
    required int expectedTurnVersion,
    required String actionId,
  }) {
    return _call('movePiece', {
      'roomCode': roomCode,
      'pieceId': pieceId,
      'expectedTurnVersion': expectedTurnVersion,
      'actionId': actionId,
    });
  }

  Future<Map<String, dynamic>> processTurnTimeout({
    required String roomCode,
    required int expectedTurnVersion,
    required String actionId,
  }) {
    return _call('processTurnTimeout', {
      'roomCode': roomCode,
      'expectedTurnVersion': expectedTurnVersion,
      'actionId': actionId,
    });
  }

  Future<Map<String, dynamic>> startGame({
    required String roomCode,
    required int expectedTurnVersion,
    required String actionId,
  }) {
    return _call('startGame', {
      'roomCode': roomCode,
      'expectedTurnVersion': expectedTurnVersion,
      'actionId': actionId,
    });
  }

  Future<Map<String, dynamic>> requestTakeBackControl({
    required String roomCode,
    required int expectedTurnVersion,
    required String actionId,
  }) {
    return _call('requestTakeBackControl', {
      'roomCode': roomCode,
      'expectedTurnVersion': expectedTurnVersion,
      'actionId': actionId,
    });
  }

  Future<Map<String, dynamic>> forfeitMatch({
    required String roomCode,
    required int expectedTurnVersion,
    required String actionId,
  }) {
    return _call('forfeitMatch', {
      'roomCode': roomCode,
      'expectedTurnVersion': expectedTurnVersion,
      'actionId': actionId,
    });
  }

  Future<Map<String, dynamic>> recoverGameState({
    required String roomCode,
    required int expectedTurnVersion,
    required String actionId,
  }) {
    return _call('recoverGameState', {
      'roomCode': roomCode,
      'expectedTurnVersion': expectedTurnVersion,
      'actionId': actionId,
    });
  }

  Future<Map<String, dynamic>> sandboxTeleportPiece({
    required String roomCode,
    required int pieceId,
    required int pos,
    required bool inHome,
    required int expectedTurnVersion,
    required String actionId,
  }) {
    return _call('sandboxTeleportPiece', {
      'roomCode': roomCode,
      'pieceId': pieceId,
      'pos': pos,
      'inHome': inHome,
      'expectedTurnVersion': expectedTurnVersion,
      'actionId': actionId,
    });
  }

  Future<Map<String, dynamic>> claimMatchReward(String matchId) {
    return _call('claimMatchReward', {'matchId': matchId});
  }

  Future<Map<String, dynamic>> prepareAccountTransfer() {
    return _call('prepareAccountTransfer', const {});
  }

  Future<Map<String, dynamic>> completeAccountTransfer({
    required String transferId,
    required String secret,
  }) {
    return _call('completeAccountTransfer', {
      'transferId': transferId,
      'secret': secret,
    });
  }
}
