import 'dart:math' as math;

import 'package:flutter/material.dart';

class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 14,
    this.margin,
  });

  final double? width;
  final double height;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    final highlight = theme.colorScheme.surfaceContainerLow;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final color = Color.lerp(base, highlight, _controller.value) ?? base;
        return Container(
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

class SkeletonCardList extends StatelessWidget {
  const SkeletonCardList({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(16),
    this.showAvatar = true,
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: itemCount,
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showAvatar) ...[
                  const SkeletonBox(width: 44, height: 44, radius: 22),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 120 + (index % 3) * 36, height: 16),
                      const SizedBox(height: 10),
                      SkeletonBox(
                        width: math.max(180, 240 - (index % 4) * 18).toDouble(),
                        height: 12,
                      ),
                      const SizedBox(height: 8),
                      SkeletonBox(
                        width: math.max(120, 200 - (index % 5) * 14).toDouble(),
                        height: 12,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AuthGateSkeleton extends StatelessWidget {
  const AuthGateSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CipherChat')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SkeletonBox(width: 64, height: 64, radius: 32),
                    SizedBox(height: 18),
                    SkeletonBox(width: 180, height: 22),
                    SizedBox(height: 12),
                    SkeletonBox(height: 14),
                    SizedBox(height: 8),
                    SkeletonBox(width: 240, height: 14),
                    SizedBox(height: 24),
                    SkeletonBox(height: 48, radius: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SearchResultsSkeleton extends StatelessWidget {
  const SearchResultsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        SkeletonBox(height: 56, radius: 18),
        SizedBox(height: 16),
        Expanded(
          child: SkeletonCardList(itemCount: 6, padding: EdgeInsets.zero),
        ),
      ],
    );
  }
}

class ChatListSkeleton extends StatelessWidget {
  const ChatListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeletonCardList(itemCount: 6);
  }
}

class InvitesSkeleton extends StatelessWidget {
  const InvitesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(child: SkeletonBox(height: 40, radius: 16)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 40, radius: 16)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 40, radius: 16)),
            ],
          ),
        ),
        Expanded(child: SkeletonCardList(itemCount: 5)),
      ],
    );
  }
}

class GroupDetailsSkeletonView extends StatelessWidget {
  const GroupDetailsSkeletonView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 180, height: 28),
                SizedBox(height: 12),
                SkeletonBox(width: 240, height: 14),
                SizedBox(height: 20),
                SkeletonBox(height: 44, radius: 16),
              ],
            ),
          ),
        ),
        SizedBox(height: 18),
        SkeletonBox(width: 120, height: 22),
        SizedBox(height: 12),
        SizedBox(
          height: 420,
          child: SkeletonCardList(itemCount: 5, padding: EdgeInsets.zero),
        ),
      ],
    );
  }
}

class ChatMessagesSkeleton extends StatelessWidget {
  const ChatMessagesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBox(width: 170, height: 40, radius: 18),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: 8,
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final isMine = index.isEven;
              return Align(
                alignment: isMine
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: SkeletonBox(
                  width: isMine ? 180 : 220,
                  height: 68,
                  radius: 20,
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: const [
              Expanded(child: SkeletonBox(height: 54, radius: 18)),
              SizedBox(width: 12),
              SkeletonBox(width: 96, height: 54, radius: 18),
            ],
          ),
        ),
      ],
    );
  }
}
