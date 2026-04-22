import 'package:flutter/material.dart';

class AppShimmer extends StatefulWidget {
  const AppShimmer({
    super.key,
    required this.child,
    this.enabled = true,
    this.duration = const Duration(milliseconds: 1350),
  });

  final Widget child;
  final bool enabled;
  final Duration duration;

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    if (widget.enabled) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AppShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled == oldWidget.enabled) return;
    if (widget.enabled) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF1F2E41) : const Color(0xFFD9E2EC);
    final highlight =
        isDark ? const Color(0xFF334A63) : const Color(0xFFF7FAFD);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final slide = (_controller.value * 2) - 1;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment(-1.0 + slide, -0.2),
              end: Alignment(1.0 + slide, 0.2),
              colors: [base, highlight, base],
              stops: const [0.1, 0.45, 0.9],
            ).createShader(rect);
          },
          child: widget.child,
        );
      },
    );
  }
}

class AppSkeletonBox extends StatelessWidget {
  const AppSkeletonBox({
    super.key,
    required this.height,
    this.width,
    this.radius = 10,
    this.color,
  });

  final double height;
  final double? width;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill =
        color ?? (isDark ? const Color(0xFF1F2E41) : const Color(0xFFD9E2EC));
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
