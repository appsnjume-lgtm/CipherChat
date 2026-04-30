import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/supabase_service.dart';
import '../auth/data/models/profile_model.dart';
import '../auth/domain/entities/app_user.dart';

final contactProfileRepositoryProvider = Provider<ContactProfileRepository>((
  ref,
) {
  return ContactProfileRepository(ref.watch(supabaseServiceProvider).client);
});

enum ContactProfileActionState { blocked, requestChat, pending, chat }

class ContactProfileData {
  const ContactProfileData({
    required this.user,
    required this.visibleGender,
    required this.visibleBio,
    required this.visibleLastSeen,
    required this.canViewProfilePhoto,
    required this.canViewGender,
    required this.canViewAbout,
    required this.canViewLastSeen,
    required this.isBlocked,
    required this.isContact,
    required this.existingChatId,
    required this.actionState,
  });

  final AppUser user;
  final String? visibleGender;
  final String? visibleBio;
  final DateTime? visibleLastSeen;
  final bool canViewProfilePhoto;
  final bool canViewGender;
  final bool canViewAbout;
  final bool canViewLastSeen;
  final bool isBlocked;
  final bool isContact;
  final String? existingChatId;
  final ContactProfileActionState actionState;

  String get actionLabel {
    switch (actionState) {
      case ContactProfileActionState.blocked:
        return 'Blocked';
      case ContactProfileActionState.requestChat:
        return 'Request Chat';
      case ContactProfileActionState.pending:
        return 'Pending';
      case ContactProfileActionState.chat:
        return 'Chat';
    }
  }

  bool get isActionEnabled {
    switch (actionState) {
      case ContactProfileActionState.blocked:
      case ContactProfileActionState.pending:
        return false;
      case ContactProfileActionState.requestChat:
      case ContactProfileActionState.chat:
        return true;
    }
  }
}

class ContactProfileRepository {
  ContactProfileRepository(this._client);

  final SupabaseClient _client;

  Future<ContactProfileData> fetchContactProfile({
    required String currentUserId,
    required String contactUserId,
  }) async {
    final rows = await _client.rpc(
      'get_visible_profiles_by_ids',
      params: {
        'p_user_ids': [contactUserId],
      },
    );
    if (rows is! List || rows.isEmpty) {
      throw StateError('Profile not found.');
    }

    final row = Map<String, dynamic>.from(rows.first as Map);
    final user = ProfileModel.fromMap(row);
    final isBlocked =
        row['is_blocked'] as bool? ??
        await _isBlockedBetween(
          currentUserId: currentUserId,
          otherUserId: contactUserId,
        );
    final existingChatId = await _findExistingDirectChatId(
      currentUserId: currentUserId,
      otherUserId: contactUserId,
    );
    final isContact = row['is_contact'] as bool? ?? existingChatId != null;
    final hasPendingRequest = await _hasPendingDirectRequest(
      currentUserId: currentUserId,
      otherUserId: contactUserId,
    );

    final canViewProfilePhoto =
        row['can_view_profile_photo'] as bool? ??
        ((user.profileImageUrl?.trim().isNotEmpty ?? false) && !isBlocked);
    final canViewGender = row['can_view_gender'] as bool? ?? !isBlocked;
    final canViewAbout = row['can_view_about'] as bool? ?? !isBlocked;
    final canViewLastSeen =
        row['can_view_last_seen'] as bool? ??
        (!isBlocked && user.lastSeenAt != null);

    final actionState = _resolveActionState(
      isBlocked: isBlocked,
      existingChatId: existingChatId,
      accountPrivacy: user.accountPrivacy,
      hasPendingRequest: hasPendingRequest,
    );

    final visibleUser = user.copyWith(
      profileImageUrl: canViewProfilePhoto ? user.profileImageUrl : null,
    );

    return ContactProfileData(
      user: visibleUser,
      visibleGender: canViewGender ? user.gender.label : null,
      visibleBio: canViewAbout && user.bio.trim().isNotEmpty
          ? user.bio.trim()
          : null,
      visibleLastSeen: canViewLastSeen ? user.lastSeenAt : null,
      canViewProfilePhoto: canViewProfilePhoto,
      canViewGender: canViewGender,
      canViewAbout: canViewAbout,
      canViewLastSeen: canViewLastSeen,
      isBlocked: isBlocked,
      isContact: isContact,
      existingChatId: existingChatId,
      actionState: actionState,
    );
  }

  Future<void> reportUser({
    required String reporterId,
    required String reportedUserId,
  }) async {
    await _client.from('user_reports').insert({
      'reporter_id': reporterId,
      'reported_user_id': reportedUserId,
      'reason': 'profile_report',
    });
  }

  ContactProfileActionState _resolveActionState({
    required bool isBlocked,
    required String? existingChatId,
    required AccountPrivacy accountPrivacy,
    required bool hasPendingRequest,
  }) {
    if (isBlocked) {
      return ContactProfileActionState.blocked;
    }
    if (existingChatId != null || accountPrivacy == AccountPrivacy.public) {
      return ContactProfileActionState.chat;
    }
    if (hasPendingRequest) {
      return ContactProfileActionState.pending;
    }
    return ContactProfileActionState.requestChat;
  }

  Future<bool> _isBlockedBetween({
    required String currentUserId,
    required String otherUserId,
  }) async {
    final rows = await _client
        .from('blocked_users')
        .select('blocker_id, blocked_user_id')
        .or(
          'and(blocker_id.eq.$currentUserId,blocked_user_id.eq.$otherUserId),and(blocker_id.eq.$otherUserId,blocked_user_id.eq.$currentUserId)',
        );

    return (rows as List<dynamic>).isNotEmpty;
  }

  Future<bool> _hasPendingDirectRequest({
    required String currentUserId,
    required String otherUserId,
  }) async {
    final rows = await _client
        .from('chat_requests')
        .select('id')
        .eq('type', 'direct_request')
        .eq('status', 'pending')
        .or(
          'and(requested_by.eq.$currentUserId,user_id.eq.$otherUserId),and(requested_by.eq.$otherUserId,user_id.eq.$currentUserId)',
        );

    return (rows as List<dynamic>).isNotEmpty;
  }

  Future<String?> _findExistingDirectChatId({
    required String currentUserId,
    required String otherUserId,
  }) async {
    final existing = await _client.rpc(
      'find_direct_chat_between',
      params: {'p_left_user_id': currentUserId, 'p_right_user_id': otherUserId},
    );

    if (existing is String && existing.trim().isNotEmpty) {
      return existing;
    }
    return null;
  }
}
