import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// A row that slides left to reveal a single options button.
///
/// Deliberately not `Dismissible`: swiping a conversation must not delete it,
/// and it must not jump straight to a popup either. The gesture reveals an
/// affordance that stays put until the row is tapped, the button is used, or
/// another row is opened -- which is what the reference screens do.
///
/// No package is used; `flutter_slidable` would be a dependency for one
/// interaction that an AnimatedPositioned already handles.
class Slidable extends StatefulWidget {
  const Slidable({
    required this.child,
    required this.onOpenOptions,
    this.actionWidth = 76,
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

  void _close() {
    if (!_open && _drag == 0) return;
    setState(() {
      _open = false;
      _drag = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final offset = _open ? widget.actionWidth : _drag;

    return GestureDetector(
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
                child: Material(
                  color: AppColors.clayFill,
                  child: InkWell(
                    onTap: () {
                      _close();
                      widget.onOpenOptions();
                    },
                    child: Semantics(
                      button: true,
                      label: 'Chat options',
                      child: const Icon(
                        Icons.more_horiz,
                        color: AppColors.clayText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: _open || offset == 0
                ? AppMotion.button
                : Duration.zero,
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(-offset, 0, 0),
            // Tapping an open row closes it rather than opening the chat, so
            // the revealed button is never dismissed by accident.
            child: _open
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: IgnorePointer(child: widget.child),
                  )
                : widget.child,
          ),
        ],
      ),
    );
  }
}
