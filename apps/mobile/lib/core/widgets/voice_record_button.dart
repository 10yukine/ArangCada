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
/// CANCEL GESTURE: drag up at least [cancelDecisionProgress] of
/// [cancelThreshold] (25% of 80px by default -- a short, easy flick, not a
/// long deliberate drag) and releasing cancels instead of sending. The drag
/// progress (0 at no movement, 1 at cancelThreshold) drives two things
/// continuously as the finger rises, so the approaching cancel is legible
/// before it happens rather than flipping abruptly at the boundary: the
/// bubble **shrinks** (1.0 down to 0.55 scale) and fades (1.0 down to 0.25
/// opacity). Both bottom out at the same point the decision flips, so
/// "visibly smaller and fainter" and "about to be interpreted as a cancel"
/// read as the same moment rather than two facts to remember separately.
///
/// No microphone is actually opened here -- see [onRecorded]'s doc comment.
class VoiceRecordButton extends StatefulWidget {
  const VoiceRecordButton({
    required this.onRecorded,
    this.cancelThreshold = 80,
    this.cancelDecisionProgress = 0.25,
    super.key,
  });

  /// Called with the held duration once the gesture ends as a send, not a
  /// cancel. The caller decides what a "voice message" becomes -- this
  /// widget only knows about the gesture, not about recording audio.
  final ValueChanged<Duration> onRecorded;
  final double cancelThreshold;

  /// Fraction of [cancelThreshold] (0-1) the drag must cross before release
  /// is interpreted as a cancel rather than a send. 0.25 means roughly a
  /// quarter of the full drag distance -- "at least 25% away" cancels --
  /// which is the point the bubble's shrink-and-fade also bottoms out at.
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
  // not "the app froze". Runs only while _recording (started in [_start],
  // stopped in [_end]); the drag-driven shrink/fade is a separate,
  // gesture-controlled value and deliberately not animated by this
  // controller, so a fast flick up is not fighting a slow pulse.
  //
  // Built in initState(), not as a `late final ... = AnimationController(...)`
  // field initializer. That pattern only constructs the controller on first
  // READ, and if a hold never actually starts recording (a quick tap that
  // does not clear the long-press timeout, or the widget being torn down
  // before ever recording), the first read becomes dispose()'s own
  // `_pulseController.dispose()` call -- constructing an AnimationController
  // there needs a `vsync` ancestor lookup, and the element is already
  // deactivated by then, crashing with "Looking up a deactivated widget's
  // ancestor is unsafe." Every real render path (send a text message with
  // the mic visible but untouched, back out of chat without ever holding
  // it) hit this. Eager construction in initState() means dispose() always
  // disposes something that genuinely exists.
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

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
    _pulseController.repeat(reverse: true);
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _startedAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt!));
    });
  }

  void _updateDrag(LongPressMoveUpdateDetails details) {
    // Only upward movement counts; dragging back down un-cancels and shrinks
    // back to full size, matching how every app with this gesture behaves.
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
    _pulseController.stop();
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
    // Keyed, and always the LAST child of an ALWAYS-PRESENT Stack below --
    // see the comment on that Stack for why this specific shape is load
    // bearing, not decorative.
    final mic = Semantics(
      key: const ValueKey('voice-record-mic'),
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

    // ALWAYS a Stack with `mic` as the last child -- never an
    // `if (!_recording) return mic;` early return that swaps the whole
    // returned widget between a bare Semantics tree and a Stack containing
    // one. THAT was a real, severe bug: the moment a hold was recognized and
    // this rebuilt with a *differently shaped* tree, Flutter's element
    // reconciliation saw the child type at this State's position change
    // (Semantics -> Stack) and tore down the in-flight GestureDetector's
    // Element -- disposing the very LongPressGestureRecognizer that was
    // actively tracking the user's still-down finger -- and mounted a brand
    // new one that was never registered for that pointer. Every event after
    // the initial onLongPressStart (the drag-to-cancel updates, and even
    // release itself) then went nowhere: the recording UI would appear and
    // then never respond to anything, including lifting the finger. Keeping
    // the Stack (and `mic`'s keyed position as its last child) permanent
    // regardless of `_recording`, and only conditionally including the
    // bubble as an earlier sibling, keeps the GestureDetector's Element --
    // and the live recognizer underneath it -- alive across the entire
    // gesture.
    //
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
        if (_recording)
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

  /// 0 at rest, 1 at the drag ceiling. Drives the rise, the shrink, and the
  /// fade together -- see the class doc comment on [VoiceRecordButton].
  final double dragProgress;
  final bool willCancel;

  @override
  Widget build(BuildContext context) {
    final seconds = elapsed.inSeconds;
    final label = '${(seconds ~/ 60).toString().padLeft(1, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    // Once the cancel decision has flipped, hold opacity and scale at their
    // floor rather than continuing toward zero -- "Release to cancel" must
    // stay legible and tappable-looking, not vanish. Below the decision
    // point, both ease from their rest value toward that floor as
    // dragProgress rises, so the shrink-and-fade visibly finishes exactly
    // where the decision flips instead of the two feeling like separate
    // mechanics.
    final opacity = willCancel ? 0.45 : (1.0 - dragProgress * 0.75).clamp(0.25, 1.0);
    final scale = willCancel ? 0.55 : (1.0 - dragProgress * 0.45).clamp(0.55, 1.0);
    // The bubble itself rises with the drag, matching finger position 1:1,
    // so cancelling reads as a direct-manipulation gesture rather than a
    // separate progress meter reacting to it.
    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 80),
      child: Transform.translate(
        offset: Offset(0, -dragProgress * 48),
        child: Transform.scale(
          // Shrinks toward the mic anchor (bottom-right of the bubble) so it
          // reads as being pulled into the button it will be cancelled by,
          // rather than shrinking toward its own center and drifting.
          alignment: Alignment.bottomRight,
          scale: scale,
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
      ),
    );
  }
}
