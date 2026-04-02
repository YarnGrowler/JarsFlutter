import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';

class PointCounter extends StatefulWidget {
  final double value;
  final double fontSize;
  final Color? color;
  final String? suffix;
  final Duration duration;

  const PointCounter({
    super.key,
    required this.value,
    this.fontSize = 24,
    this.color,
    this.suffix,
    this.duration = const Duration(milliseconds: 600),
  });

  @override
  State<PointCounter> createState() => _PointCounterState();
}

class _PointCounterState extends State<PointCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _oldValue = 0;

  @override
  void initState() {
    super.initState();
    _oldValue = widget.value;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = Tween(begin: widget.value, end: widget.value)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(PointCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _oldValue = oldWidget.value;
      _animation = Tween(begin: _oldValue, end: widget.value)
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AnimatedBuilder(
      listenable: _animation,
      builder: (context, _) {
        final v = _animation.value;
        final display = v == v.toInt() ? '${v.toInt()}' : v.toStringAsFixed(1);
        return Text(
          '$display${widget.suffix ?? ''}',
          style: GoogleFonts.spaceMono(
            fontSize: widget.fontSize,
            fontWeight: FontWeight.w700,
            color: widget.color ?? JarsColors.gold,
          ),
        );
      },
    );
  }
}

class _AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;

  const _AnimatedBuilder({
    required super.listenable,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return builder(context, null);
  }
}
