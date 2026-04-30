import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isGX = GXThemeExtension.of(context).isGX;
    final accent = GXThemeExtension.of(context).accent;

    return Scaffold(
      appBar: AppBar(title: Text(isGX ? 'PRIVACY PROTOCOL' : 'Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // ── Hero banner ────────────────────────────────────────────────
          _HeroBanner(isGX: isGX, accent: accent, colorScheme: colorScheme),
          const SizedBox(height: 24),

          // ── Last updated chip ──────────────────────────────────────────
          _MetaRow(isGX: isGX, accent: accent, colorScheme: colorScheme),
          const SizedBox(height: 28),

          // ── Data collection ────────────────────────────────────────────
          _SectionHeading(
            text: isGX ? 'DATA COLLECTION' : 'What We Collect',
            isGX: isGX,
            accent: accent,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 12),
          _ExpandableCard(
            icon: Icons.person_outline_rounded,
            title: isGX ? 'IDENTITY METADATA' : 'Account Information',
            summary: isGX
                ? 'Username handle, avatar hash, registration timestamp.'
                : 'Username, profile photo, and account creation date.',
            detail: isGX
                ? 'Minimal identity data is stored to facilitate peer discovery within the network. No real name, phone number, or email is required beyond authentication.'
                : 'We collect only what is necessary to identify you within the app. This includes your chosen username and optional avatar. No government ID or phone number is required.',
            isGX: isGX,
            accent: accent,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 10),
          _ExpandableCard(
            icon: Icons.chat_bubble_outline_rounded,
            title: isGX ? 'MESSAGE PAYLOADS' : 'Message Content',
            summary: isGX
                ? 'Encrypted ciphertext only. Plaintext never leaves the device.'
                : 'Only encrypted message content is stored on our servers.',
            detail: isGX
                ? 'All message payloads are sealed client-side before uplink. The server receives and stores only opaque ciphertext. Server operators cannot read your messages under any circumstances.'
                : 'Messages are encrypted on your device before being sent. Our servers store only the encrypted form. We have no technical ability to read the content of your conversations.',
            isGX: isGX,
            accent: accent,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 10),
          _ExpandableCard(
            icon: Icons.devices_rounded,
            title: isGX ? 'DEVICE TELEMETRY' : 'Device Information',
            summary: isGX
                ? 'Platform type and app version only. No hardware fingerprinting.'
                : 'Basic platform info used to deliver the correct app experience.',
            detail: isGX
                ? 'We log the operating system platform (Android/iOS) and semantic app version to enable targeted hotfix delivery. No device identifiers, IMEI, MAC address, or hardware fingerprints are recorded.'
                : 'We record your OS platform and app version to diagnose compatibility issues and deliver relevant updates. No unique hardware identifiers are collected.',
            isGX: isGX,
            accent: accent,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 28),

          // ── Security ───────────────────────────────────────────────────
          _SectionHeading(
            text: isGX ? 'SECURITY ARCHITECTURE' : 'Security',
            isGX: isGX,
            accent: accent,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 12),
          _PolicyCard(
            icon: Icons.vpn_key_rounded,
            title: isGX ? 'CRYPTOGRAPHIC SHIELD' : 'Message Encryption',
            body: isGX
                ? 'Messages are sealed on-device before transmission. This MVP utilises a shared AES key for demonstration. Full E2EE asymmetric key exchange is scheduled for the next build cycle.'
                : 'Messages are encrypted on your device before being sent. The current version uses a shared AES key for demonstration purposes. Full end-to-end encryption with per-user key pairs is coming soon.',
            isGX: isGX,
            accent: accent,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 10),
          _PolicyCard(
            icon: Icons.lock_clock_rounded,
            title: isGX ? 'SESSION TOKENS' : 'Authentication Sessions',
            body: isGX
                ? 'Auth uplinks are managed via short-lived JWT tokens issued by the secure auth cluster. Tokens are rotated on each session resume and purged on sign-out.'
                : 'Sessions are secured with JWT tokens that automatically refresh. Signing out immediately invalidates your session and clears all local cached credentials.',
            isGX: isGX,
            accent: accent,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 10),
          _PolicyCard(
            icon: Icons.shield_outlined,
            title: isGX ? 'INFRASTRUCTURE POSTURE' : 'Infrastructure Security',
            body: isGX
                ? 'Backend cluster operates within an isolated VPC with restricted ingress rules. All data at rest is encrypted using AES-256. TLS 1.3 is enforced on all uplink channels.'
                : 'Our backend runs in an isolated private network. All stored data is encrypted at rest using AES-256. All connections are secured with TLS 1.3.',
            isGX: isGX,
            accent: accent,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 28),

          // ── Your rights ────────────────────────────────────────────────
          _SectionHeading(
            text: isGX ? 'YOUR RIGHTS' : 'Your Rights',
            isGX: isGX,
            accent: accent,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 12),
          _RightsGrid(isGX: isGX, accent: accent, colorScheme: colorScheme),
          const SizedBox(height: 28),

          // ── Third parties ──────────────────────────────────────────────
          _SectionHeading(
            text: isGX ? 'THIRD-PARTY SYSTEMS' : 'Third Parties',
            isGX: isGX,
            accent: accent,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 12),
          _ThirdPartyTable(
            isGX: isGX,
            accent: accent,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 28),

          // ── Data retention ─────────────────────────────────────────────
          _SectionHeading(
            text: isGX ? 'RETENTION SCHEDULE' : 'Data Retention',
            isGX: isGX,
            accent: accent,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 12),
          _RetentionTable(isGX: isGX, accent: accent, colorScheme: colorScheme),
          const SizedBox(height: 28),

          // ── Contact ────────────────────────────────────────────────────
          _ContactCard(isGX: isGX, accent: accent, colorScheme: colorScheme),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero banner
// ─────────────────────────────────────────────────────────────────────────────

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.isGX,
    required this.accent,
    required this.colorScheme,
  });

  final bool isGX;
  final Color accent;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    if (isGX) {
      return Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF12121E),
              border: Border.all(
                color: accent.withValues(alpha: 0.22),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: Icon(
                    Icons.admin_panel_settings_rounded,
                    color: accent,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ENCRYPTION MANIFESTO',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'All uplinks secured. Zero tracking. Data sovereignty guaranteed.',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Color(0xFF8888AA),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Top accent line
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(height: 1.5, color: accent.withValues(alpha: 0.7)),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.admin_panel_settings_rounded,
              color: colorScheme.primary,
              size: 32,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Privacy Matters',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'CipherChat is built around privacy-first architecture with no third-party trackers.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Meta row (last updated + version)
// ─────────────────────────────────────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.isGX,
    required this.accent,
    required this.colorScheme,
  });

  final bool isGX;
  final Color accent;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final chipColor = isGX ? accent : colorScheme.primary;
    final bgColor = isGX
        ? accent.withValues(alpha: 0.08)
        : colorScheme.primary.withValues(alpha: 0.08);
    final textStyle = isGX
        ? TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w700,
            color: chipColor,
          )
        : TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: chipColor,
          );

    Widget chip(IconData icon, String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(isGX ? 3 : 20),
        border: Border.all(
          color: chipColor.withValues(alpha: isGX ? 0.3 : 0.2),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: chipColor),
          const SizedBox(width: 5),
          Text(label, style: textStyle),
        ],
      ),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(
          Icons.calendar_today_rounded,
          isGX ? 'UPDATED: 2026-04-04' : 'Updated Apr 04, 2026',
        ),
        chip(Icons.tag_rounded, isGX ? 'VERSION: 1.0.0' : 'v1.0.0'),
        chip(Icons.public_rounded, isGX ? 'JURISDICTION: GLOBAL' : 'Global'),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section heading
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.text,
    required this.isGX,
    required this.accent,
    required this.colorScheme,
  });

  final String text;
  final bool isGX;
  final Color accent;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    if (isGX) {
      return Row(
        children: [
          Container(width: 2, height: 14, color: accent),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      );
    }
    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expandable card (dropdown)
// ─────────────────────────────────────────────────────────────────────────────

class _ExpandableCard extends StatefulWidget {
  const _ExpandableCard({
    required this.icon,
    required this.title,
    required this.summary,
    required this.detail,
    required this.isGX,
    required this.accent,
    required this.colorScheme,
  });

  final IconData icon;
  final String title;
  final String summary;
  final String detail;
  final bool isGX;
  final Color accent;
  final ColorScheme colorScheme;

  @override
  State<_ExpandableCard> createState() => _ExpandableCardState();
}

class _ExpandableCardState extends State<_ExpandableCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _rotate = Tween<double>(
      begin: 0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isGX = widget.isGX;
    final accent = widget.accent;
    final cs = widget.colorScheme;

    if (isGX) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF191926),
          border: Border.all(
            color: _expanded
                ? accent.withValues(alpha: 0.35)
                : accent.withValues(alpha: 0.15),
            width: 0.8,
          ),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: accent, size: 16),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.summary,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Color(0xFF8888AA),
                            ),
                          ),
                        ],
                      ),
                    ),
                    RotationTransition(
                      turns: _rotate,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: accent,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: _expanded
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: accent.withValues(alpha: 0.10),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          widget.detail,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: Color(0xFFCCCCDD),
                            height: 1.6,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }

    // Normal style
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      widget.icon,
                      color: cs.onSecondaryContainer,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.summary,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  RotationTransition(
                    turns: _rotate,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: cs.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        Divider(
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.detail,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Static policy card
// ─────────────────────────────────────────────────────────────────────────────

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.isGX,
    required this.accent,
    required this.colorScheme,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool isGX;
  final Color accent;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isGX) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF191926),
          border: Border.all(color: accent.withValues(alpha: 0.15), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: accent.withValues(alpha: 0.10),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, color: accent, size: 16),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 1.2,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                body,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  color: Color(0xFFCCCCDD),
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: colorScheme.onSecondaryContainer,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              body,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rights grid (2-column icon grid)
// ─────────────────────────────────────────────────────────────────────────────

class _RightsGrid extends StatelessWidget {
  const _RightsGrid({
    required this.isGX,
    required this.accent,
    required this.colorScheme,
  });

  final bool isGX;
  final Color accent;
  final ColorScheme colorScheme;

  static const _rights = [
    (
      Icons.download_rounded,
      'Access',
      'Request a full export of your stored data at any time.',
    ),
    (
      Icons.edit_rounded,
      'Rectify',
      'Correct inaccurate profile data via account settings.',
    ),
    (
      Icons.delete_forever_rounded,
      'Erase',
      'Delete your account and all its data permanently.',
    ),
    (
      Icons.block_rounded,
      'Restrict',
      'Limit how your data is processed without deleting.',
    ),
    (
      Icons.move_to_inbox_rounded,
      'Portability',
      'Receive your data in a machine-readable format.',
    ),
    (
      Icons.gavel_rounded,
      'Object',
      'Opt out of any processing beyond core functionality.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: _rights.map((r) {
        final (icon, title, body) = r;
        if (isGX) {
          return Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFF191926),
              border: Border.all(
                color: accent.withValues(alpha: 0.15),
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: accent, size: 16),
                const SizedBox(height: 7),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Color(0xFF8888AA),
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: colorScheme.primary, size: 18),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Third-party table
// ─────────────────────────────────────────────────────────────────────────────

class _ThirdPartyTable extends StatelessWidget {
  const _ThirdPartyTable({
    required this.isGX,
    required this.accent,
    required this.colorScheme,
  });

  final bool isGX;
  final Color accent;
  final ColorScheme colorScheme;

  static const _rows = [
    ('Supabase', 'Database & Auth', 'EU / US', 'Required'),
    ('APNS / FCM', 'Push Notifications', 'Apple / Google', 'Optional'),
    ('Sentry', 'Crash Reporting', 'US', 'Optional'),
  ];

  @override
  Widget build(BuildContext context) {
    final borderColor = isGX
        ? accent.withValues(alpha: 0.15)
        : colorScheme.outlineVariant.withValues(alpha: 0.5);
    final headerBg = isGX
        ? accent.withValues(alpha: 0.08)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final headerText = isGX ? accent : colorScheme.onSurfaceVariant;
    final bodyText = isGX ? const Color(0xFFCCCCDD) : colorScheme.onSurface;
    final subText = isGX
        ? const Color(0xFF8888AA)
        : colorScheme.onSurfaceVariant;
    final monoStyle = isGX
        ? const TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            letterSpacing: 0.8,
          )
        : null;

    final radius = isGX ? 0.0 : 14.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: 0.8),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Column(
          children: [
            // Header
            Container(
              color: headerBg,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      isGX ? 'VENDOR' : 'Service',
                      style: (monoStyle ?? const TextStyle()).copyWith(
                        fontWeight: FontWeight.w700,
                        color: headerText,
                        fontSize: isGX ? 10 : 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      isGX ? 'PURPOSE' : 'Purpose',
                      style: (monoStyle ?? const TextStyle()).copyWith(
                        fontWeight: FontWeight.w700,
                        color: headerText,
                        fontSize: isGX ? 10 : 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      isGX ? 'REGION' : 'Region',
                      style: (monoStyle ?? const TextStyle()).copyWith(
                        fontWeight: FontWeight.w700,
                        color: headerText,
                        fontSize: isGX ? 10 : 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      isGX ? 'STATUS' : 'Status',
                      style: (monoStyle ?? const TextStyle()).copyWith(
                        fontWeight: FontWeight.w700,
                        color: headerText,
                        fontSize: isGX ? 10 : 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ..._rows.asMap().entries.map((entry) {
              final i = entry.key;
              final (vendor, purpose, region, status) = entry.value;
              final isLast = i == _rows.length - 1;
              final isRequired = status == 'Required';
              final statusColor = isRequired
                  ? (isGX ? accent : colorScheme.primary)
                  : (isGX
                        ? const Color(0xFF8888AA)
                        : colorScheme.onSurfaceVariant);

              return Container(
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : Border(
                          bottom: BorderSide(color: borderColor, width: 0.5),
                        ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        vendor,
                        style: (monoStyle ?? const TextStyle()).copyWith(
                          fontWeight: FontWeight.w600,
                          color: bodyText,
                          fontSize: isGX ? 11 : 13,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        purpose,
                        style: (monoStyle ?? const TextStyle()).copyWith(
                          color: subText,
                          fontSize: isGX ? 10 : 12,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        region,
                        style: (monoStyle ?? const TextStyle()).copyWith(
                          color: subText,
                          fontSize: isGX ? 10 : 12,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(isGX ? 2 : 8),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.3),
                            width: 0.6,
                          ),
                        ),
                        child: Text(
                          isGX ? status.toUpperCase() : status,
                          style: (monoStyle ?? const TextStyle()).copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: isGX ? 9 : 11,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Retention schedule table
// ─────────────────────────────────────────────────────────────────────────────

class _RetentionTable extends StatelessWidget {
  const _RetentionTable({
    required this.isGX,
    required this.accent,
    required this.colorScheme,
  });

  final bool isGX;
  final Color accent;
  final ColorScheme colorScheme;

  static const _rows = [
    (
      Icons.chat_rounded,
      'Message ciphertext',
      'Until deleted by sender or recipient',
    ),
    (Icons.person_rounded, 'Profile metadata', 'Until account deletion'),
    (
      Icons.image_rounded,
      'Media attachments',
      'Until deleted by sender or recipient',
    ),
    (Icons.history_rounded, 'Auth session logs', '30 days rolling window'),
    (Icons.bug_report_rounded, 'Crash reports', '90 days'),
  ];

  @override
  Widget build(BuildContext context) {
    final borderColor = isGX
        ? accent.withValues(alpha: 0.15)
        : colorScheme.outlineVariant.withValues(alpha: 0.5);
    final radius = isGX ? 0.0 : 14.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: 0.8),
          borderRadius: BorderRadius.circular(radius),
          color: isGX ? const Color(0xFF191926) : null,
        ),
        child: Column(
          children: _rows.asMap().entries.map((entry) {
            final i = entry.key;
            final (icon, dataType, period) = entry.value;
            final isLast = i == _rows.length - 1;

            return Container(
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(color: borderColor, width: 0.5),
                      ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isGX ? accent : colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGX ? dataType.toUpperCase() : dataType,
                          style: TextStyle(
                            fontFamily: isGX ? 'monospace' : null,
                            fontSize: isGX ? 11 : 13,
                            letterSpacing: isGX ? 0.8 : 0,
                            fontWeight: FontWeight.w600,
                            color: isGX
                                ? const Color(0xFFF0F0F8)
                                : colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          period,
                          style: TextStyle(
                            fontFamily: isGX ? 'monospace' : null,
                            fontSize: isGX ? 10 : 12,
                            color: isGX
                                ? const Color(0xFF8888AA)
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contact card
// ─────────────────────────────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.isGX,
    required this.accent,
    required this.colorScheme,
  });

  final bool isGX;
  final Color accent;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    if (isGX) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF12121E),
          border: Border.all(color: accent.withValues(alpha: 0.22), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 2, height: 14, color: accent),
                const SizedBox(width: 8),
                Text(
                  'CONTACT CHANNEL',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Privacy inquiries, data requests, and erasure commands can be directed to the secure contact endpoint below.',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFF8888AA),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.07),
                border: Border.all(
                  color: accent.withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.alternate_email_rounded, color: accent, size: 14),
                  const SizedBox(width: 10),
                  Text(
                    'privacy@cipherchat.app',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      letterSpacing: 0.6,
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contact Us',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'For privacy inquiries, data access requests, or erasure requests, reach out at:',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.25),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.alternate_email_rounded,
                    color: colorScheme.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'privacy@cipherchat.app',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
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
