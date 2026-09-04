import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import 'sheet_drag_handle.dart';

/// Whether the last sheet the user interacted with was open.
///
/// The ride flow moves through four screens that each carry a sheet, and a
/// commuter who drags one open has said what level of detail they want. Losing
/// that at every transition made them re-open it on the next screen, which read
/// as the app forgetting rather than as a fresh screen with its own default.
///
/// Deliberately not persisted beyond the session: it is a reading preference
/// for a journey, not a setting.
class SheetExpansionMemory {
  bool expanded = false;
}

/// A plain mutable holder rather than a reactive provider, on purpose. Nothing
/// needs to rebuild when this changes -- each sheet reads it once as it mounts
/// and writes it when it settles. A StateProvider here would add a rebuild path
/// nobody listens to.
final sheetExpansionProvider = Provider<SheetExpansionMemory>(
  (ref) => SheetExpansionMemory(),
);

/// Drives a [DragSheetScaffold] from outside it.
///
/// Needed because some sheets must open themselves in response to something
/// that is not a gesture -- the active trip expands the moment the driver
/// arrives, since a collapsed peek at that exact moment hides the one button
/// that matters. Everything else should leave this null and let the user
/// drive.
class DragSheetController extends ChangeNotifier {
  bool? _request;

  bool? takeRequest() {
    final value = _request;
    _request = null;
    return value;
  }

  void expand() {
    _request = true;
    notifyListeners();
  }

  void collapse() {
    _request = false;
    notifyListeners();
  }
}

/// A full-bleed background (the map) with a sheet over it that drags open to
/// full screen and takes the background away as it goes.
///
/// Every ride screen in the app was growing its own version of this. The good
/// one lived in `_ActiveTripSheetState`: a continuous 0..1 reveal driven by
/// [SheetDragHandle]'s drag callbacks, snapped on release by velocity or
/// position, honouring `MediaQuery.disableAnimations`. That logic is extracted
/// here rather than rewritten, and the screens that never had it -- the driver
/// match and approach screens, which were plain pages with an AppBar and no map
/// at all -- adopt it instead of growing a fourth variant.
///
/// The background is rebuilt by an [AnimatedBuilder] on the reveal controller,
/// not by the parent's `setState`. A drag emits a value every frame, and
/// rebuilding a whole screen (a live map among it) at that rate is the
/// difference between a sheet that tracks the finger and one that stutters.
///
/// `DraggableScrollableSheet` was considered and rejected: it requires a
/// scrollable child and runs its own gesture arena, which fights a fixed-height
/// sheet. That fight is why this codebase grew [SheetDragHandle] in the first
/// place.
class DragSheetScaffold extends ConsumerStatefulWidget {
  const DragSheetScaffold({
    required this.background,
    required this.sheetBuilder,
    this.overlay = const <Widget>[],
    this.collapsedHeight = 260,
    this.controller,
    this.footer,
    this.sheetKey,
    this.handleTrailing,
    this.handleSemanticLabel,
    super.key,
  });

  /// Painted edge to edge behind the sheet, and faded out as the sheet opens.
  final Widget background;

  /// Content below the drag handle. `expanded` lets a caller show detail only
  /// when there is room for it.
  final Widget Function(BuildContext context, bool expanded) sheetBuilder;

  /// Stacked over the background but under the sheet: back buttons, recentre
  /// controls. These fade with the background, since a control floating over a
  /// hidden map is pointing at nothing.
  final List<Widget> overlay;

  /// Height of the collapsed peek. The expanded height is always the full
  /// screen -- that uniformity is the point.
  final double collapsedHeight;

  final DragSheetController? controller;

  /// Pinned below the scrolling content, never scrolled off.
  ///
  /// The sheet's primary action belongs here. Putting it inside the scroll area
  /// means the one thing the screen exists for can be pushed out of reach by a
  /// long address or a large text-scale setting -- and the collapsed peek is
  /// deliberately shorter than its content, so that is the normal case rather
  /// than an edge one.
  final Widget? footer;

  /// Attached to the sheet's own box so a caller can measure its height.
  ///
  /// LiveMapViewController.bottomInset reads exactly this to know how much of
  /// the map is hidden, so fitRoute() can frame the route in the part still
  /// visible rather than centring it behind the sheet. Without it a "centre
  /// route" button politely centres the route underneath the panel covering it.
  final GlobalKey? sheetKey;

  final Widget? handleTrailing;
  final String? handleSemanticLabel;

  @override
  ConsumerState<DragSheetScaffold> createState() => _DragSheetScaffoldState();
}

class _DragSheetScaffoldState extends ConsumerState<DragSheetScaffold>
    with SingleTickerProviderStateMixin {
  /// Seeded from the last sheet the user touched, so dragging one open carries
  /// through the rest of the flow.
  late bool _expanded = ref.read(sheetExpansionProvider).expanded;
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: AppMotion.sheet,
    value: ref.read(sheetExpansionProvider).expanded ? 1 : 0,
  );

  /// How far a finger must travel to cross the whole range. Taken from the
  /// active-trip sheet unchanged: shorter feels twitchy, longer feels like the
  /// sheet is resisting.
  static const _dragExtent = 260.0;

  /// Above this, a flick decides the direction regardless of where the sheet
  /// happens to be sitting. Below it, position decides.
  static const _velocityThreshold = 250.0;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerRequest);
  }

  @override
  void didUpdateWidget(covariant DragSheetScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerRequest);
      widget.controller?.addListener(_onControllerRequest);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerRequest);
    _reveal.dispose();
    super.dispose();
  }

  void _onControllerRequest() {
    final request = widget.controller?.takeRequest();
    if (request != null) _setExpanded(request);
  }

  void _setExpanded(bool expanded) {
    if (mounted) setState(() => _expanded = expanded);
    // Written on every settle, including the end of a drag, so the next screen
    // opens the way this one was left.
    ref.read(sheetExpansionProvider).expanded = expanded;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _reveal.value = expanded ? 1 : 0;
    } else {
      _reveal.animateTo(
        expanded ? 1 : 0,
        duration: AppMotion.sheet,
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Tracks the finger directly. Dragging up is a negative dy, which raises
  /// the reveal.
  void _drag(double dy) {
    _reveal.value = (_reveal.value - dy / _dragExtent).clamp(0.0, 1.0);
  }

  void _endDrag(double velocity) {
    final expand =
        velocity < -_velocityThreshold ||
        (velocity.abs() <= _velocityThreshold && _reveal.value >= 0.5);
    _setExpanded(expand);
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    // Sized against the box this widget actually occupies, never against the
    // display. The ride screens render inside the commuter shell, whose bottom
    // tab bar makes the body shorter than the screen -- expanding to
    // MediaQuery.size.height overshot by exactly that difference, pushing the
    // drag handle off the top edge and leaving no way to drag the sheet back
    // down. A sheet that cannot be closed is worse than one that never opened.
    return LayoutBuilder(
      builder: (context, constraints) {
        final expandedHeight = constraints.maxHeight;
        // A caller's peek height must not exceed the space available either,
        // or the collapsed sheet is already overshooting before anyone drags.
        final collapsedHeight = widget.collapsedHeight > expandedHeight
            ? expandedHeight
            : widget.collapsedHeight;

        return Stack(
          children: [
            // Background and overlay share one builder: they belong to the same
            // layer conceptually, and fading them together avoids a recentre
            // button hovering over an empty white sheet.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _reveal,
                builder: (context, child) {
                  // Cleared a little before the sheet physically covers it, so the
                  // map reads as being put away rather than merely occluded.
                  final opacity =
                      (1 - Curves.easeIn.transform(_reveal.value) * 1.3).clamp(
                        0.0,
                        1.0,
                      );
                  if (opacity == 0) {
                    // Stop painting entirely once invisible. A live map is not
                    // cheap, and there is no reason to keep drawing one nobody can
                    // see.
                    return const SizedBox.shrink();
                  }
                  return Opacity(opacity: opacity, child: child);
                },
                child: Stack(
                  children: [
                    Positioned.fill(child: widget.background),
                    ...widget.overlay,
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: _reveal,
                builder: (context, child) {
                  final height = lerpDouble(
                    collapsedHeight,
                    expandedHeight,
                    _reveal.value,
                  )!;
                  return SizedBox(
                    key: widget.sheetKey,
                    height: height,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        // The corners flatten as the sheet becomes the screen. A
                        // rounded top against the status bar reads as a sheet that
                        // failed to finish opening.
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(
                            AppRadii.sheet * (1 - _reveal.value),
                          ),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: AppColors.shadowLight,
                            blurRadius: 10,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Padding(
                        // Earns its status-bar padding on the way up, so text
                        // never slides under the clock.
                        padding: EdgeInsets.only(top: topInset * _reveal.value),
                        child: child,
                      ),
                    ),
                  );
                },
                child: SafeArea(
                  top: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SheetDragHandle(
                        expanded: _expanded,
                        onToggle: () => _setExpanded(!_expanded),
                        onDragUpdate: _drag,
                        onDragEnd: _endDrag,
                        trailing: widget.handleTrailing,
                        semanticLabel: widget.handleSemanticLabel,
                      ),
                      // Scrolls rather than overflows: the collapsed peek is
                      // deliberately shorter than its content, and a fixed-height
                      // box around growing text is how a translated string clips.
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.xs,
                            AppSpacing.lg,
                            AppSpacing.md,
                          ),
                          child: widget.sheetBuilder(context, _expanded),
                        ),
                      ),
                      if (widget.footer != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            AppSpacing.sm,
                          ),
                          child: widget.footer,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
