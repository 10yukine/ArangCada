import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Front-facing Philippine tricycle (sidecar cab + motorcycle). Sizes and
/// colors itself from the surrounding [IconTheme] like a regular [Icon].
class TricycleIcon extends StatelessWidget {
  const TricycleIcon({super.key, this.size, this.color});

  final double? size;
  final Color? color;

  static const _svg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
      'stroke="#000" stroke-width="1.8" stroke-linecap="round" '
      'stroke-linejoin="round">'
      '<rect x="2" y="3" width="20" height="3" rx="1.5"/>' // roof
      '<path d="M5 6v12h9V6"/>' // sidecar cab
      '<rect x="7" y="8" width="5" height="4" rx="1"/>' // windshield
      '<rect x="2" y="14" width="3" height="7" rx="1.5"/>' // sidecar wheel
      '<circle cx="18" cy="10" r="2"/>' // driver
      '<path d="M14 14.5h7"/>' // handlebar
      '<rect x="16" y="14.5" width="4" height="6.5" rx="2"/>' // front wheel
      '</svg>';

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    return SvgPicture.string(
      _svg,
      width: side,
      height: side,
      colorFilter: ColorFilter.mode(
        color ?? theme.color ?? Colors.black,
        BlendMode.srcIn,
      ),
    );
  }
}
