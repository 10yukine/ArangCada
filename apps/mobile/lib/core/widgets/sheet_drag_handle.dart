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
    this.trailing,
    this.onDragUpdate,
    this.onDragEnd,
    super.key,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final String? semanticLabel;
  final Widget? trailing;
  final ValueChanged<double>? onDragUpdate;
  final ValueChanged<double>? onDragEnd;

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
    if (widget.onDragEnd != null) {
      widget.onDragEnd!(velocity);
      setState(() {
        _dragDy = 0;
        _dragging = false;
      });
      return;
    }
    final draggedUp =
        velocity < -_velocityThreshold || _dragDy < -_distanceThreshold;
    final draggedDown =
        velocity > _velocityThreshold || _dragDy > _distanceThreshold;
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

  void _onDragCancel() {
    widget.onDragEnd?.call(0);
    setState(() {
      _dragDy = 0;
      _dragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final handle = Semantics(
      button: true,
      label:
          widget.semanticLabel ??
          (widget.expanded ? 'Collapse details' : 'Expand details'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        onVerticalDragStart: (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: (details) {
          widget.onDragUpdate?.call(details.delta.dy);
          if (widget.onDragUpdate == null) {
            setState(() => _dragDy += details.delta.dy);
          }
        },
        onVerticalDragEnd: _onDragEnd,
        onVerticalDragCancel: _onDragCancel,
        child: Center(
          child: AnimatedContainer(
            duration: AppMotion.button,
            curve: Curves.easeOut,
            width: _dragging ? 44 : 36,
            height: 4,
            decoration: BoxDecoration(
              color: _dragging
                  ? AppColors.borderStrong
                  : AppColors.disabledFill,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );

    return SizedBox(
      width: double.infinity,
      height: widget.trailing == null ? 28 : AppSizes.minTapTarget,
      child: widget.trailing == null
          ? handle
          : Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(child: handle),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox.square(
                    dimension: AppSizes.minTapTarget,
                    child: widget.trailing,
                  ),
                ),
              ],
            ),
    );
  }
}
