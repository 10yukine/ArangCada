import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';

/// Hold-to-record, matching the gesture every mainstream chat app uses.
///
/// `GestureDetector`'s long-press callbacks fire after exactly Flutter's
/// default long-press timeout -- 500ms, which is the "hold for at least half
/// a second" grace period a quick, accidental tap needs to not register at
/// all. Releasing after that already sends immediately, with no extra delay
/// added -- see [_end].
///
/// CANCEL GESTURE, REDESIGNED: cancelling used to be an all-or-nothing pixel
/// threshold -- drag exactly [cancelThreshold] px up and the button flips
/// state right at the boundary, with no feedback building up to that point.
/// Reported as "slide up to cancel is not working" -- the mechanism itself
/// fired correctly, but nothing on screen made the approaching cancel legible
/// until the instant it happened, so it read as broken rather than abrupt.
/// The drag progress (0 at no movement, 1 at cancelThreshold) now drives a
/// continuous fade: full opacity at rest, fading out linearly as the finger
/// rises, decided as a cancel once progress crosses [cancelDecisionProgress]
/// (75%, so "roughly three-quarters transparent" and "about to be
/// interpreted as a cancel" are the same visual moment, not two unrelated
/// facts the user has to remember separately).
///
/// No microphone is actually opened here -- see [onRecorded]'s doc comment.
class VoiceRecordButton extends StatefulWidget {
  const VoiceRecordButton({
    required this.onRecorded,
    this.cancelThreshold = 80,
    this.cancelDecisionProgress = 0.75,
    super.key,
  });

  /// Called with the held duration once the gesture ends as a send, not a
  /// cancel. The caller decides what a "voice message" becomes -- this
  /// widget only knows about the gesture, not about recording audio.
  final ValueChanged<Duration> onRecorded;
  final double cancelThreshold;

  /// Fraction of [cancelThreshold] (0-1) the drag must cross before release
  /// is interpreted as a cancel rather than a send. 0.75 means the bubble
  /// has faded to roughly a quarter of its original opacity at the exact
  /// point the decision flips -- the fade IS the threshold indicator, not a
  /// separate thing next to it.
  final double cancelDecisionProgress;

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton>
    with TickerProviderStateMixin {
  bool _recording = false;
  bool _willCancel = false;
  double _dragUp = 0;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  // Idle "held and recording" pulse -- a slow, continuous breathing scale on
  // the mic circle so a still finger still reads as "actively recording",
  // not "the app froze". Runs only while _recording; the drag-driven fade
  // is a separate, gesture-controlled value and deliberately not animated by
  // this controller, so a fast flick up is not fighting a slow pulse.
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final Animation<double> _pulseScale = Tween<double>(
    begin: 1.0,
    end: 1.08,
  ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

  double get _dragProgress =>
      widget.cancelThreshold <= 0 ? 0 : (_dragUp / widget.cancelThreshold).clamp(0.0, 1.0);

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
    // Only upward movement counts; dragging back down un-cancels and fades
    // back in, matching how every app with this gesture behaves.
    final up = (-details.localOffsetFromOrigin.dy).clamp(
      0.0,
      widget.cancelThreshold,
    );
    final progress = widget.cancelThreshold <= 0
        ? 0.0
        : (up / widget.cancelThreshold).clamp(0.0, 1.0);
    setState(() {
      _dragUp = up;
      _willCancel = progress >= widget.cancelDecisionProgress;
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
    // Sends the instant the gesture ends as a release, not a cancel -- no
    // additional delay beyond the 500ms long-press grace period that already
    // gated whether this callback fires at all.
    if (!cancelled && duration.inMilliseconds > 0) {
      widget.onRecorded(duration);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulseController.dispose();
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
        child: AnimatedScale(
          // The button itself grows slightly the instant a hold registers,
          // a quick, separate cue from the slower recording pulse below --
          // together they read as "you started something" then "it is
          // ongoing", rather than one animation trying to say both.
          scale: _recording ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: ScaleTransition(
            scale: _recording ? _pulseScale : const AlwaysStoppedAnimation(1.0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _recording
                    ? (_willCancel ? AppColors.dangerFill : AppColors.primary)
                    : AppColors.primary,
              ),
              width: 44,
              height: 44,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  _willCancel ? Icons.delete_outline : Icons.mic_none_rounded,
                  key: ValueKey(_willCancel),
                  size: 20,
                  color: _willCancel ? AppColors.dangerDark : Colors.white,
                ),
              ),
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
            dragProgress: _dragProgress,
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
    required this.dragProgress,
    required this.willCancel,
  });

  final Duration elapsed;

  /// 0 at rest, 1 at the drag ceiling. Drives both the rise and the fade --
  /// the fade IS the cancel-threshold indicator (see the class doc comment
  /// on [VoiceRecordButton]), not a decoration next to a separate one.
  final double dragProgress;
  final bool willCancel;

  @override
  Widget build(BuildContext context) {
    final seconds = elapsed.inSeconds;
    final label = '${(seconds ~/ 60).toString().padLeft(1, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    // Once the cancel decision has flipped, hold opacity at a fixed low
    // value rather than continuing to fade toward zero -- "Release to
    // cancel" must stay legible. Below the decision point, opacity eases
    // from 1.0 down to ~0.25 as dragProgress approaches
    // cancelDecisionProgress, so the fade visibly finishes exactly where the
    // decision flips instead of the two feeling like separate mechanics.
    final opacity = willCancel ? 0.45 : (1.0 - dragProgress * 0.75).clamp(0.25, 1.0);
    // The bubble itself rises with the drag, matching finger position 1:1,
    // so cancelling reads as a direct-manipulation gesture rather than a
    // separate progress meter reacting to it.
    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 80),
      child: Transform.translate(
        offset: Offset(0, -dragProgress * 48),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
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
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  willCancel ? Icons.delete_outline : Icons.fiber_manual_record,
                  key: ValueKey(willCancel),
                  size: 14,
                  color: willCancel ? AppColors.dangerDark : AppColors.danger,
                ),
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
      ),
    );
  }
}
