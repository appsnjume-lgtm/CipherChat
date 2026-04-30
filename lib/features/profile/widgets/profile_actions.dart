import 'package:flutter/material.dart';

class ProfileActions extends StatelessWidget {
  const ProfileActions({
    super.key,
    required this.label,
    required this.isEnabled,
    required this.onPressed,
    this.helperText,
  });

  final String label;
  final bool isEnabled;
  final VoidCallback? onPressed;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: isEnabled ? onPressed : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: Text(label),
        ),
        if (helperText != null && helperText!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            helperText!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
