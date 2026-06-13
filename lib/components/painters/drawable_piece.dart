import 'package:flutter/material.dart';

import '../../models/ludo_models.dart';

class DrawablePiece {
  final String playerId;
  final int playerIndex;
  final LudoPiece piece;
  final bool isCurrentPlayer;
  final bool isSharedMoving;
  final Offset center;
  final Color colorBright;
  final Color colorDark;

  const DrawablePiece({
    required this.playerId,
    required this.playerIndex,
    required this.piece,
    required this.isCurrentPlayer,
    required this.isSharedMoving,
    required this.center,
    required this.colorBright,
    required this.colorDark,
  });
}