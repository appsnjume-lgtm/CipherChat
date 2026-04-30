import 'package:flutter/material.dart';

class EncryptedTooltip extends StatelessWidget {
  const EncryptedTooltip({
    super.key,
    required this.encrypted,
    required this.decrypted,
    required this.child,
  });

  final String encrypted;
  final String decrypted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      waitDuration: const Duration(milliseconds: 250),
      message: 'ENC: $encrypted\nDEC: $decrypted',
      child: child,
    );
  }
}
