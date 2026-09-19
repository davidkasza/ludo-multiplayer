import 'dart:async';

import 'package:flutter/material.dart';

import '../../game/ludo_presentation.dart';
import '../../models/ludo_models.dart';

/// Temporary board-local quick-chat presentation.
///
/// New messages replace the current bubble and reset its short lifetime. Stale
/// RTDB `latest` values are ignored when reconnecting or changing rooms.
class QuickChatBubble extends StatefulWidget {
  final String roomId;
  final LudoChat? chat;
  final int? nowMs;
  final int senderSeat;
  final String senderName;
  final Color color;

  const QuickChatBubble({
    super.key,
    required this.roomId,
    required this.chat,
    this.nowMs,
    required this.senderSeat,
    required this.senderName,
    required this.color,
  });

  @override
  State<QuickChatBubble> createState() => _QuickChatBubbleState();
}

class _QuickChatBubbleState extends State<QuickChatBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  Timer? _hideTimer;
  String? _lastIdentity;
  LudoChat? _visibleChat;
  String _visibleSenderName = '';
  Color _visibleColor = Colors.white;
  int _visibleSeat = 0;
  bool _reduceMotion = false;
  bool _dependenciesReady = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),
    )..addStatusListener(_handleStatus);
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion && !_reduceMotion && _visibleChat != null) {
      _controller
        ..stop()
        ..value = 1;
    }
    _reduceMotion = reduceMotion;
    if (!_dependenciesReady) {
      _dependenciesReady = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _considerMessage();
      });
    }
  }

  @override
  void didUpdateWidget(covariant QuickChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _lastIdentity = null;
      _hideImmediately();
    }
    _considerMessage();
  }

  void _considerMessage() {
    final chat = widget.chat;
    if (chat == null || widget.roomId.isEmpty) return;
    final identity =
        '${widget.roomId}:${chat.timestamp}:${chat.sender}:${chat.message}';
    if (_lastIdentity == identity) return;
    _lastIdentity = identity;

    if (!LudoPresentation.shouldPresentQuickChat(
      chat: chat,
      nowMs: widget.nowMs ?? DateTime.now().millisecondsSinceEpoch,
    )) {
      return;
    }

    _hideTimer?.cancel();
    setState(() {
      _visibleChat = chat;
      _visibleSenderName = widget.senderName;
      _visibleColor = widget.color;
      _visibleSeat = widget.senderSeat.clamp(0, 3);
    });

    if (_reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
    _hideTimer = Timer(const Duration(milliseconds: 2700), () {
      if (!mounted) return;
      if (_reduceMotion) {
        setState(() => _visibleChat = null);
      } else {
        _controller.reverse();
      }
    });
  }

  void _hideImmediately() {
    _hideTimer?.cancel();
    _controller.stop();
    _controller.value = 0;
    if (_visibleChat != null && mounted) {
      setState(() => _visibleChat = null);
    } else {
      _visibleChat = null;
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed &&
        _visibleChat != null &&
        mounted) {
      setState(() => _visibleChat = null);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = _visibleChat;
    if (chat == null) return const SizedBox.shrink();

    final alignment = switch (_visibleSeat) {
      0 => const Alignment(-0.72, -0.62),
      1 => const Alignment(0.72, -0.62),
      2 => const Alignment(0.72, 0.62),
      _ => const Alignment(-0.72, 0.62),
    };
    final bubble = Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xf21f2937),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: _visibleColor.withOpacity(0.72)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.30),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _visibleSenderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _visibleColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  chat.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (_reduceMotion) return IgnorePointer(child: bubble);
    return IgnorePointer(
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(position: _slide, child: bubble),
      ),
    );
  }
}
