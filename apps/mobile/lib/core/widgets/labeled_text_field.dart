import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';

/// A bold label above a field, matching the prototype's login/signup
/// density -- distinct from Flutter's default floating `labelText`, which
/// reads noticeably smaller and less confident at this weight.
///
/// Shared by the login and sign-up screens so their fields stay visually
/// identical; it used to be a private copy inside `login_screen.dart`.
class LabeledTextField extends StatefulWidget {
  const LabeledTextField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.hintText,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.obscureText = false,
    this.onSubmitted,
    this.suffixIcon,
    this.errorText,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;

  /// Format-illustrative, e.g. `you@example.com`, not a generic instruction
  /// like "Enter your email" -- the point is showing the expected shape of
  /// the answer, matching the reference prototype.
  final String hintText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;
  final String? errorText;
  final bool autofocus;

  @override
  State<LabeledTextField> createState() => _LabeledTextFieldState();
}

class _LabeledTextFieldState extends State<LabeledTextField> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() => setState(() {});

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          Text(widget.label, style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
        ],
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          keyboardType: widget.keyboardType,
          autofillHints: widget.autofillHints,
          textInputAction: widget.textInputAction,
          obscureText: widget.obscureText,
          onSubmitted: widget.onSubmitted,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: widget.label.isEmpty
                ? const TextStyle(fontSize: 13)
                : null,
            errorText: widget.errorText,
            fillColor: _focusNode.hasFocus
                ? AppColors.surface
                : AppColors.inputFill,
            prefixIcon: Icon(widget.icon, size: 18),
            suffixIcon: widget.suffixIcon,
          ),
        ),
      ],
    );
  }
}
