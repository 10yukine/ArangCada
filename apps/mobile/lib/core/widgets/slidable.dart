import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// A row that slides left to reveal a single options button, Messenger-style.
///
/// The button only exists while the row is swiped open -- it is not a
/// persistent affordance sitting in the row at rest. Deliberately not
/// `Dismissible`: swiping a conversation must not delete it, and it must not
/// jump straight to a popup either. The gesture reveals a button that stays
/// put until the row is tapped, the button is used, or another row is
/// opened, which is what the reference screens do.
///
/// `ClipRect` bounds the translated content to the row's own box, so a full
/// swipe reveals the action cleanly instead of pushing the avatar past the
/// screen's own left edge.
///
/// No package is used; `flutter_slidable` would be a dependency for one
/// interaction that an `AnimatedContainer` already handles.
class Slidable extends StatefulWidget {
  const Slidable({
    required this.child,
    required this.onOpenOptions,
    this.actionWidth = 58,
    super.key,
  });

  final Widget child;
  final VoidCallback onOpenOptions;
  final double actionWidth;

  @override
  State<Slidable> createState() => _SlidableState();
}

class _SlidableState extends State<Slidable> {
  bool _open = false;
  double _drag = 0;

  void close() {
    if (!_open && _drag == 0) return;
    setState(() {
      _open = false;
      _drag = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final offset = _open ? widget.actionWidth : _drag;

    return ClipRect(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          setState(() {
            _drag = (_drag - details.delta.dx).clamp(0.0, widget.actionWidth);
          });
        },
        onHorizontalDragEnd: (_) {
          setState(() {
            _open = _drag > widget.actionWidth / 2;
            _drag = _open ? widget.actionWidth : 0;
          });
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: widget.actionWidth,
                  height: double.infinity,
                  child: Material(
                    color: AppColors.primaryFill,
                    child: InkWell(
                      onTap: () {
                        close();
                        widget.onOpenOptions();
                      },
                      child: Semantics(
                        button: true,
                        label: 'Chat options',
                        child: const Icon(
                          Icons.more_horiz,
                          size: 22,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedContainer(
              duration: _open || offset == 0 ? AppMotion.button : Duration.zero,
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(-offset, 0, 0),
              // Tapping an open row closes it rather than opening the chat, so
              // the revealed button is never dismissed by accident.
              child: _open
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: close,
                      child: IgnorePointer(child: widget.child),
                    )
                  : widget.child,
            ),
          ],
        ),
      ),
    );
  }
}
