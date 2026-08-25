import 'package:flutter/material.dart';

/// ArangCada colour palette.
///
/// The identity is anchored on two supplied brand colours:
///
///   Brand Blue  #1262D0  (HSL 215 84% 44%) -- deep, civic, trustworthy
///   Sky         #53B8F6  (HSL 202 90% 65%) -- light support accent
///
/// Contrast budget (WCAG 2.1, measured, not guessed):
///
///   white       on #1262D0 -> 5.70:1   AA  (button labels)
///   #1262D0     on white   -> 5.70:1   AA  (links, text buttons)
///   #1262D0     on #F6F9FD -> 5.36:1   AA  (links on the app background)
///   #0B4699     on #E4F0FE -> 7.74:1   AAA (chip/badge text)
///   #53B8F6     on white   -> 2.20:1   FAIL
///
/// That last line is the load-bearing rule: [sky] is a decoration colour --
/// map route casing, gradients, illustration, focus glow, dark surfaces. It
/// must never carry body text on a light background. Everything that has to
/// be *read* or *tapped* uses [primary].
///
/// The neutrals are cut cool (hue 213-215, saturation 8-22%) so the blue reads
/// as the native accent of the surface rather than a colour dropped onto an
/// unrelated beige. Their lightness values are matched to the warm ramp they
/// replaced, so every contrast relationship the UI already relied on survives
/// the recolour unchanged.
abstract final class AppColors {
  // --- Text -----------------------------------------------------------------
  static const ink = Color(0xFF0F1A28);
  static const textSecondary = Color(0xFF48586B);
  static const textMuted = Color(0xFF5A6A7D);
  static const textRow = Color(0xFF2B3B4D);
  static const label = Color(0xFF1A2736);
  static const textDisabled = Color(0xFF8493A5);

  // --- Surfaces and lines ---------------------------------------------------
  static const screenBackground = Color(0xFFF6F9FD);
  static const surface = Color(0xFFFFFFFF);
  static const inputFill = Color(0xFFF1F6FC);
  static const pressedFill = Color(0xFFE8F0FA);
  static const neutralFill = Color(0xFFE9F0F8);
  static const border = Color(0xFFDBE5F1);
  static const borderStrong = Color(0xFFC4D3E5);
  static const dividerLight = Color(0xFFE9F0F8);
  static const disabledFill = Color(0xFFCCD8E6);

  // --- Brand ----------------------------------------------------------------
  static const primary = Color(0xFF1262D0);
  static const primaryPressed = Color(0xFF0E4EA6);

  /// Deepest brand step. Navy anchor for dark rails, headers, and the
  /// admin console sidebar.
  static const primaryDeep = Color(0xFF0C2340);

  /// The light brand accent. Decoration only -- see the class doc.
  static const sky = Color(0xFF53B8F6);

  /// Softer [sky] step for gradient tails and low-emphasis map fills.
  static const skySoft = Color(0xFF9BD5FA);

  /// Tinted background for brand chips, badges, and selected states.
  static const primaryFill = Color(0xFFE4F0FE);

  /// Text and icons drawn on [primaryFill]. 7.74:1 against it.
  static const primaryText = Color(0xFF0B4699);

  // --- Status ---------------------------------------------------------------
  // Success, warning, and danger keep their universal hues. A blue "danger"
  // would be indefensible in an SOS flow. They are only re-cut so their tints
  // sit on the cool neutral ramp instead of the old warm one.
  static const green = Color(0xFF0E7A5A);
  static const greenDark = Color(0xFF0A6349);
  static const greenFill = Color(0xFFDFF3EB);
  static const amberFill = Color(0xFFFCEFD6);
  static const amberText = Color(0xFF7A5210);

  static const danger = Color(0xFFC22F26);
  static const dangerDark = Color(0xFFA82920);
  static const dangerDeep = Color(0xFF8E211A);
  static const dangerFill = Color(0xFFFCEAE8);
  static const dangerBorder = Color(0xFFEDA9A2);
}
