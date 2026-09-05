import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';

class AppTabDestination {
  const AppTabDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.showNotification = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool showNotification;
}

/// The bottom navigation bar, flush to the edge of the screen.
///
/// It used to be a floating pill: inset 14px, fully rounded, with a strong
/// shadow. That looked lighter in isolation and cost more than it looked. A bar
/// that hovers over content is still opaque, so every scrolling screen has to
/// reserve space for a control that is pretending not to occupy any -- and
/// "did I leave enough bottom padding" is a bug that recurs on every new screen
/// rather than being fixed once.
///
/// Flush also matches the shape the rest of the app already settled on. The
/// ride sheets sit against the bottom edge with square corners at full height;
/// a rounded pill floating beneath them was the odd one out.
///
/// Used by both roles through `AdaptiveTabShell`. A commuter and a driver get
/// the same bar because there is no reason for them to differ, and two bottom
/// bars would drift apart the way the two sheet implementations did.
class AppTabBar extends StatelessWidget {
  const AppTabBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
    super.key,
  });

  /// Excludes the gesture inset, which is added on top. Material lands bottom
  /// bars at 56-64; this is the upper end because every destination shows a
  /// label, and a 20px icon over an 11px label needs the room.
  static const double barHeight = 62;

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<AppTabDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        // A hairline, not a shadow. The bar no longer floats, so it has no
        // height to cast from -- a shadow here would imply a depth that is not
        // there. The line exists only to stop white content bleeding into a
        // white bar (better-ui: borders for structure, shadows for elevation).
        border: Border(top: BorderSide(color: AppColors.dividerLight)),
      ),
      child: SafeArea(
        top: false,
        // Sits above the gesture bar rather than under it. Flush means flush to
        // the usable edge, not to the glass.
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: [
              for (var index = 0; index < destinations.length; index++)
                Expanded(
                  child: _AppTabItem(
                    destination: destinations[index],
                    selected: index == selectedIndex,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppTabItem extends StatelessWidget {
  const _AppTabItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppTabDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        // No radius. A pill highlight inside a square bar reads as a leftover
        // from the floating version.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 30,
              height: 24,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 22,
                    color: color,
                  ),
                  if (destination.showNotification)
                    Positioned(
                      right: 0,
                      top: -1,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surface,
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.tab.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
