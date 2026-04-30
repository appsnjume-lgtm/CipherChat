import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/connectivity_service.dart';
import 'skeleton_loader.dart';

class NoInternetOverlay extends StatelessWidget {
  const NoInternetOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class ConnectivityBodyIndicator extends ConsumerWidget {
  const ConnectivityBodyIndicator({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 0),
    this.loadingHeight = 52,
  });

  final EdgeInsetsGeometry padding;
  final double loadingHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityStatusProvider);

    return connectivity.when(
      data: (isOnline) {
        if (isOnline) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        return Padding(
          padding: padding,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Offline. Showing saved data and waiting to reconnect.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => Padding(
        padding: padding,
        child: SkeletonBox(height: loadingHeight, radius: 18),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
