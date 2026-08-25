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
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final ArangButtonVariant variant;
  final IconData? icon;
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
        if (icon != null) ...[
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

/// Compact pill filter/selection chip. Selected state uses the clay tint.
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
            child: Padding(
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
        side: BorderSide(color: AppColors.border),
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
    super.key,
  });

  final String name;
  final double size;
  final Color background;
  final Color foreground;

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

  @override
  Widget build(BuildContext context) {
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
}

enum ArangBadgeTone { green, amber, red, clay, neutral }

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
      case ArangBadgeTone.clay:
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
          shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
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
