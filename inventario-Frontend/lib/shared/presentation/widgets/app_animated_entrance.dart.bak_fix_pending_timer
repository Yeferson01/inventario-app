import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

class AppAnimatedEntrance extends StatefulWidget {
  const AppAnimatedEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 16),
  });

  final Widget child;
  final Duration delay;
  final Offset offset;

  @override
  State<AppAnimatedEntrance> createState() => _AppAnimatedEntranceState();
}

class _AppAnimatedEntranceState extends State<AppAnimatedEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: CronosMotion.normal,
    );

    _opacity = CurvedAnimation(
      parent: _controller,
      curve: CronosMotion.curve,
    );

    _slide = Tween<Offset>(
      begin: widget.offset,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: CronosMotion.curve,
      ),
    );

    Future<void>.delayed(widget.delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, child) {
          return Transform.translate(
            offset: _slide.value,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
