import 'package:flutter/material.dart';

class ProfileInfoSection extends StatelessWidget {
  const ProfileInfoSection({
    super.key,
    required this.gender,
    required this.bio,
    required this.isGenderVisible,
    required this.isBioVisible,
  });

  final String? gender;
  final String? bio;
  final bool isGenderVisible;
  final bool isBioVisible;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Info',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: 'Gender',
              value: !isGenderVisible
                  ? 'Hidden'
                  : (gender == null || gender!.trim().isEmpty)
                  ? 'Not set'
                  : gender!,
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: 'About',
              value: !isBioVisible
                  ? 'Hidden'
                  : (bio == null || bio!.trim().isEmpty)
                  ? 'No bio yet'
                  : bio!,
              multiline: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge,
          maxLines: multiline ? null : 1,
          overflow: multiline ? null : TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
