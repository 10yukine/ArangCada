import 'package:flutter/material.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // Sections share the page surface; spacing establishes their hierarchy.
    return Padding(padding: padding, child: child);
  }
}
