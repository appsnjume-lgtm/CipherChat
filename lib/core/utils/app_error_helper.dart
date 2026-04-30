import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class AppErrorHelper {
  const AppErrorHelper._();

  static final RegExp _emailRegex = RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$');

  static String messageFor(Object error) {
    final normalized = _normalizedMessage(error);
    return _map(normalized);
  }

  static bool isNetworkRelated(Object error) {
    return _isNetworkError(_normalizedMessage(error));
  }

  static bool isPermanentOutgoingMessageFailure(Object error) {
    final normalized = _normalizedMessage(error);
    return _isPermissionError(normalized) ||
        _isReplyTargetError(normalized) ||
        _isAttachmentUnavailable(normalized) ||
        _isChatUnavailable(normalized) ||
        _isSessionError(normalized) ||
        normalized.contains('selected file no longer exists on disk') ||
        normalized.contains('pending text message is empty') ||
        normalized.contains('pending attachment path is missing');
  }

  static bool isNetworkMessage(String? message) {
    if (message == null || message.trim().isEmpty) {
      return false;
    }

    final normalized = message.trim().toLowerCase();
    return _isNetworkError(normalized) ||
        normalized.contains('we could not reach cipherchat right now');
  }

  static String? emailValidationMessage(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Email is required.';
    }
    if (!_emailRegex.hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? requiredPasswordMessage(String? value) {
    final password = value ?? '';
    if (password.trim().isEmpty) {
      return 'Password is required.';
    }
    return null;
  }

  static String? passwordStrengthMessage(String? value) {
    final password = value ?? '';
    if (password.trim().isEmpty) {
      return 'Password is required.';
    }
    if (password.length < 8) {
      return 'Use at least 8 characters.';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Add at least one uppercase letter.';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Add at least one lowercase letter.';
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      return 'Add at least one number.';
    }
    return null;
  }

  static String? usernameValidationMessage(
    String? value, {
    String label = 'Username',
  }) {
    final username = value?.trim() ?? '';
    if (username.isEmpty) {
      return '$label is required.';
    }
    if (username.length < 3) {
      return '$label must be at least 3 characters.';
    }
    if (username.length > 24) {
      return '$label must be 24 characters or fewer.';
    }
    if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(username)) {
      return '$label can use letters, numbers, dots, and underscores only.';
    }
    return null;
  }

  static String? optionalUsernameValidationMessage(
    String? value, {
    String label = 'Username',
  }) {
    final username = value?.trim() ?? '';
    if (username.isEmpty) {
      return null;
    }
    return usernameValidationMessage(username, label: label);
  }

  static String? loginEmailErrorFor(Object error) {
    final normalized = _normalizedMessage(error);
    if (_isInvalidEmail(normalized)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? loginPasswordErrorFor(Object error) {
    final normalized = _normalizedMessage(error);
    if (_isInvalidCredentials(normalized)) {
      return 'Email or password does not match.';
    }
    if (_isEmailNotConfirmed(normalized)) {
      return 'Confirm your email first, then try again.';
    }
    return null;
  }

  static String? signUpEmailErrorFor(Object error) {
    final normalized = _normalizedMessage(error);
    if (_isEmailAlreadyRegistered(normalized)) {
      return 'An account with this email already exists.';
    }
    if (_isInvalidEmail(normalized)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? signUpPasswordErrorFor(Object error) {
    final normalized = _normalizedMessage(error);
    if (_isWeakPassword(normalized)) {
      return 'Use 8+ characters with uppercase, lowercase, and a number.';
    }
    return null;
  }

  static String? passwordRecoveryEmailErrorFor(Object error) {
    final normalized = _normalizedMessage(error);
    if (_isInvalidEmail(normalized)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? passwordRecoveryPasswordErrorFor(Object error) {
    final normalized = _normalizedMessage(error);
    if (_isWeakPassword(normalized)) {
      return 'Use 8+ characters with uppercase, lowercase, and a number.';
    }
    if (_isRecoveryLinkInvalid(normalized)) {
      return 'This reset link is no longer valid. Request a new one.';
    }
    return null;
  }

  static String passwordRecoveryCallbackMessageFor(Object error) {
    final normalized = _normalizedMessage(error);
    if (_isRecoveryLinkInvalid(normalized) || _isSessionError(normalized)) {
      return 'This password reset link is invalid or has expired. Request a new one.';
    }
    return messageFor(error);
  }

  static String? usernameErrorFor(Object error) {
    final normalized = _normalizedMessage(error);
    if (_isUsernameTaken(normalized)) {
      return 'This username is already taken.';
    }
    return null;
  }

  static String _normalizedMessage(Object error) {
    if (error is AuthException) {
      return error.message.trim().toLowerCase();
    }

    if (error is PostgrestException) {
      return error.message.trim().toLowerCase();
    }

    if (error is SocketException) {
      return 'socketexception ${error.message}'.trim().toLowerCase();
    }

    return error.toString().trim().toLowerCase();
  }

  static String _map(String normalized) {
    if (_isNetworkError(normalized)) {
      return 'We could not reach CipherChat right now. Check your connection and try again.';
    }

    if (_isGridBreachSchemaMismatch(normalized)) {
      return 'Grid Breach needs the latest database update before this action can work.';
    }

    if (_isInvalidCredentials(normalized)) {
      return 'Email or password does not match.';
    }

    if (_isEmailNotConfirmed(normalized)) {
      return 'Confirm your email first, then try logging in again.';
    }

    if (_isEmailAlreadyRegistered(normalized)) {
      return 'An account with this email already exists. Try logging in instead.';
    }

    if (_isInvalidEmail(normalized)) {
      return 'That email address does not look valid.';
    }

    if (_isWeakPassword(normalized)) {
      return 'Use 8+ characters with uppercase, lowercase, and a number.';
    }

    if (_isUsernameTaken(normalized)) {
      return 'This username is already taken. Try another one.';
    }

    if (_isPermissionError(normalized)) {
      return 'You do not have permission to do that right now.';
    }

    if (_isReplyTargetError(normalized)) {
      return 'That replied message is no longer available in this chat.';
    }

    if (_isAttachmentUnavailable(normalized)) {
      return 'That file is not available right now. Reconnect and try again.';
    }

    if (_isChatUnavailable(normalized)) {
      return 'This chat is no longer available.';
    }

    if (_isSessionError(normalized)) {
      return 'Your session expired. Please sign in again.';
    }

    if (_isNoUserReturned(normalized)) {
      return 'We could not complete that sign-in. Please try again.';
    }

    return 'Something went wrong. Please try again in a moment.';
  }

  static bool _isNetworkError(String normalized) {
    return normalized.contains('socketexception') ||
        normalized.contains('failed host lookup') ||
        normalized.contains('network is unreachable') ||
        normalized.contains('no address associated with hostname') ||
        normalized.contains('name or service not known') ||
        normalized.contains('timed out') ||
        normalized.contains('timeoutexception') ||
        normalized.contains('connection refused') ||
        normalized.contains('connection reset') ||
        normalized.contains('connection closed') ||
        normalized.contains('clientexception with socketexception');
  }

  static bool _isInvalidCredentials(String normalized) {
    return normalized.contains('invalid login credentials') ||
        normalized.contains('invalid email or password');
  }

  static bool _isEmailNotConfirmed(String normalized) {
    return normalized.contains('email not confirmed');
  }

  static bool _isEmailAlreadyRegistered(String normalized) {
    return normalized.contains('user already registered') ||
        normalized.contains('already been registered') ||
        normalized.contains('already exists') && normalized.contains('email');
  }

  static bool _isInvalidEmail(String normalized) {
    return normalized.contains('invalid email') ||
        normalized.contains('email address is invalid');
  }

  static bool _isWeakPassword(String normalized) {
    return normalized.contains('password should be at least') ||
        normalized.contains('password is too short') ||
        normalized.contains('weak password') ||
        normalized.contains('password should contain') ||
        normalized.contains('password must contain');
  }

  static bool _isUsernameTaken(String normalized) {
    return normalized.contains('profiles_username_key') ||
        normalized.contains('username already exists') ||
        normalized.contains('username is already taken') ||
        normalized.contains('duplicate key') &&
            normalized.contains('username') ||
        normalized.contains('unique') && normalized.contains('username');
  }

  static bool _isPermissionError(String normalized) {
    return normalized.contains('row-level security') ||
        normalized.contains('permission denied') ||
        normalized.contains('not allowed') ||
        normalized.contains('forbidden');
  }

  static bool _isReplyTargetError(String normalized) {
    return normalized.contains('reply target must belong to the same chat') ||
        normalized.contains('same chat');
  }

  static bool _isAttachmentUnavailable(String normalized) {
    return normalized.contains('object not found') ||
        normalized.contains('storage') && normalized.contains('not found') ||
        normalized.contains('attachment missing') ||
        normalized.contains('file not found');
  }

  static bool _isChatUnavailable(String normalized) {
    return normalized.contains('chat not found') ||
        normalized.contains('conversation not found') ||
        normalized.contains('not a member of this chat');
  }

  static bool _isSessionError(String normalized) {
    return normalized.contains('jwt') ||
        normalized.contains('session expired') ||
        normalized.contains('refresh token');
  }

  static bool _isRecoveryLinkInvalid(String normalized) {
    return normalized.contains('expired') && normalized.contains('link') ||
        normalized.contains('expired') && normalized.contains('token') ||
        normalized.contains('invalid') && normalized.contains('token') ||
        normalized.contains('otp has expired') ||
        normalized.contains('invalid grant') ||
        normalized.contains('flow state not found') ||
        normalized.contains('auth session missing');
  }

  static bool _isNoUserReturned(String normalized) {
    return normalized.contains('no user returned') ||
        normalized.contains('did not return a user');
  }

  static bool _isGridBreachSchemaMismatch(String normalized) {
    return normalized.contains('grid_breach_matches') &&
        normalized.contains('column') &&
        (normalized.contains('quit_by') ||
            normalized.contains('quit_at') ||
            normalized.contains('move_deadline_at') ||
            normalized.contains('move_time_limit_seconds') ||
            normalized.contains('rematch_requested_by'));
  }
}
