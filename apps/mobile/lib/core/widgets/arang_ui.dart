import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import 'press_scale.dart';

/// ArangCada's owned component primitives.
///
/// These follow the shadcn/ui *discipline* -- components live in this
/// repository rather than a package, every visual value comes from
/// `app/theme`, and variation is expressed as an explicit variant rather than
/// a pile of optional styling arguments. shadcn's *code* is React + Tailwind
/// and cannot be used here, so the ideas are reimplemented in Dart.
///
/// Feature code composes these. It must not reach for raw `ElevatedButton`,
/// `Card`, or hand-written `BoxDecoration`, because that is how a design
/// system drifts.

enum ArangButtonVariant { primary, ghost, dangerGhost }

/// Full-width pill button. The prototype's primary action shape.
class ArangButton extends StatelessWidget {
  const ArangButton({
    required this.label,
    required this.onPressed,
    this.variant = ArangButtonVariant.primary,
    this.icon,
    this.iconTrailing = false,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final ArangButtonVariant variant;
  final IconData? icon;

  /// Puts [icon] after the label instead of before it.
  ///
  /// For actions that move the user forward. A leading arrow on "Send Reset
  /// Link" points back the way they came, which is the opposite of what the
  /// button does; trailing reads as "and then this happens".
  final bool iconTrailing;

  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    late final Color background;
    late final Color foreground;
    late final Color? borderColor;
    switch (variant) {
      case ArangButtonVariant.primary:
        background = enabled ? AppColors.primary : AppColors.disabledFill;
        foreground = enabled ? Colors.white : AppColors.textDisabled;
        borderColor = null;
      case ArangButtonVariant.ghost:
        background = AppColors.surface;
        foreground = enabled ? AppColors.textRow : AppColors.textDisabled;
        borderColor = AppColors.borderStrong;
      case ArangButtonVariant.dangerGhost:
        background = AppColors.surface;
        foreground = enabled ? AppColors.dangerDark : AppColors.textDisabled;
        borderColor = AppColors.dangerBorder;
    }

    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null && !iconTrailing) ...[
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: AppSpacing.xs),
        ],
        // Flexible only earns its place when the row may grow. On a
        // shrink-wrapped button it just invites a squeezed label.
        if (expand)
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: foreground,
              ),
            ),
          )
        else
          Text(
            label,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
        if (icon != null && iconTrailing) ...[
          const SizedBox(width: AppSpacing.xs),
          Icon(icon, size: 18, color: foreground),
        ],
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: PressScale(
        enabled: enabled,
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(
              Radius.circular(AppRadii.pill),
            ),
            side: borderColor == null
                ? BorderSide.none
                : BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AppSizes.buttonHeight,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 13,
              ),
              // Only centre when the button is meant to span its parent.
              // `Container.alignment` wraps the child in an Align, and an
              // Align with no widthFactor expands to the maximum width on
              // offer -- so setting it unconditionally made every
              // `expand: false` button silently full width, which is why
              // inline card actions looked oversized.
              alignment: expand ? Alignment.center : null,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact pill filter/selection chip. Selected state uses the brand tint.
class ArangChip extends StatelessWidget {
  const ArangChip({
    required this.label,
    required this.selected,
    this.onTap,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: PressScale(
        enabled: onTap != null,
        child: Material(
          color: selected ? AppColors.primaryFill : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(
              Radius.circular(AppRadii.chip),
            ),
            side: BorderSide(
              color: selected ? AppColors.sky : AppColors.borderStrong,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AppSizes.minTapTarget,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 15,
                      color: selected
                          ? AppColors.primaryText
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? AppColors.primaryText
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White surface with the prototype's hairline border and 16px radius.
class ArangCard extends StatelessWidget {
  const ArangCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.color,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Material(
      color: color ?? AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Rounded square icon tile used at the head of prototype list rows.
class ArangRowIcon extends StatelessWidget {
  const ArangRowIcon(
    this.icon, {
    this.background = AppColors.neutralFill,
    this.foreground = AppColors.textSecondary,
    this.size = AppSizes.rowIcon,
    super.key,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Icon(icon, size: size * 0.52, color: foreground),
    );
  }
}

/// Full-width tappable row: icon tile, title, optional subtitle, chevron.
/// The prototype uses these directly on the page background rather than
/// wrapping each one in its own card.
class ArangRow extends StatelessWidget {
  const ArangRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.iconBackground = AppColors.neutralFill,
    this.iconForeground = AppColors.textSecondary,
    this.showChevron = true,
    this.showDivider = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color iconBackground;
  final Color iconForeground;
  final bool showChevron;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: showDivider
              ? const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.dividerLight),
                  ),
                )
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ArangRowIcon(
                icon,
                background: iconBackground,
                foreground: iconForeground,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textRow,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption,
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
              if (trailing == null && showChevron)
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular initials avatar. Avoids shipping any photo assets.
class ArangAvatar extends StatelessWidget {
  const ArangAvatar({
    required this.name,
    this.size = AppSizes.avatar,
    this.background = AppColors.primaryFill,
    this.foreground = AppColors.primaryText,
    this.imageUrl,
    super.key,
  });

  final String name;
  final double size;
  final Color background;
  final Color foreground;

  /// A signed URL for an uploaded photo (see .pipeline/specs.md Spec 15).
  /// Null renders today's initials circle unchanged -- every existing call
  /// site keeps working without passing this.
  final String? imageUrl;

  static String initialsFor(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  Widget _initials() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(
        initialsFor(name),
        style: TextStyle(
          fontSize: size * 0.33,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return _initials();
    // A signed URL can expire or fail to load (offline, revoked); falling
    // back to the same initials circle beats a broken-image icon or a blank
    // space where someone's identity is meant to be.
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _initials(),
      ),
    );
  }
}

enum ArangBadgeTone { green, amber, red, brand, neutral }

/// Small status pill. Tone always pairs with text, never colour alone.
class ArangBadge extends StatelessWidget {
  const ArangBadge(this.label, {this.tone = ArangBadgeTone.neutral, super.key});

  final String label;
  final ArangBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    late final Color background;
    late final Color foreground;
    switch (tone) {
      case ArangBadgeTone.green:
        background = AppColors.greenFill;
        foreground = AppColors.greenDark;
      case ArangBadgeTone.amber:
        background = AppColors.amberFill;
        foreground = AppColors.amberText;
      case ArangBadgeTone.red:
        background = AppColors.dangerFill;
        foreground = AppColors.dangerDeep;
      case ArangBadgeTone.brand:
        background = AppColors.primaryFill;
        foreground = AppColors.primaryText;
      case ArangBadgeTone.neutral:
        background = AppColors.neutralFill;
        foreground = AppColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.badge)),
      ),
      child: Text(
        label,
        style: AppTypography.badge.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// "Section heading + optional trailing" pair used throughout the prototype.
class ArangSectionHead extends StatelessWidget {
  const ArangSectionHead(this.title, {this.trailing, this.color, super.key});

  final String title;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: AppTypography.h2.copyWith(color: color)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Circular bordered icon button, 42px, as used in prototype headers.
class ArangIconButton extends StatelessWidget {
  const ArangIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.showDot = false,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    // The 42dp circle is the prototype's visual size; the tap target is
    // padded out to the 48dp minimum without changing how it looks.
    final button = Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip ?? '',
        excludeFromSemantics: true,
        child: Material(
          color: AppColors.surface,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: AppSizes.iconButton,
              height: AppSizes.iconButton,
              child: Icon(icon, size: 20, color: AppColors.textRow),
            ),
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSizes.minTapTarget,
            minHeight: AppSizes.minTapTarget,
          ),
          child: Center(child: button),
        ),
        if (showDot)
          Positioned(
            top: 8,
            right: 9,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

/// Search/destination field styled like the prototype's `.field`.
class ArangField extends StatelessWidget {
  const ArangField({
    required this.icon,
    required this.text,
    required this.onTap,
    this.muted = true,
    super.key,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    color: muted ? AppColors.textMuted : AppColors.ink,
                    fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The route pair used wherever a trip is shown: a round dot for pickup and a
/// location pin for the destination, told apart by shape as well as label.
/// Both sit in a 20 px column so stacked rows line up.
class ArangRouteMarker extends StatelessWidget {
  const ArangRouteMarker({required this.destination, super.key});

  final bool destination;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Center(
        child: destination
            ? const Icon(Icons.location_on, size: 16, color: AppColors.primary)
            : Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
      ),
    );
  }
}

/// One stop of a trip: the route marker, a small label ("Pickup",
/// "Drop-off") and the place name. Shared by every ride screen so the route
/// reads the same from search to receipt.
class ArangRouteStop extends StatelessWidget {
  const ArangRouteStop({
    required this.destination,
    required this.label,
    required this.name,
    super.key,
  });

  final bool destination;
  final String label;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ArangRouteMarker(destination: destination),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.caption),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Five large stars with the choice said back in words (Poor to Great).
/// Read-only when [onChanged] is null, e.g. after a rating was sent.
class ArangStarRating extends StatelessWidget {
  const ArangStarRating({required this.value, this.onChanged, super.key});

  static const words = ['Poor', 'Fair', 'Okay', 'Good', 'Great'];

  /// 0 when nothing is chosen yet.
  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var star = 1; star <= 5; star++)
              if (onChanged != null)
                IconButton(
                  tooltip: '$star star${star == 1 ? '' : 's'}',
                  iconSize: 40,
                  onPressed: () => onChanged!(star),
                  icon: Icon(
                    star <= value
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: AppColors.primary,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    star <= value
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: AppColors.primary,
                    size: 36,
                  ),
                ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value == 0 ? 'Tap a star' : words[value - 1],
          textAlign: TextAlign.center,
          style: AppTypography.label.copyWith(
            color: value == 0 ? AppColors.textMuted : AppColors.primary,
          ),
        ),
      ],
    );
  }
}
