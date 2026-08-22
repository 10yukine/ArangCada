import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';

/// Hold-to-record, matching the gesture every mainstream chat app uses.
///
/// `GestureDetector`'s long-press callbacks fire after exactly Flutter's
/// default long-press timeout -- 500ms, which is the "hold for at least half
/// a second" the button is supposed to require, so no custom timer is
/// needed. While held, dragging up past [cancelThreshold] before release
/// cancels instead of sending.
///
/// No microphone is actually opened here -- see [onRecorded]'s doc comment.
class VoiceRecordButton extends StatefulWidget {
  const VoiceRecordButton({
    required this.onRecorded,
    this.cancelThreshold = 80,
    super.key,
  });

  /// Called with the held duration once the gesture ends as a send, not a
  /// cancel. The caller decides what a "voice message" becomes -- this
  /// widget only knows about the gesture, not about recording audio.
  final ValueChanged<Duration> onRecorded;
  final double cancelThreshold;

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  bool _recording = false;
  bool _willCancel = false;
  double _dragUp = 0;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  void _start(Offset _) {
    setState(() {
      _recording = true;
      _willCancel = false;
      _dragUp = 0;
      _startedAt = DateTime.now();
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _startedAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt!));
    });
  }

  void _updateDrag(LongPressMoveUpdateDetails details) {
    // Only upward movement counts; dragging back down un-cancels, matching
    // how every app with this gesture behaves.
    final up = (-details.localOffsetFromOrigin.dy).clamp(
      0.0,
      widget.cancelThreshold,
    );
    setState(() {
      _dragUp = up;
      _willCancel = up >= widget.cancelThreshold;
    });
  }

  void _end([LongPressEndDetails? _]) {
    _ticker?.cancel();
    final cancelled = _willCancel;
    final duration = _elapsed;
    setState(() {
      _recording = false;
      _willCancel = false;
      _dragUp = 0;
      _startedAt = null;
      _elapsed = Duration.zero;
    });
    if (!cancelled && duration.inMilliseconds > 0) {
      widget.onRecorded(duration);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mic = Semantics(
      button: true,
      label: 'Hold to record a voice message',
      child: GestureDetector(
        onLongPressStart: (details) => _start(details.localPosition),
        onLongPressMoveUpdate: _updateDrag,
        onLongPressEnd: _end,
        onLongPressCancel: () => _end(),
        child: Material(
          color: _recording
              ? (_willCancel ? AppColors.dangerFill : AppColors.primary)
              : AppColors.primary,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              _willCancel ? Icons.delete_outline : Icons.mic_none_rounded,
              size: 20,
              color: _willCancel ? AppColors.dangerDark : Colors.white,
            ),
          ),
        ),
      ),
    );

    if (!_recording) return mic;

    // The recording overlay sits above the mic, anchored to it, so the
    // composer's layout does not jump while held.
    //
    // The Stack's own box is only as wide as `mic` (44px), sitting near the
    // screen's right edge. Centering the bubble on that 44px anchor -- the
    // previous `alignment: Alignment.center` -- put roughly half its actual
    // content width past the screen edge, clipping "Slide up to cancel" mid
    // word. Anchoring its right edge to the mic's right edge instead lets it
    // grow left into the composer row's real space, which is where the room
    // actually is.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          bottom: 52,
          right: 0,
          child: _RecordingBubble(
            elapsed: _elapsed,
            dragUp: _dragUp,
            cancelThreshold: widget.cancelThreshold,
            willCancel: _willCancel,
          ),
        ),
        mic,
      ],
    );
  }
}

class _RecordingBubble extends StatelessWidget {
  const _RecordingBubble({
    required this.elapsed,
    required this.dragUp,
    required this.cancelThreshold,
    required this.willCancel,
  });

  final Duration elapsed;
  final double dragUp;
  final double cancelThreshold;
  final bool willCancel;

  @override
  Widget build(BuildContext context) {
    final seconds = elapsed.inSeconds;
    final label = '${(seconds ~/ 60).toString().padLeft(1, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    // The bubble itself rises with the drag, matching finger position 1:1,
    // so cancelling reads as a direct-manipulation gesture rather than a
    // separate progress meter reacting to it.
    return Transform.translate(
      offset: Offset(0, -dragUp * 0.6),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: willCancel ? AppColors.dangerFill : AppColors.ink,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              willCancel ? Icons.delete_outline : Icons.fiber_manual_record,
              size: 14,
              color: willCancel ? AppColors.dangerDark : AppColors.danger,
            ),
            const SizedBox(width: 6),
            Text(
              willCancel ? 'Release to cancel' : label,
              style: AppTypography.bodySm.copyWith(
                color: willCancel ? AppColors.dangerDark : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!willCancel) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 16,
                color: Colors.white70,
              ),
              const Text(
                'Slide up to cancel',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
