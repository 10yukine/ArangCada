import 'package:flutter/material.dart';

/// Tactile press feedback: a subtle scale-down the instant a finger touches
/// down, not on release.
///
/// Flutter's `InkWell` ripple alone is the neutral default every Material
/// app ships with. Layering a `scale(0.97)` on press -- the same technique
/// Apple and most hand-crafted interfaces use -- is what makes a control
/// feel like it is truly listening, per the design-engineering guidance this
/// follows. [Listener] (not `GestureDetector`) is used deliberately: it
/// observes raw pointer events without joining the gesture arena, so it
/// never competes with the `InkWell`/`onTap` beneath it for the tap.
///
/// Respects reduced-motion: when the platform's "remove animations"
/// accessibility setting is on, the scale still communicates press state
/// (per Apple's guidance that reduced motion means gentler feedback, not
/// none) but settles instantly instead of animating.
class PressScale extends StatefulWidget {
  const PressScale({required this.enabled, required this.child, super.key});

  final bool enabled;
  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final active = widget.enabled && _pressed;

    return Listener(
      onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
      onPointerUp: widget.enabled ? (_) => _setPressed(false) : null,
      onPointerCancel: widget.enabled ? (_) => _setPressed(false) : null,
      child: AnimatedScale(
        scale: active ? 0.97 : 1.0,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
