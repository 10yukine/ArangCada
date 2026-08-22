import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// A bottom-sheet handle that actually responds to being dragged, not just
/// tapped.
///
/// The grey pill at the top of a sheet reads as a drag affordance; before
/// this it was decoration in some sheets and tap-only in others, so the
/// thing it visually promised never happened. This widget keeps the tap
/// (for anyone who taps instead of drags) and adds a real vertical drag:
/// dragging up expands, dragging down collapses, judged by direction and a
/// small distance threshold rather than requiring a full sheet-height throw.
///
/// State stays owned by the caller (an `expanded` bool + a toggle), because
/// every sheet in this app already expresses "how much detail is showing"
/// that way. This widget only decides *when* to call it.
class SheetDragHandle extends StatefulWidget {
  const SheetDragHandle({
    required this.expanded,
    required this.onToggle,
    this.semanticLabel,
    super.key,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final String? semanticLabel;

  @override
  State<SheetDragHandle> createState() => _SheetDragHandleState();
}

class _SheetDragHandleState extends State<SheetDragHandle> {
  double _dragDy = 0;
  bool _dragging = false;

  static const _distanceThreshold = 18.0;
  static const _velocityThreshold = 250.0;

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final draggedUp = velocity < -_velocityThreshold || _dragDy < -_distanceThreshold;
    final draggedDown = velocity > _velocityThreshold || _dragDy > _distanceThreshold;
    setState(() {
      _dragDy = 0;
      _dragging = false;
    });
    if (draggedUp && !widget.expanded) {
      widget.onToggle();
    } else if (draggedDown && widget.expanded) {
      widget.onToggle();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel ??
          (widget.expanded ? 'Collapse details' : 'Expand details'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        onVerticalDragStart: (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: (details) =>
            setState(() => _dragDy += details.delta.dy),
        onVerticalDragEnd: _onDragEnd,
        onVerticalDragCancel: () => setState(() {
          _dragDy = 0;
          _dragging = false;
        }),
        child: Container(
          // A real tap target, even though the visible bar is thin.
          constraints: const BoxConstraints(minHeight: 28),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: AppMotion.button,
            curve: Curves.easeOut,
            width: _dragging ? 44 : 36,
            height: 4,
            decoration: BoxDecoration(
              color: _dragging ? AppColors.borderStrong : AppColors.disabledFill,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
