import 'dart:math' as math;
import 'package:flutter/material.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = theme.colorScheme.surfaceContainerLow;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            return _TypingDot(
              index: index,
              controller: _controller,
              color: theme.colorScheme.onSurfaceVariant,
            );
          }),
        ),
      ),
    );
  }
}

class _TypingDot extends StatelessWidget {
  const _TypingDot({
    required this.index,
    required this.controller,
    required this.color,
  });

  final int index;
  final AnimationController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // Offset each dot's animation start
        final double t = (controller.value - (index * 0.15)) % 1.0;

        // Create a "bounce" effect using a sine wave restricted to half its period
        // and only positive values for the "up" movement.
        // We want the dot to go up and back down, then stay still for a bit.
        double y = 0;
        if (t < 0.4) {
          // Normalizing 0.0 -> 0.4 to 0.0 -> PI
          y = math.sin((t / 0.4) * math.pi) * -5.0;
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          child: Transform.translate(
            offset: Offset(0, y),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.6 + (y.abs() * 0.08)),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}
