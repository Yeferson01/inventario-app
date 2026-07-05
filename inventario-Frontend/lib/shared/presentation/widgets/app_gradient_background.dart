import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

class AppGradientBackground extends StatelessWidget {
  const AppGradientBackground({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: CronosColors.appBackgroundGradient,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
