import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/ludo_controller.dart';
import '../../game/ludo_presentation.dart';
import '../../models/ludo_models.dart';

/// Shows short local-only feedback after an already committed extra turn.
///
/// It observes presentation completion but never advances or writes game state.
class GameplayFeedbackOverlay extends StatefulWidget {
  final LudoController controller;
  final Widget child;

  const GameplayFeedbackOverlay({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<GameplayFeedbackOverlay> createState() =>
      _GameplayFeedbackOverlayState();
}

class _GameplayFeedbackOverlayState extends State<GameplayFeedbackOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  ActiveMove? _observedMove;
  ActiveDiceRoll? _observedRoll;
  ActiveMove? _pendingCompletedMove;
  ActiveDiceRoll? _pendingCompletedRoll;
  ExtraTurnReason? _reason;
  Timer? _reducedMotionTimer;
  bool _reduceMotion = false;
  bool _feedbackResolutionScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: LudoPresentation.extraTurnFeedbackDurationMs,
      ),
    )..addStatusListener(_handleAnimationStatus);
    _captureActivePresentations();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant GameplayFeedbackOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _observedMove = null;
      _observedRoll = null;
      _pendingCompletedMove = null;
      _pendingCompletedRoll = null;
      _dismissFeedback();
      _captureActivePresentations();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;

    if (_reason == null) return;
    if (_reduceMotion) {
      _controller
        ..stop()
        ..value = 1;
      _scheduleReducedMotionDismiss();
    } else {
      // Do not replay an effect just because the accessibility preference
      // changed while it was already on screen.
      _dismissFeedback();
    }
  }

  void _captureActivePresentations() {
    final game = widget.controller.game;
    final move = widget.controller.visualActiveMove;
    if (move != null) _observedMove = move;
    if (widget.controller.isDicePresentationActive &&
        game?.activeDiceRoll != null) {
      _observedRoll = game!.activeDiceRoll;
    }
  }

  void _handleControllerChanged() {
    final game = widget.controller.game;
    if (game == null) {
      _observedMove = null;
      _observedRoll = null;
      _pendingCompletedMove = null;
      _pendingCompletedRoll = null;
      _dismissFeedback();
      return;
    }

    final currentMove = widget.controller.visualActiveMove;
    if (currentMove != null) {
      _observedMove = currentMove;
    } else if (_observedMove != null) {
      _pendingCompletedMove = _observedMove;
      _observedMove = null;
    }

    final currentRoll = widget.controller.isDicePresentationActive
        ? game.activeDiceRoll
        : null;
    if (currentRoll != null) {
      _observedRoll = currentRoll;
    } else if (_observedRoll != null) {
      _pendingCompletedRoll = _observedRoll;
      _observedRoll = null;
    }

    if (LudoPresentation.shouldDismissExtraTurnFeedback(
          hasActiveMovePresentation: currentMove != null,
          hasActiveDicePresentation: currentRoll != null,
        ) &&
        _reason != null) {
      _dismissFeedback();
    }
    _schedulePendingFeedbackResolution();
  }

  void _schedulePendingFeedbackResolution() {
    if (_feedbackResolutionScheduled) return;
    _feedbackResolutionScheduled = true;
    scheduleMicrotask(() {
      _feedbackResolutionScheduled = false;
      if (!mounted) return;
      final latestGame = widget.controller.game;
      if (latestGame != null) _resolvePendingFeedback(latestGame);
    });
  }

  void _resolvePendingFeedback(LudoGame game) {
    final completedMove = _pendingCompletedMove;
    if (completedMove != null &&
        (completedMove.turnVersion == 0 ||
            game.turnVersion >= completedMove.turnVersion)) {
      _pendingCompletedMove = null;
      if (_belongsToLocalHuman(game, completedMove.playerId) &&
          LudoPresentation.isCurrentActionForFeedback(
            actionTurnVersion: completedMove.turnVersion,
            currentTurnVersion: game.turnVersion,
            lastActionType: game.lastActionType,
            expectedActionType: 'move',
          )) {
        final reason = LudoPresentation.extraTurnReasonAfterMove(
          move: completedMove,
          authoritativeTurnPlayerId: game.currentTurn,
          matchFinished: game.status == 'finished',
          movingPlayerFinished: game.finishOrder.contains(
            completedMove.playerId,
          ),
        );
        if (reason != null) _showReason(reason);
      }
    }

    final completedRoll = _pendingCompletedRoll;
    if (completedRoll != null &&
        (completedRoll.turnVersion == 0 ||
            game.turnVersion >= completedRoll.turnVersion)) {
      _pendingCompletedRoll = null;
      if (_belongsToLocalHuman(game, completedRoll.playerId) &&
          LudoPresentation.isCurrentActionForFeedback(
            actionTurnVersion: completedRoll.turnVersion,
            currentTurnVersion: game.turnVersion,
            lastActionType: game.lastActionType,
            expectedActionType: 'dice',
          )) {
        final reason = LudoPresentation.extraTurnReasonAfterRoll(
          roll: completedRoll,
          authoritativeTurnPlayerId: game.currentTurn,
          matchFinished: game.status == 'finished',
          hasValidMove: game.hasRolled,
        );
        if (reason != null) _showReason(reason);
      }
    }
  }

  bool _belongsToLocalHuman(LudoGame game, String actionPlayerId) {
    return LudoPresentation.shouldShowLocalExtraTurnFeedback(
      actionPlayerId: actionPlayerId,
      localPlayerId: widget.controller.user?.uid ?? '',
      actionPlayerIsAiControlled: game.isAiControlled(actionPlayerId),
    );
  }

  void _showReason(ExtraTurnReason reason) {
    _reducedMotionTimer?.cancel();
    _controller.stop();
    if (!mounted) return;
    setState(() => _reason = reason);

    if (_reduceMotion) {
      _controller.value = 1;
      _scheduleReducedMotionDismiss();
    } else {
      _controller.forward(from: 0);
    }
  }

  void _scheduleReducedMotionDismiss() {
    _reducedMotionTimer?.cancel();
    _reducedMotionTimer = Timer(
      const Duration(
        milliseconds: LudoPresentation.extraTurnFeedbackDurationMs,
      ),
      () {
        _reducedMotionTimer = null;
        if (mounted) setState(() => _reason = null);
      },
    );
  }

  void _dismissFeedback() {
    _reducedMotionTimer?.cancel();
    _reducedMotionTimer = null;
    _controller
      ..stop()
      ..value = 0;
    if (_reason != null && mounted) setState(() => _reason = null);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && !_reduceMotion) {
      setState(() => _reason = null);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _reducedMotionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (_reason != null)
          Positioned(
            top: 10,
            left: 28,
            right: 28,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  if (_reduceMotion) return child!;
                  final progress = _controller.value;
                  const fadeInEnd =
                      180 / LudoPresentation.extraTurnFeedbackDurationMs;
                  const fadeOutStart =
                      (LudoPresentation.extraTurnFeedbackDurationMs - 220) /
                      LudoPresentation.extraTurnFeedbackDurationMs;
                  final opacity = progress < fadeInEnd
                      ? Curves.easeOut.transform(progress / fadeInEnd)
                      : progress > fadeOutStart
                      ? 1 -
                            Curves.easeIn.transform(
                              (progress - fadeOutStart) / (1 - fadeOutStart),
                            )
                      : 1.0;
                  final entrance = Curves.easeOutBack.transform(
                    (progress / fadeInEnd).clamp(0.0, 1.0),
                  );
                  return Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.94 + entrance * 0.06,
                      child: child,
                    ),
                  );
                },
                child: _ExtraTurnCard(reason: _reason!),
              ),
            ),
          ),
      ],
    );
  }
}

class _ExtraTurnCard extends StatelessWidget {
  final ExtraTurnReason reason;

  const _ExtraTurnCard({required this.reason});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (reason) {
      ExtraTurnReason.six => (Icons.casino_rounded, 'Six! Roll again'),
      ExtraTurnReason.capture => (
        Icons.flash_on_rounded,
        'Capture! Roll again',
      ),
      ExtraTurnReason.goal => (Icons.emoji_events_rounded, 'Goal! Roll again'),
    };

    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xee111827),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xffffd166), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: const Color(0xffffd166).withOpacity(0.22),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: const Color(0xffffd166)),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
