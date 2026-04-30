import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/local_profile_cache_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/startup/app_startup.dart';
import '../../../../core/utils/app_error_helper.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/entities/app_user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  final localProfileCache = ref.watch(localProfileCacheServiceProvider);
  return AuthRepository(client, localProfileCache);
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authControllerProvider).session?.user.id;
});

final currentUserProfileProvider = Provider<AppUser?>((ref) {
  return ref.watch(authControllerProvider).profile;
});

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    if (!AppConstants.isSupabaseConfigured) {
      return AuthController.unconfigured();
    }

    return AuthController(ref.watch(authRepositoryProvider));
  },
);

const _unset = Object();

class AuthState {
  const AuthState({
    required this.session,
    required this.profile,
    required this.isSessionLoading,
    required this.isLoginLoading,
    required this.isSignUpLoading,
    required this.isProfileLoading,
    required this.isInitializing,
    required this.isEmailVerificationSent,
    required this.errorMessage,
    required this.loginEmailError,
    required this.loginPasswordError,
    required this.signUpEmailError,
    required this.signUpPasswordError,
    required this.profileUsernameError,
    required this.anonymousUsernameError,
  });

  factory AuthState.initial() {
    return const AuthState(
      session: null,
      profile: null,
      isSessionLoading: false,
      isLoginLoading: false,
      isSignUpLoading: false,
      isProfileLoading: false,
      isInitializing: true,
      isEmailVerificationSent: false,
      errorMessage: null,
      loginEmailError: null,
      loginPasswordError: null,
      signUpEmailError: null,
      signUpPasswordError: null,
      profileUsernameError: null,
      anonymousUsernameError: null,
    );
  }

  final Session? session;
  final AppUser? profile;
  final bool isSessionLoading;
  final bool isLoginLoading;
  final bool isSignUpLoading;
  final bool isProfileLoading;
  final bool isInitializing;
  final bool isEmailVerificationSent;
  final String? errorMessage;
  final String? loginEmailError;
  final String? loginPasswordError;
  final String? signUpEmailError;
  final String? signUpPasswordError;
  final String? profileUsernameError;
  final String? anonymousUsernameError;

  bool get isLoading =>
      isSessionLoading || isLoginLoading || isSignUpLoading || isProfileLoading;

  bool get isAuthenticated => session != null;

  bool get needsProfileSetup =>
      session != null && profile == null && !isSessionLoading;

  AuthState copyWith({
    Object? session = _unset,
    Object? profile = _unset,
    bool? isSessionLoading,
    bool? isLoginLoading,
    bool? isSignUpLoading,
    bool? isProfileLoading,
    bool? isInitializing,
    bool? isEmailVerificationSent,
    Object? errorMessage = _unset,
    Object? loginEmailError = _unset,
    Object? loginPasswordError = _unset,
    Object? signUpEmailError = _unset,
    Object? signUpPasswordError = _unset,
    Object? profileUsernameError = _unset,
    Object? anonymousUsernameError = _unset,
  }) {
    return AuthState(
      session: session == _unset ? this.session : session as Session?,
      profile: profile == _unset ? this.profile : profile as AppUser?,
      isSessionLoading: isSessionLoading ?? this.isSessionLoading,
      isLoginLoading: isLoginLoading ?? this.isLoginLoading,
      isSignUpLoading: isSignUpLoading ?? this.isSignUpLoading,
      isProfileLoading: isProfileLoading ?? this.isProfileLoading,
      isInitializing: isInitializing ?? this.isInitializing,
      isEmailVerificationSent:
          isEmailVerificationSent ?? this.isEmailVerificationSent,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
      loginEmailError: loginEmailError == _unset
          ? this.loginEmailError
          : loginEmailError as String?,
      loginPasswordError: loginPasswordError == _unset
          ? this.loginPasswordError
          : loginPasswordError as String?,
      signUpEmailError: signUpEmailError == _unset
          ? this.signUpEmailError
          : signUpEmailError as String?,
      signUpPasswordError: signUpPasswordError == _unset
          ? this.signUpPasswordError
          : signUpPasswordError as String?,
      profileUsernameError: profileUsernameError == _unset
          ? this.profileUsernameError
          : profileUsernameError as String?,
      anonymousUsernameError: anonymousUsernameError == _unset
          ? this.anonymousUsernameError
          : anonymousUsernameError as String?,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(AuthRepository repository)
    : _repository = repository,
      super(AuthState.initial()) {
    _bootstrap();
    _subscription = repository.authStateChanges().listen(_handleSessionChanged);
  }

  AuthController.unconfigured()
    : _repository = null,
      super(AuthState.initial().copyWith(isInitializing: false));

  final AuthRepository? _repository;
  StreamSubscription<Session?>? _subscription;
  bool _isCompletingAnonymousSignIn = false;

  Future<void> _bootstrap() async {
    await _handleSessionChanged(_repository?.currentSession);
  }

  Future<void> _handleSessionChanged(Session? session) async {
    final repository = _repository;
    if (repository == null) {
      state = state.copyWith(isInitializing: false);
      return;
    }

    if (session == null) {
      _isCompletingAnonymousSignIn = false;
      state = AuthState.initial().copyWith(isInitializing: false);
      return;
    }

    if (_isCompletingAnonymousSignIn) {
      state = _clearAllFormErrors(
        state.copyWith(
          session: session,
          profile: null,
          isSessionLoading: true,
          isLoginLoading: true,
          isSignUpLoading: false,
          isProfileLoading: false,
          isInitializing: false,
          isEmailVerificationSent: false,
          errorMessage: null,
        ),
      );
      return;
    }

    state = _clearAllFormErrors(
      state.copyWith(
        session: session,
        profile: null,
        isSessionLoading: true,
        isLoginLoading: false,
        isSignUpLoading: false,
        isProfileLoading: true,
        isInitializing: false,
        isEmailVerificationSent: false,
        errorMessage: null,
      ),
    );

    final cachedProfile = await repository.fetchCachedProfile(session.user.id);
    if (cachedProfile != null) {
      state = state.copyWith(
        session: session,
        profile: cachedProfile,
        isSessionLoading: false,
        isProfileLoading: true,
        isInitializing: false,
        errorMessage: null,
      );
    } else {
      state = state.copyWith(
        session: session,
        profile: null,
        isSessionLoading: false,
        isProfileLoading: true,
        isInitializing: false,
      );
    }

    unawaited(
      _fetchProfileForSession(session, cachedProfile: cachedProfile),
    );
  }

  Future<void> _fetchProfileForSession(
    Session session, {
    AppUser? cachedProfile,
  }) async {
    final repository = _repository;
    if (repository == null) {
      return;
    }

    try {
      final profile = await StartupTrace.async(
        'Profile fetch',
        () => repository.fetchProfile(session.user.id),
      );
      if (!_isCurrentSession(session)) {
        return;
      }

      if (profile != null) {
        final visibleProfile = profile.copyWith(
          isOnline: true,
          lastSeenAt: DateTime.now(),
        );
        state = _clearAllFormErrors(
          state.copyWith(
            session: session,
            profile: visibleProfile,
            isSessionLoading: false,
            isProfileLoading: false,
            isInitializing: false,
            errorMessage: null,
          ),
        );
        unawaited(repository.touchLastSeen(session.user.id));
      } else {
        state = state.copyWith(
          session: session,
          profile: null,
          isSessionLoading: false,
          isProfileLoading: false,
          isInitializing: false,
        );
      }
    } catch (error) {
      if (!_isCurrentSession(session)) {
        return;
      }

      if (cachedProfile != null) {
        state = state.copyWith(
          session: session,
          profile: cachedProfile,
          isSessionLoading: false,
          isProfileLoading: false,
          isInitializing: false,
          errorMessage: null,
        );
        return;
      }

      state = _clearAllFormErrors(
        state.copyWith(
          session: session,
          profile: null,
          isSessionLoading: false,
          isProfileLoading: false,
          isInitializing: false,
          errorMessage: AppErrorHelper.messageFor(error),
        ),
      );
    }
  }

  bool _isCurrentSession(Session session) {
    return state.session?.user.id == session.user.id;
  }

  Future<void> signInAnonymously({
    required String username,
    required AppGender gender,
  }) async {
    final repository = _repository;
    if (repository == null) {
      return;
    }

    final usernameError = AppErrorHelper.optionalUsernameValidationMessage(
      username,
    );
    if (usernameError != null) {
      state = state.copyWith(
        isLoginLoading: false,
        errorMessage: null,
        anonymousUsernameError: usernameError,
        loginEmailError: null,
        loginPasswordError: null,
      );
      return;
    }

    state = state.copyWith(
      isLoginLoading: true,
      errorMessage: null,
      anonymousUsernameError: null,
      loginEmailError: null,
      loginPasswordError: null,
    );

    try {
      _isCompletingAnonymousSignIn = true;
      final response = await repository.signInAnonymously();
      final userId = response.user?.id ?? repository.currentSession?.user.id;
      if (userId == null) {
        throw Exception('No user returned from anonymous sign-in.');
      }

      final profile = await repository.createProfile(
        userId: userId,
        username: username.trim().isEmpty
            ? repository.generateAnonymousUsername(userId)
            : username.trim(),
        gender: gender,
      );

      _isCompletingAnonymousSignIn = false;
      state = _clearAllFormErrors(
        state.copyWith(
          session: repository.currentSession,
          profile: profile,
          isSessionLoading: false,
          isLoginLoading: false,
          isSignUpLoading: false,
          isProfileLoading: false,
          isInitializing: false,
          errorMessage: null,
        ),
      );
    } catch (error) {
      _isCompletingAnonymousSignIn = false;
      final usernameFieldError = AppErrorHelper.usernameErrorFor(error);
      state = state.copyWith(
        isLoginLoading: false,
        errorMessage: usernameFieldError == null
            ? AppErrorHelper.messageFor(error)
            : null,
        anonymousUsernameError: usernameFieldError,
      );
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final repository = _repository;
    if (repository == null) {
      return;
    }

    final emailError = AppErrorHelper.emailValidationMessage(email);
    final passwordError = AppErrorHelper.requiredPasswordMessage(password);
    if (emailError != null || passwordError != null) {
      state = state.copyWith(
        isLoginLoading: false,
        errorMessage: null,
        loginEmailError: emailError,
        loginPasswordError: passwordError,
      );
      return;
    }

    state = state.copyWith(
      isLoginLoading: true,
      errorMessage: null,
      loginEmailError: null,
      loginPasswordError: null,
    );

    try {
      await repository.signInWithEmail(email: email.trim(), password: password);
    } catch (error) {
      final resolvedEmailError = AppErrorHelper.loginEmailErrorFor(error);
      final resolvedPasswordError = AppErrorHelper.loginPasswordErrorFor(error);
      state = state.copyWith(
        isLoginLoading: false,
        errorMessage:
            resolvedEmailError == null && resolvedPasswordError == null
            ? AppErrorHelper.messageFor(error)
            : null,
        loginEmailError: resolvedEmailError,
        loginPasswordError: resolvedPasswordError,
      );
    }
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final repository = _repository;
    if (repository == null) {
      return;
    }

    final emailError = AppErrorHelper.emailValidationMessage(email);
    final passwordError = AppErrorHelper.passwordStrengthMessage(password);
    if (emailError != null || passwordError != null) {
      state = state.copyWith(
        isSignUpLoading: false,
        errorMessage: null,
        signUpEmailError: emailError,
        signUpPasswordError: passwordError,
      );
      return;
    }

    state = state.copyWith(
      isSignUpLoading: true,
      errorMessage: null,
      signUpEmailError: null,
      signUpPasswordError: null,
    );

    try {
      await repository.signUpWithEmail(email: email.trim(), password: password);

      state = _clearAllFormErrors(
        state.copyWith(
          isSignUpLoading: false,
          isEmailVerificationSent: true,
          errorMessage: null,
        ),
      );
    } catch (error) {
      final resolvedEmailError = AppErrorHelper.signUpEmailErrorFor(error);
      final resolvedPasswordError = AppErrorHelper.signUpPasswordErrorFor(
        error,
      );
      state = state.copyWith(
        isSignUpLoading: false,
        errorMessage:
            resolvedEmailError == null && resolvedPasswordError == null
            ? AppErrorHelper.messageFor(error)
            : null,
        signUpEmailError: resolvedEmailError,
        signUpPasswordError: resolvedPasswordError,
      );
    }
  }

  Future<void> completeProfile({
    required String username,
    required AppGender gender,
  }) async {
    final repository = _repository;
    final session = state.session;
    if (repository == null || session == null) {
      return;
    }

    final usernameError = AppErrorHelper.usernameValidationMessage(username);
    if (usernameError != null) {
      state = state.copyWith(
        isProfileLoading: false,
        errorMessage: null,
        profileUsernameError: usernameError,
      );
      return;
    }

    state = state.copyWith(
      isProfileLoading: true,
      errorMessage: null,
      profileUsernameError: null,
    );

    try {
      final profile = await repository.createProfile(
        userId: session.user.id,
        username: username.trim(),
        gender: gender,
      );
      state = state.copyWith(
        profile: profile,
        isProfileLoading: false,
        profileUsernameError: null,
      );
    } catch (error) {
      final resolvedUsernameError = AppErrorHelper.usernameErrorFor(error);
      state = state.copyWith(
        isProfileLoading: false,
        errorMessage: resolvedUsernameError == null
            ? AppErrorHelper.messageFor(error)
            : null,
        profileUsernameError: resolvedUsernameError,
      );
    }
  }

  Future<void> updateProfile({
    String? username,
    AppGender? gender,
    String? avatarId,
    String? profileImageUrl,
    bool clearProfileImage = false,
    String? bio,
    AppVisibility? genderVisibility,
    AppVisibility? profilePhotoVisibility,
    AppVisibility? lastSeenVisibility,
    AppVisibility? aboutVisibility,
    AccountPrivacy? accountPrivacy,
    bool? readReceiptsEnabled,
    bool? typingIndicatorEnabled,
    bool? enterToSendEnabled,
    bool? messageNotificationsEnabled,
    bool? groupNotificationsEnabled,
    bool? notificationPreviewEnabled,
    AutoDownloadSetting? autoDownloadMedia,
    MediaQualityPreference? mediaQualityPreference,
    CallPermission? whoCanCall,
  }) async {
    final repository = _repository;
    final session = state.session;
    if (repository == null || session == null) {
      return;
    }

    state = state.copyWith(isProfileLoading: true, errorMessage: null);

    try {
      final profile = await repository.updateProfile(
        userId: session.user.id,
        username: username,
        gender: gender,
        avatarId: avatarId,
        profileImageUrl: profileImageUrl,
        clearProfileImage: clearProfileImage,
        bio: bio,
        genderVisibility: genderVisibility,
        profilePhotoVisibility: profilePhotoVisibility,
        lastSeenVisibility: lastSeenVisibility,
        aboutVisibility: aboutVisibility,
        accountPrivacy: accountPrivacy,
        readReceiptsEnabled: readReceiptsEnabled,
        typingIndicatorEnabled: typingIndicatorEnabled,
        enterToSendEnabled: enterToSendEnabled,
        messageNotificationsEnabled: messageNotificationsEnabled,
        groupNotificationsEnabled: groupNotificationsEnabled,
        notificationPreviewEnabled: notificationPreviewEnabled,
        autoDownloadMedia: autoDownloadMedia,
        mediaQualityPreference: mediaQualityPreference,
        whoCanCall: whoCanCall,
      );
      state = state.copyWith(profile: profile, isProfileLoading: false);
    } catch (error) {
      state = state.copyWith(
        isProfileLoading: false,
        errorMessage: AppErrorHelper.messageFor(error),
      );
    }
  }

  Future<void> uploadProfileImage(String sourcePath) async {
    final repository = _repository;
    final session = state.session;
    if (repository == null || session == null) {
      return;
    }

    state = state.copyWith(isProfileLoading: true, errorMessage: null);

    try {
      final profile = await repository.uploadProfileImage(
        userId: session.user.id,
        sourcePath: sourcePath,
      );
      state = state.copyWith(profile: profile, isProfileLoading: false);
    } catch (error) {
      state = state.copyWith(
        isProfileLoading: false,
        errorMessage: AppErrorHelper.messageFor(error),
      );
    }
  }

  Future<void> removeProfileImage() async {
    final repository = _repository;
    final session = state.session;
    final profile = state.profile;
    if (repository == null || session == null || profile == null) {
      return;
    }

    state = state.copyWith(isProfileLoading: true, errorMessage: null);

    try {
      final updatedProfile = await repository.removeProfileImage(
        userId: session.user.id,
        existingPath: profile.profileImageUrl,
      );
      state = state.copyWith(profile: updatedProfile, isProfileLoading: false);
    } catch (error) {
      state = state.copyWith(
        isProfileLoading: false,
        errorMessage: AppErrorHelper.messageFor(error),
      );
    }
  }

  Future<void> refreshProfile() async {
    final repository = _repository;
    final session = state.session;
    if (repository == null || session == null) {
      return;
    }

    try {
      final profile = await StartupTrace.async(
        'Profile refresh',
        () => repository.fetchProfile(session.user.id),
      );
      state = state.copyWith(profile: profile);
    } catch (_) {
      // Silent refresh should never disturb the active UI.
    }
  }

  Future<void> signOut() async {
    final repository = _repository;
    final session = state.session;
    if (repository == null) {
      return;
    }

    if (session != null) {
      try {
        await repository.setOnlineStatus(
          userId: session.user.id,
          isOnline: false,
        );
      } catch (_) {
        // If presence cleanup fails, we still sign out the user locally.
      }
    }

    await repository.signOut();
    state = AuthState.initial().copyWith(
      isInitializing: false,
      isSessionLoading: false,
    );
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  void clearLoginErrors() {
    state = state.copyWith(
      errorMessage: null,
      loginEmailError: null,
      loginPasswordError: null,
    );
  }

  void clearSignUpErrors() {
    state = state.copyWith(
      errorMessage: null,
      signUpEmailError: null,
      signUpPasswordError: null,
    );
  }

  void clearProfileSetupErrors() {
    state = state.copyWith(errorMessage: null, profileUsernameError: null);
  }

  void clearAnonymousErrors() {
    state = state.copyWith(errorMessage: null, anonymousUsernameError: null);
  }

  AuthState _clearAllFormErrors(AuthState nextState) {
    return nextState.copyWith(
      loginEmailError: null,
      loginPasswordError: null,
      signUpEmailError: null,
      signUpPasswordError: null,
      profileUsernameError: null,
      anonymousUsernameError: null,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
