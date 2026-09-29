import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// The app's text field: an outlined box whose label sits inside it and
/// floats up into the border when the field is focused or filled, with its
/// error shown directly under the box (icon + red text). One widget for every
/// form so login, sign-up and profile fields stay identical.
///
/// [label] is the floating label. When it is empty, [hintText] is used as
/// the label instead (short forms like login, where "Password" says it all);
/// otherwise [hintText] is the example shown once the field is focused, e.g.
/// `you@example.com`.
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
    this.onChanged,
    this.suffixIcon,
    this.errorText,
    this.helperText,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String hintText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;

  /// Screens clear this field's error here, so it disappears as soon as the
  /// person starts fixing it.
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;
  final String? errorText;

  /// Guidance under the box, e.g. "At least 8 characters"; an error replaces it.
  final String? helperText;
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
    final error = widget.errorText;
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      obscureText: widget.obscureText,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: widget.label.isEmpty ? widget.hintText : widget.label,
        hintText: widget.label.isEmpty ? null : widget.hintText,
        helperText: widget.helperText,
        helperStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        labelStyle: const TextStyle(fontSize: 15, color: AppColors.textMuted),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: states.contains(WidgetState.error)
                ? AppColors.danger
                : states.contains(WidgetState.focused)
                ? AppColors.primary
                : AppColors.textMuted,
          ),
        ),
        error: error == null
            ? null
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.error, size: 16, color: AppColors.danger),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.input)),
          borderSide: BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.input)),
          borderSide: BorderSide(color: AppColors.danger, width: 2),
        ),
        fillColor: _focusNode.hasFocus
            ? AppColors.surface
            : AppColors.inputFill,
        prefixIcon: Icon(
          widget.icon,
          size: 18,
          color: error != null ? AppColors.danger : null,
        ),
        suffixIcon: widget.suffixIcon,
      ),
    );
  }
}
