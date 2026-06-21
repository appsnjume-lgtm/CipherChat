import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/app_error_helper.dart';
import '../../../../core/widgets/app_error_card.dart';
import '../../domain/entities/app_user.dart';
import '../providers/auth_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _signUpEmailController = TextEditingController();
  final _signUpPasswordController = TextEditingController();
  final _anonymousUsernameController = TextEditingController();
  final _profileUsernameController = TextEditingController();

  final _loginFormKey = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();
  final _anonymousFormKey = GlobalKey<FormState>();
  final _profileFormKey = GlobalKey<FormState>();

  AppGender _anonymousGender = AppGender.male;
  AppGender _profileGender = AppGender.male;

  bool _obscureLoginPassword = true;
  bool _obscureSignUpPassword = true;

  @override
  void dispose() {
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _signUpEmailController.dispose();
    _signUpPasswordController.dispose();
    _anonymousUsernameController.dispose();
    _profileUsernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final authController = ref.read(authControllerProvider.notifier);
    final theme = Theme.of(context);

    if (authState.isEmailVerificationSent) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.mark_email_read_outlined,
                  size: 80,
                  color: Colors.blue,
                ),
                const SizedBox(height: 24),
                Text(
                  'Check your email',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'We\'ve sent a confirmation link to your email. Please verify your account to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => authController.signOut(),
                  child: const Text('Back to Login'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(title: const Text('Welcome to CipherChat')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    if (authState.errorMessage != null) ...[
                      AppErrorCard(
                        message: authState.errorMessage!,
                        actionLabel: 'Dismiss',
                        onAction: authController.clearError,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (authState.needsProfileSetup)
                      _ProfileCompletionCard(
                        formKey: _profileFormKey,
                        controller: _profileUsernameController,
                        usernameError: authState.profileUsernameError,
                        gender: _profileGender,
                        isLoading: authState.isProfileLoading,
                        onUsernameChanged: (_) {
                          authController.clearProfileSetupErrors();
                        },
                        onGenderChanged: (gender) {
                          setState(() {
                            _profileGender = gender;
                          });
                        },
                        onSubmit: () {
                          if (_profileFormKey.currentState?.validate() ??
                              false) {
                            authController.completeProfile(
                              username: _profileUsernameController.text,
                              gender: _profileGender,
                            );
                          }
                        },
                        onSignOut: authController.signOut,
                      )
                    else
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const TabBar(
                                tabs: [
                                  Tab(text: 'Login'),
                                  Tab(text: 'Sign Up'),
                                  Tab(text: 'Anonymous'),
                                ],
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 450,
                                child: TabBarView(
                                  children: [
                                    Form(
                                      key: _loginFormKey,
                                      autovalidateMode:
                                          AutovalidateMode.onUserInteraction,
                                      child: _AuthForm(
                                        title: 'Log in with email',
                                        fields: [
                                          TextFormField(
                                            controller: _loginEmailController,
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            decoration: const InputDecoration(
                                              labelText: 'Email',
                                              prefixIcon: Icon(Icons.email),
                                            ),
                                            forceErrorText:
                                                authState.loginEmailError,
                                            onChanged: (_) {
                                              authController.clearLoginErrors();
                                            },
                                            validator: (value) =>
                                                AppErrorHelper.emailValidationMessage(
                                                  value,
                                                ),
                                          ),
                                          const SizedBox(height: 16),
                                          TextFormField(
                                            controller:
                                                _loginPasswordController,
                                            obscureText: _obscureLoginPassword,
                                            decoration: InputDecoration(
                                              labelText: 'Password',
                                              prefixIcon: const Icon(
                                                Icons.lock,
                                              ),
                                              suffixIcon: IconButton(
                                                icon: Icon(
                                                  _obscureLoginPassword
                                                      ? Icons.visibility
                                                      : Icons.visibility_off,
                                                ),
                                                onPressed: () => setState(
                                                  () => _obscureLoginPassword =
                                                      !_obscureLoginPassword,
                                                ),
                                              ),
                                            ),
                                            forceErrorText:
                                                authState.loginPasswordError,
                                            onChanged: (_) {
                                              authController.clearLoginErrors();
                                            },
                                            validator: (value) =>
                                                AppErrorHelper.requiredPasswordMessage(
                                                  value,
                                                ),
                                          ),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton(
                                              onPressed:
                                                  authState.isLoginLoading
                                                  ? null
                                                  : () => context.push(
                                                      '/auth/recovery',
                                                    ),
                                              child: const Text(
                                                'Forgot password?',
                                              ),
                                            ),
                                          ),
                                        ],
                                        buttonLabel: 'Log In',
                                        isLoading: authState.isLoginLoading,
                                        onPressed: () {
                                          if (_loginFormKey.currentState
                                                  ?.validate() ??
                                              false) {
                                            authController.signInWithEmail(
                                              email: _loginEmailController.text,
                                              password:
                                                  _loginPasswordController.text,
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                    Form(
                                      key: _signUpFormKey,
                                      autovalidateMode:
                                          AutovalidateMode.onUserInteraction,
                                      child: _AuthForm(
                                        title: 'Create a new account',
                                        description:
                                            'Start your journey with a secure account.',
                                        fields: [
                                          TextFormField(
                                            controller: _signUpEmailController,
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            decoration: const InputDecoration(
                                              labelText: 'Email',
                                              prefixIcon: Icon(Icons.email),
                                            ),
                                            forceErrorText:
                                                authState.signUpEmailError,
                                            onChanged: (_) {
                                              authController
                                                  .clearSignUpErrors();
                                            },
                                            validator: (value) =>
                                                AppErrorHelper.emailValidationMessage(
                                                  value,
                                                ),
                                          ),
                                          const SizedBox(height: 16),
                                          TextFormField(
                                            controller:
                                                _signUpPasswordController,
                                            obscureText: _obscureSignUpPassword,
                                            decoration: InputDecoration(
                                              labelText: 'Password',
                                              helperText:
                                                  'Use 8+ characters with uppercase, lowercase, and a number.',
                                              prefixIcon: const Icon(
                                                Icons.lock,
                                              ),
                                              suffixIcon: IconButton(
                                                icon: Icon(
                                                  _obscureSignUpPassword
                                                      ? Icons.visibility
                                                      : Icons.visibility_off,
                                                ),
                                                onPressed: () => setState(
                                                  () => _obscureSignUpPassword =
                                                      !_obscureSignUpPassword,
                                                ),
                                              ),
                                            ),
                                            forceErrorText:
                                                authState.signUpPasswordError,
                                            onChanged: (_) {
                                              authController
                                                  .clearSignUpErrors();
                                            },
                                            validator: (value) =>
                                                AppErrorHelper.passwordStrengthMessage(
                                                  value,
                                                ),
                                          ),
                                          const SizedBox(height: 24),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: theme
                                                  .colorScheme
                                                  .secondaryContainer
                                                  .withAlpha(102),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.info_outline_rounded,
                                                  size: 20,
                                                  color: theme
                                                      .colorScheme
                                                      .onSecondaryContainer,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    'You will need to confirm your email in the next step to finish setting up your profile.',
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: theme
                                                              .colorScheme
                                                              .onSecondaryContainer,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        buttonLabel: 'Create Account',
                                        isLoading: authState.isSignUpLoading,
                                        onPressed: () {
                                          if (_signUpFormKey.currentState
                                                  ?.validate() ??
                                              false) {
                                            authController.signUpWithEmail(
                                              email:
                                                  _signUpEmailController.text,
                                              password:
                                                  _signUpPasswordController
                                                      .text,
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                    Form(
                                      key: _anonymousFormKey,
                                      autovalidateMode:
                                          AutovalidateMode.onUserInteraction,
                                      child: _AuthForm(
                                        title: 'Jump in anonymously',
                                        description:
                                            'For demo flows, you can create an anonymous Supabase session and still get a profile row.',
                                        fields: [
                                          TextFormField(
                                            controller:
                                                _anonymousUsernameController,
                                            decoration: const InputDecoration(
                                              labelText:
                                                  'Username (optional for anonymous)',
                                              prefixIcon: Icon(Icons.person),
                                            ),
                                            forceErrorText: authState
                                                .anonymousUsernameError,
                                            onChanged: (_) {
                                              authController
                                                  .clearAnonymousErrors();
                                            },
                                            validator: (value) =>
                                                AppErrorHelper.optionalUsernameValidationMessage(
                                                  value,
                                                ),
                                          ),
                                          const SizedBox(height: 16),
                                          _GenderSelector(
                                            value: _anonymousGender,
                                            onChanged: (gender) {
                                              setState(() {
                                                _anonymousGender = gender;
                                              });
                                            },
                                          ),
                                        ],
                                        buttonLabel: 'Continue Anonymously',
                                        isLoading: authState.isLoginLoading,
                                        onPressed: () {
                                          if (_anonymousFormKey.currentState
                                                  ?.validate() ??
                                              false) {
                                            authController.signInAnonymously(
                                              username:
                                                  _anonymousUsernameController
                                                      .text,
                                              gender: _anonymousGender,
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

class _AuthForm extends StatelessWidget {
  const _AuthForm({
    required this.title,
    required this.fields,
    required this.buttonLabel,
    required this.isLoading,
    required this.onPressed,
    this.description,
  });

  final String title;
  final String? description;
  final List<Widget> fields;
  final String buttonLabel;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(description!),
        ],
        const SizedBox(height: 20),
        ...fields,
        const Spacer(),
        FilledButton(
          onPressed: isLoading ? null : onPressed,
          child: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(buttonLabel),
        ),
      ],
    );
  }
}

class _ProfileCompletionCard extends StatelessWidget {
  const _ProfileCompletionCard({
    required this.formKey,
    required this.controller,
    required this.usernameError,
    required this.gender,
    required this.isLoading,
    required this.onUsernameChanged,
    required this.onGenderChanged,
    required this.onSubmit,
    required this.onSignOut,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final String? usernameError;
  final AppGender gender;
  final bool isLoading;
  final ValueChanged<String> onUsernameChanged;
  final ValueChanged<AppGender> onGenderChanged;
  final VoidCallback onSubmit;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Finish your profile',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pick a username and gender to finish your profile. You can upload a custom profile photo later in Settings.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person),
                ),
                forceErrorText: usernameError,
                onChanged: onUsernameChanged,
                validator: (value) =>
                    AppErrorHelper.usernameValidationMessage(value),
              ),
              const SizedBox(height: 16),
              _GenderSelector(value: gender, onChanged: onGenderChanged),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: isLoading ? null : onSubmit,
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save Profile'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: isLoading ? null : () => onSignOut(),
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenderSelector extends StatelessWidget {
  const _GenderSelector({required this.value, required this.onChanged});

  final AppGender value;
  final ValueChanged<AppGender> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gender',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        SegmentedButton<AppGender>(
          showSelectedIcon: false,
          segments: AppGender.values
              .map(
                (gender) => ButtonSegment<AppGender>(
                  value: gender,
                  label: Text(gender.label),
                ),
              )
              .toList(),
          selected: {value},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}
