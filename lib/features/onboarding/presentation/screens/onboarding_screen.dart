import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/startup/app_startup.dart';
import '../../../../core/theme/app_theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_currentPage < 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _onBack() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _completeOnboarding() {
    appStartupController.completeOnboarding();
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGX = GXThemeExtension.of(context).isGX;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _completeOnboarding,
            child: Text(
              isGX ? 'SKIP' : 'Skip',
              style: isGX ? const TextStyle(fontFamily: 'monospace') : null,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                children: [
                  _OnboardingPage(
                    title: 'CipherChat',
                    description:
                        'Private real-time messaging for individuals and groups.',
                    heroContent: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Text(
                        'Real-time messaging with secure cloud sync and group conversations.',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  _OnboardingPage(
                    title: 'Your Privacy Matters',
                    description:
                        'Messages are encrypted before they leave your device, helping keep your conversations private.',
                    heroContent: Column(
                      children: [
                        _PrivacyFeatureCard(
                          icon: Icons.lock_outline_rounded,
                          title: 'Local encryption',
                          description:
                              'Messages are secured on your device before sending.',
                        ),
                        const SizedBox(height: 12),
                        _PrivacyFeatureCard(
                          icon: Icons.sync_lock_rounded,
                          title: 'Secure synchronization',
                          description:
                              'Your data is synced safely across all your devices.',
                        ),
                        const SizedBox(height: 12),
                        _PrivacyFeatureCard(
                          icon: Icons.privacy_tip_outlined,
                          title: 'Privacy-focused design',
                          description:
                              'Built from the ground up to protect your communication.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    OutlinedButton(
                      onPressed: _onBack,
                      child: Text(
                        isGX ? 'BACK' : 'Back',
                        style: isGX
                            ? const TextStyle(fontFamily: 'monospace')
                            : null,
                      ),
                    )
                  else
                    const SizedBox(width: 80), // Spacer to keep balance
                  const Spacer(),
                  Row(
                    children: List.generate(
                      2,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == index
                              ? theme.colorScheme.primary
                              : theme.colorScheme.primary.withAlpha(51),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _onNext,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(120, 48),
                    ),
                    child: Text(
                      _currentPage == 1
                          ? (isGX ? 'GET STARTED' : 'Get Started')
                          : (isGX ? 'NEXT' : 'Next'),
                      style: isGX
                          ? const TextStyle(fontFamily: 'monospace')
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.title,
    required this.description,
    required this.heroContent,
  });

  final String title;
  final String description;
  final Widget heroContent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGX = GXThemeExtension.of(context).isGX;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Text(
            isGX ? title.toUpperCase() : title,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontFamily: isGX ? 'monospace' : null,
              letterSpacing: isGX ? 2.0 : null,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          heroContent,
        ],
      ),
    );
  }
}

class _PrivacyFeatureCard extends StatelessWidget {
  const _PrivacyFeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGX = GXThemeExtension.of(context).isGX;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(76),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(127),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isGX ? title.toUpperCase() : title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFamily: isGX ? 'monospace' : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
