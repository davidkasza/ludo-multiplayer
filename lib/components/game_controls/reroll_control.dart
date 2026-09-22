import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/ludo_controller.dart';
import '../../theme/app_colors.dart';

/// Fixed trailing area of the turn card. Its size does not depend on whether
/// the temporary Reroll action is visible, so the board cannot move.
class TurnActionSlot extends StatelessWidget {
  final Widget dice;
  final Widget? reroll;

  const TurnActionSlot({super.key, required this.dice, this.reroll});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('turn-action-slot'),
      width: 110,
      height: 42,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(right: 0, top: 0, child: dice),
          Positioned(
            right: 47,
            top: 4,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child:
                  reroll ??
                  const SizedBox(
                    key: ValueKey('reroll-action-empty'),
                    width: 63,
                    height: 34,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class RerollControl extends StatelessWidget {
  final LudoController controller;

  const RerollControl({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final availableAt = controller.game?.rerollAvailableAt?.toDate();
    final deadlineAt = controller.game?.rerollDeadlineAt?.toDate();
    final cost = controller.currentRerollCost;
    final actionKey = controller.currentRerollActionKey;
    if (!controller.shouldShowRerollControl ||
        availableAt == null ||
        deadlineAt == null ||
        cost == null ||
        actionKey == null) {
      return const SizedBox.shrink();
    }

    return CompactRerollAction(
      key: ValueKey('reroll-$actionKey'),
      actionKey: actionKey,
      price: cost,
      availableAt: availableAt,
      deadlineAt: deadlineAt,
      serverNow: controller.estimatedServerNow,
      onPressed: controller.useReroll,
    );
  }
}

/// Presentation-only Reroll affordance. Backend timestamps define the window;
/// this local controller only paints its remaining fraction.
class CompactRerollAction extends StatefulWidget {
  final String actionKey;
  final int price;
  final DateTime availableAt;
  final DateTime deadlineAt;
  final DateTime serverNow;
  final Future<String?> Function() onPressed;

  const CompactRerollAction({
    super.key,
    required this.actionKey,
    required this.price,
    required this.availableAt,
    required this.deadlineAt,
    required this.serverNow,
    required this.onPressed,
  });

  @override
  State<CompactRerollAction> createState() => _CompactRerollActionState();
}

class _CompactRerollActionState extends State<CompactRerollAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  Timer? _reducedMotionExpiry;
  bool _expired = false;
  bool _submitting = false;
  bool? _lastReduceMotion;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_lastReduceMotion != reduceMotion) {
      _lastReduceMotion = reduceMotion;
      _startExpiry(reduceMotion: reduceMotion);
    }
  }

  @override
  void didUpdateWidget(covariant CompactRerollAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actionKey != widget.actionKey ||
        oldWidget.availableAt != widget.availableAt ||
        oldWidget.deadlineAt != widget.deadlineAt) {
      _startExpiry(reduceMotion: _lastReduceMotion ?? false);
    }
  }

  void _startExpiry({required bool reduceMotion}) {
    _reducedMotionExpiry?.cancel();
    _progressController.stop();
    _expired = false;

    final total = widget.deadlineAt.difference(widget.availableAt);
    final remaining = widget.deadlineAt.difference(widget.serverNow);
    if (total <= Duration.zero || remaining <= Duration.zero) {
      _expired = true;
      _progressController.value = 1;
      return;
    }

    final elapsedFraction =
        1 - (remaining.inMicroseconds / total.inMicroseconds);
    _progressController.value = elapsedFraction.clamp(0.0, 1.0);
    if (reduceMotion) {
      _reducedMotionExpiry = Timer(remaining, _markExpired);
      return;
    }

    _progressController.duration = remaining;
    _progressController.forward().whenComplete(_markExpired);
  }

  void _markExpired() {
    if (!mounted || _expired) return;
    setState(() => _expired = true);
  }

  Future<void> _submit() async {
    if (_expired || _submitting) return;
    setState(() => _submitting = true);
    final errorMessage = await widget.onPressed();
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _expired = true;
    });
    if (errorMessage == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: const Color(0xff991b1b),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  void dispose() {
    _reducedMotionExpiry?.cancel();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_expired) return const SizedBox(width: 63, height: 34);

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: 'Reroll for ${widget.price} coins',
      child: SizedBox(
        key: const ValueKey('reroll-action'),
        width: 63,
        height: 34,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              OutlinedButton(
                onPressed: _submitting ? null : _submit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.yellowBright,
                  backgroundColor: AppColors.background.withOpacity(0.94),
                  disabledForegroundColor: Colors.white38,
                  side: BorderSide(
                    color: AppColors.yellowBright.withOpacity(0.55),
                  ),
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _submitting
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        '↻ ${widget.price}',
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
              if (!reduceMotion)
                Positioned(
                  left: 5,
                  right: 5,
                  bottom: 2,
                  height: 2,
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, _) => LinearProgressIndicator(
                        value: 1 - _progressController.value,
                        backgroundColor: Colors.transparent,
                        color: AppColors.yellowBright.withOpacity(0.75),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
