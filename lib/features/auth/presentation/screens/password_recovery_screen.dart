import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/app_error_helper.dart';
import '../../../../core/widgets/app_error_card.dart';
import '../providers/auth_provider.dart';

class PasswordRecoveryScreen extends ConsumerStatefulWidget {
  const PasswordRecoveryScreen({
    super.key,
    this.resetMode = false,
    this.initialErrorMessage,
  });

  final bool resetMode;
  final String? initialErrorMessage;

  @override
  ConsumerState<PasswordRecoveryScreen> createState() =>
      _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState
    extends ConsumerState<PasswordRecoveryScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _requestFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  bool _isSubmitting = false;
  bool _didUpdatePassword = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  String? _noticeMessage;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  @override
  void initState() {
    super.initState();
    _errorMessage = widget.initialErrorMessage;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _canResetPassword {
    final currentUserId = ref.read(currentUserIdProvider);
    return widget.resetMode &&
        currentUserId != null &&
        (widget.initialErrorMessage?.trim().isEmpty ?? true);
  }

  Future<void> _sendResetEmail() async {
    if (!(_requestFormKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _noticeMessage = null;
      _emailError = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordResetEmail(_emailController.text.trim());
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _noticeMessage =
            'Check your email for a password reset link. Open it on this device to continue.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _emailError = AppErrorHelper.passwordRecoveryEmailErrorFor(error);
        _errorMessage = _emailError == null
            ? AppErrorHelper.messageFor(error)
            : null;
      });
    }
  }

  Future<void> _updatePassword() async {
    final password = _passwordController.text;
    final passwordError = AppErrorHelper.passwordStrengthMessage(password);
    final confirmPassword = _confirmPasswordController.text;
    final confirmError = confirmPassword != password
        ? 'Passwords do not match.'
        : null;

    if (passwordError != null || confirmError != null) {
      setState(() {
        _passwordError = passwordError;
        _confirmPasswordError = confirmError;
        _errorMessage = null;
      });
      return;
    }

    if (!(_resetFormKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _noticeMessage = null;
      _passwordError = null;
      _confirmPasswordError = null;
    });

    try {
      await ref.read(authRepositoryProvider).updatePassword(password.trim());
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _didUpdatePassword = true;
        _noticeMessage =
            'Password updated successfully. You can continue to CipherChat now.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _passwordError = AppErrorHelper.passwordRecoveryPasswordErrorFor(error);
        _errorMessage = _passwordError == null
            ? AppErrorHelper.messageFor(error)
            : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isResetFlow = _canResetPassword && !_didUpdatePassword;

    return Scaffold(
      appBar: AppBar(
        title: Text(isResetFlow ? 'Set New Password' : 'Password Recovery'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isResetFlow
                            ? 'Choose a new password'
                            : _didUpdatePassword
                            ? 'Password updated'
                            : 'Reset your password',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isResetFlow
                            ? 'Use 8+ characters with uppercase, lowercase, and a number.'
                            : _didUpdatePassword
                            ? 'Your recovery session is complete.'
                            : 'Enter your email and we will send you a recovery link.',
                      ),
                      const SizedBox(height: 20),
                      if (_errorMessage != null) ...[
                        AppErrorCard(message: _errorMessage!),
                        const SizedBox(height: 16),
                      ],
                      if (_noticeMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer
                                .withAlpha(102),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _noticeMessage!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_didUpdatePassword)
                        FilledButton(
                          onPressed: () => context.go('/'),
                          child: const Text('Continue to App'),
                        )
                      else if (isResetFlow)
                        Form(
                          key: _resetFormKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText: 'New Password',
                                  prefixIcon: const Icon(Icons.lock),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),
                                forceErrorText: _passwordError,
                                onChanged: (_) {
                                  if (_passwordError != null ||
                                      _confirmPasswordError != null ||
                                      _errorMessage != null) {
                                    setState(() {
                                      _passwordError = null;
                                      _confirmPasswordError = null;
                                      _errorMessage = null;
                                    });
                                  }
                                },
                                validator:
                                    AppErrorHelper.passwordStrengthMessage,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: _obscureConfirmPassword,
                                decoration: InputDecoration(
                                  labelText: 'Confirm Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirmPassword
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                    ),
                                    onPressed: () => setState(
                                      () => _obscureConfirmPassword =
                                          !_obscureConfirmPassword,
                                    ),
                                  ),
                                ),
                                forceErrorText: _confirmPasswordError,
                                onChanged: (_) {
                                  if (_confirmPasswordError != null ||
                                      _errorMessage != null) {
                                    setState(() {
                                      _confirmPasswordError = null;
                                      _errorMessage = null;
                                    });
                                  }
                                },
                                validator: (value) {
                                  if ((value ?? '').trim().isEmpty) {
                                    return 'Please confirm your password.';
                                  }
                                  if (value != _passwordController.text) {
                                    return 'Passwords do not match.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              FilledButton(
                                onPressed: _isSubmitting
                                    ? null
                                    : _updatePassword,
                                child: _isSubmitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Update Password'),
                              ),
                            ],
                          ),
                        )
                      else
                        Form(
                          key: _requestFormKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.email),
                                ),
                                forceErrorText: _emailError,
                                onChanged: (_) {
                                  if (_emailError != null ||
                                      _errorMessage != null) {
                                    setState(() {
                                      _emailError = null;
                                      _errorMessage = null;
                                    });
                                  }
                                },
                                validator:
                                    AppErrorHelper.emailValidationMessage,
                              ),
                              const SizedBox(height: 24),
                              FilledButton(
                                onPressed: _isSubmitting
                                    ? null
                                    : _sendResetEmail,
                                child: _isSubmitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Send Recovery Link'),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _isSubmitting
                                    ? null
                                    : () => context.go('/'),
                                child: const Text('Back to Login'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
