import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/local_chat_cache_service.dart';
import '../../../../core/services/realtime_service.dart';
import '../../../../core/startup/app_startup.dart';
import '../../../auth/data/models/profile_model.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../application/models/resolved_chat_message.dart';
import '../../domain/entities/chat.dart';
import '../../domain/entities/chat_member.dart';
import '../../domain/entities/chat_request.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/message_receipt.dart';
import '../models/chat_member_model.dart';
import '../models/chat_model.dart';
import '../models/chat_request_model.dart';
import '../models/message_model.dart';
import '../models/message_receipt_model.dart';
import '../models/search_models.dart';

enum DirectConversationOutcome {
  opened,
  requestSent,
  requestAlreadyPending,
  blocked,
}

const String _messageSelectWithReceipts =
    '*, message_receipts(message_id, chat_id, user_id, delivered_at, read_at, consumed_at)';

class DirectConversationResult {
  const DirectConversationResult({required this.outcome, this.chat});

  final DirectConversationOutcome outcome;
  final Chat? chat;

  bool get openedChat => outcome == DirectConversationOutcome.opened;
}

class MessageReceiptSummary {
  const MessageReceiptSummary({
    required this.messageId,
    required this.deliveredCount,
    required this.readCount,
    required this.consumedCount,
  });

  final String messageId;
  final int deliveredCount;
  final int readCount;
  final int consumedCount;
}

class ChatRepository {
  ChatRepository(this._client, this._realtimeService, this._chatCache);

  final SupabaseClient _client;
  final RealtimeService _realtimeService;
  final LocalChatCacheService _chatCache;

  Future<List<Chat>> fetchChats(String currentUserId) async {
    Object rows;
    try {
      rows = await StartupTrace.async(
        'get_chat_inbox RPC',
        () =>
            _client.rpc('get_chat_inbox', params: {'p_user_id': currentUserId}),
      );
    } on PostgrestException catch (error) {
      if (!_isMissingRpcFunction(error, 'get_chat_inbox')) {
        rethrow;
      }

      return _fetchChatsWithoutInboxRpc(currentUserId);
    }

    return (rows as List<dynamic>)
        .map(
          (row) => _chatFromInboxRow(
            Map<String, dynamic>.from(row as Map),
            currentUserId,
          ),
        )
        .toList(growable: false);
  }

  Future<List<Chat>> _fetchChatsWithoutInboxRpc(String currentUserId) async {
    final memberships = await _client
        .from('chat_members')
        .select('chat_id')
        .eq('user_id', currentUserId);

    final chatIds = (memberships as List<dynamic>)
        .map((item) => (item as Map)['chat_id'] as String?)
        .whereType<String>()
        .toList(growable: false);
    if (chatIds.isEmpty) {
      return const [];
    }

    final rows = await _client
        .from('chats')
        .select()
        .inFilter('id', chatIds)
        .order('updated_at', ascending: false);
    final chats = await Future.wait(
      (rows as List<dynamic>).map((row) async {
        final chat = ChatModel.fromMap(Map<String, dynamic>.from(row as Map));
        final results = await Future.wait<Object?>([
          fetchChatMembers(chat.id, currentUserId: currentUserId),
          fetchLatestMessage(chat.id),
          _fetchUnreadCount(currentUserId: currentUserId, chatId: chat.id),
        ]);
        final members = results[0] as List<ChatMember>;
        final latestMessage = results[1] as Message?;
        final unreadCount = results[2] as int;
        final isCurrentUserMember = members.any(
          (member) => member.userId == currentUserId,
        );
        final isCurrentUserAdmin =
            members.any(
              (member) => member.userId == currentUserId && member.isAdmin,
            ) ||
            chat.createdBy == currentUserId;

        return chat.copyWith(
          members: members,
          latestMessage: latestMessage,
          unreadCount: unreadCount,
          isCurrentUserMember: isCurrentUserMember,
          isCurrentUserAdmin: isCurrentUserAdmin,
        );
      }),
    );
    return chats.toList(growable: false);
  }

  Future<List<Chat>> fetchDiscoverableGroups(
    String currentUserId, {
    int limit = 30,
    int offset = 0,
  }) async {
    final safeLimit = limit.clamp(1, 100);
    final safeOffset = offset < 0 ? 0 : offset;
    final chats = await _client
        .from('chats')
        .select(
          'id, is_group, title, group_image_url, created_by, created_at, chat_members(count)',
        )
        .eq('is_group', true)
        .order('created_at', ascending: false)
        .range(safeOffset, safeOffset + safeLimit - 1);

    final rows = (chats as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    if (rows.isEmpty) {
      return const [];
    }

    final chatIds = rows
        .map((row) => row['id'] as String)
        .toList(growable: false);
    final currentMembershipsFuture = _client
        .from('chat_members')
        .select('chat_id, role')
        .eq('user_id', currentUserId)
        .inFilter('chat_id', chatIds);
    final pendingRequestsFuture = _client
        .from('chat_requests')
        .select('chat_id')
        .eq('user_id', currentUserId)
        .eq('status', 'pending')
        .inFilter('chat_id', chatIds);

    final lookups = await Future.wait<dynamic>([
      currentMembershipsFuture,
      pendingRequestsFuture,
    ]);
    final membershipByChatId = {
      for (final item in lookups[0] as List<dynamic>)
        (item['chat_id'] as String): item['role'] as String? ?? 'member',
    };
    final pendingRequestChatIds = {
      for (final item in lookups[1] as List<dynamic>)
        if (item['chat_id'] != null) item['chat_id'] as String,
    };

    return rows
        .map((row) {
          final chat = ChatModel.fromMap(row);
          final memberCount = _memberCountFromAggregate(row['chat_members']);
          final membershipRole = membershipByChatId[chat.id];
          final isMember = membershipRole != null;
          final isAdmin =
              membershipRole == 'admin' || chat.createdBy == currentUserId;

          return chat.copyWith(
            members: _memberCountPlaceholders(
              chatId: chat.id,
              count: memberCount,
              createdAt: chat.createdAt,
              currentUserId: isMember ? currentUserId : null,
              currentUserRole: membershipRole,
            ),
            latestMessage: null,
            unreadCount: 0,
            isCurrentUserMember: isMember,
            isCurrentUserAdmin: isAdmin,
            latestMessagePreviewText: pendingRequestChatIds.contains(chat.id)
                ? 'Join request pending'
                : null,
          );
        })
        .toList(growable: false);
  }

  int _memberCountFromAggregate(Object? value) {
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is Map) {
        final count = first['count'];
        if (count is int) {
          return count;
        }
        if (count is num) {
          return count.toInt();
        }
      }
    }
    return 0;
  }

  List<ChatMember> _memberCountPlaceholders({
    required String chatId,
    required int count,
    required DateTime createdAt,
    required String? currentUserId,
    required String? currentUserRole,
  }) {
    if (count <= 0) {
      return const [];
    }

    return List<ChatMember>.generate(
      count,
      (index) => ChatMember(
        id: '$chatId-member-count-$index',
        chatId: chatId,
        userId: index == 0 && currentUserId != null
            ? currentUserId
            : '$chatId-member-$index',
        role: index == 0 && currentUserRole != null
            ? currentUserRole
            : 'member',
        joinedAt: createdAt,
      ),
    );
  }

  Future<Chat> fetchChat({
    required String chatId,
    required String currentUserId,
  }) async {
    final raw = await _client.from('chats').select().eq('id', chatId).single();
    final unreadCount = await _fetchUnreadCount(
      currentUserId: currentUserId,
      chatId: chatId,
    );
    return _buildChat(raw, currentUserId, unreadCount: unreadCount);
  }

  Future<List<ChatMember>> fetchChatMembers(
    String chatId, {
    required String currentUserId,
  }) async {
    final rows = await _client
        .from('chat_members')
        .select()
        .eq('chat_id', chatId)
        .order('joined_at', ascending: true);

    final models = (rows as List<dynamic>)
        .map((item) => ChatMemberModel.fromMap(item as Map<String, dynamic>))
        .toList();

    if (models.isEmpty) {
      return const [];
    }

    final profileMap = await _fetchVisibleProfilesByIds(
      userIds: models.map((member) => member.userId).toList(growable: false),
    );

    return models
        .map(
          (member) => member.withProfile(
            username: profileMap[member.userId]?.username,
            avatarId: profileMap[member.userId]?.avatarId,
            profileImageUrl: profileMap[member.userId]?.profileImageUrl,
            genderLabel: profileMap[member.userId]?.gender.label,
            bioPreview: profileMap[member.userId]?.bio,
            isOnline: profileMap[member.userId]?.isOnline ?? false,
            lastSeenAt: profileMap[member.userId]?.lastSeenAt,
          ),
        )
        .toList();
  }

  Future<Map<String, String>> fetchParticipantPublicKeys(String chatId) async {
    final rows = await _client.rpc(
      'get_chat_participant_keys',
      params: {'p_chat_id': chatId},
    );

    final keys = <String, String>{};
    for (final row in rows as List<dynamic>) {
      final map = Map<String, dynamic>.from(row as Map);
      final key = (map['e2ee_public_key'] as String?)?.trim();
      final userId = map['id'] as String?;
      if (userId == null || key == null || key.isEmpty) {
        continue;
      }
      keys[userId] = key;
    }
    return keys;
  }

  Future<Message?> fetchLatestMessage(String chatId) async {
    final currentUserId = _client.auth.currentUser?.id;
    var query = _client
        .from('messages')
        .select(_messageSelectWithReceipts)
        .eq('chat_id', chatId);

    if (currentUserId != null) {
      query = query.eq('message_receipts.user_id', currentUserId);
    }

    final row = await query
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    return MessageModel.fromMap(row);
  }

  Future<Message> fetchMessageById(String messageId) async {
    final currentUserId = _client.auth.currentUser?.id;
    var query = _client
        .from('messages')
        .select(_messageSelectWithReceipts)
        .eq('id', messageId);

    if (currentUserId != null) {
      query = query.eq('message_receipts.user_id', currentUserId);
    }

    final row = await query.single();

    return MessageModel.fromMap(row);
  }

  Future<List<Message>> fetchMessages({
    required String chatId,
    DateTime? before,
    int limit = 30,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;
    var query = _client
        .from('messages')
        .select(_messageSelectWithReceipts)
        .eq('chat_id', chatId);

    if (currentUserId != null) {
      query = query.eq('message_receipts.user_id', currentUserId);
    }

    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }

    final rows = await query.order('created_at', ascending: false).limit(limit);

    final messages =
        (rows as List<dynamic>)
            .map((item) => MessageModel.fromMap(item as Map<String, dynamic>))
            .toList()
          ..sort((left, right) => left.createdAt.compareTo(right.createdAt));

    return messages;
  }

  Future<Map<String, MessageReceiptSummary>> fetchMessageReceiptSummary({
    required String chatId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) {
      return const {};
    }

    final rows = await _client
        .from('message_receipts')
        .select('message_id, delivered_at, read_at, consumed_at')
        .eq('chat_id', chatId)
        .inFilter('message_id', messageIds);

    final summaries = <String, ({int delivered, int read, int consumed})>{};
    for (final row in rows as List<dynamic>) {
      final map = row as Map<String, dynamic>;
      final messageId = map['message_id'] as String?;
      if (messageId == null) {
        continue;
      }

      final existing =
          summaries[messageId] ?? (delivered: 0, read: 0, consumed: 0);
      summaries[messageId] = (
        delivered: existing.delivered + (map['delivered_at'] == null ? 0 : 1),
        read: existing.read + (map['read_at'] == null ? 0 : 1),
        consumed: existing.consumed + (map['consumed_at'] == null ? 0 : 1),
      );
    }

    return {
      for (final entry in summaries.entries)
        entry.key: MessageReceiptSummary(
          messageId: entry.key,
          deliveredCount: entry.value.delivered,
          readCount: entry.value.read,
          consumedCount: entry.value.consumed,
        ),
    };
  }

  Future<List<AppUser>> searchUsers({
    required String currentUserId,
    required String query,
  }) async {
    final trimmed = query.trim();
    final rows = await _client.rpc(
      'search_visible_profiles',
      params: {'p_query': trimmed.isEmpty ? null : trimmed, 'p_limit': 30},
    );

    return (rows as List<dynamic>)
        .map(
          (item) =>
              ProfileModel.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .where((user) => user.id != currentUserId)
        .toList(growable: false);
  }

  Future<List<ChatMessageSearchMatch>> searchChatMessages({
    required String chatId,
    required String query,
    int limit = 200,
    int offset = 0,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;
    final trimmed = query.trim();
    if (currentUserId == null || trimmed.isEmpty) {
      return const [];
    }

    final headers = await _chatCache.readMessageHeaders(
      userId: currentUserId,
      chatId: chatId,
    );
    final normalizedQuery = trimmed.toLowerCase();
    final matched =
        headers
            .where((message) {
              final searchable = _searchableTextForMessage(
                message,
              ).toLowerCase();
              return searchable.contains(normalizedQuery);
            })
            .toList(growable: false)
          ..sort((left, right) => left.createdAt.compareTo(right.createdAt));

    final page = matched.skip(offset).take(limit).toList(growable: false);
    return page
        .map((message) {
          final searchableText = _searchableTextForMessage(message);
          return ChatMessageSearchMatch(
            messageId: message.id,
            chatId: message.chatId,
            senderId: message.senderId,
            messageType: message.kind.name,
            createdAt: message.createdAt,
            searchText: searchableText,
            snippet: _snippetForSearch(searchableText, trimmed),
            matchPosition:
                searchableText.toLowerCase().indexOf(normalizedQuery) + 1,
            totalMatches: matched.length,
          );
        })
        .toList(growable: false);
  }

  Future<List<GlobalMessageSearchResult>> searchGlobalMessages({
    required String query,
    int limit = 40,
    int offset = 0,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;
    final trimmed = query.trim();
    if (currentUserId == null || trimmed.isEmpty) {
      return const [];
    }

    final chats = await _chatCache.readChatSnapshots(currentUserId);
    if (chats.isEmpty) {
      return const [];
    }

    final normalizedQuery = trimmed.toLowerCase();
    final results = <GlobalMessageSearchResult>[];
    for (final chat in chats) {
      final headers = await _chatCache.readMessageHeaders(
        userId: currentUserId,
        chatId: chat.id,
      );
      for (final message in headers) {
        final searchableText = _searchableTextForMessage(message);
        final lower = searchableText.toLowerCase();
        if (searchableText.isEmpty || !lower.contains(normalizedQuery)) {
          continue;
        }

        final relevance = lower.startsWith(normalizedQuery) ? 1.0 : 0.7;
        results.add(
          GlobalMessageSearchResult(
            messageId: message.id,
            chatId: message.chatId,
            senderId: message.senderId,
            messageType: message.kind.name,
            createdAt: message.createdAt,
            searchText: searchableText,
            snippet: _snippetForSearch(searchableText, trimmed),
            chatLabel: chat.titleFor(currentUserId),
            isGroup: chat.isGroup,
            senderUsername:
                message.senderLabel ?? (message.isMine ? 'You' : 'Unknown'),
            matchPosition: lower.indexOf(normalizedQuery) + 1,
            relevance: relevance,
            totalMatches: 0,
          ),
        );
      }
    }

    results.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    final totalMatches = results.length;
    final page = results.skip(offset).take(limit).toList(growable: false);
    return page
        .map(
          (result) => GlobalMessageSearchResult(
            messageId: result.messageId,
            chatId: result.chatId,
            senderId: result.senderId,
            messageType: result.messageType,
            createdAt: result.createdAt,
            searchText: result.searchText,
            snippet: result.snippet,
            chatLabel: result.chatLabel,
            isGroup: result.isGroup,
            senderUsername: result.senderUsername,
            matchPosition: result.matchPosition,
            relevance: result.relevance,
            totalMatches: totalMatches,
          ),
        )
        .toList(growable: false);
  }

  Future<List<GlobalContactSearchResult>> searchGlobalContacts({
    required String query,
    int limit = 30,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final rows = await _client.rpc(
      'search_global_contacts',
      params: {'p_query': trimmed, 'p_limit': limit},
    );

    return (rows as List<dynamic>)
        .map(
          (item) => GlobalContactSearchResult.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<GlobalSearchResults> searchGlobal(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const GlobalSearchResults();
    }

    final results = await Future.wait<dynamic>([
      searchGlobalMessages(query: trimmed),
      searchGlobalContacts(query: trimmed),
    ]);

    return GlobalSearchResults(
      messages: results[0] as List<GlobalMessageSearchResult>,
      contacts: results[1] as List<GlobalContactSearchResult>,
    );
  }

  Future<DirectConversationResult> startDirectConversation({
    required String currentUserId,
    required String otherUserId,
  }) async {
    if (await isBlockedBetween(
      currentUserId: currentUserId,
      otherUserId: otherUserId,
    )) {
      return const DirectConversationResult(
        outcome: DirectConversationOutcome.blocked,
      );
    }

    final existingChatId = await _findExistingDirectChatId(
      currentUserId: currentUserId,
      otherUserId: otherUserId,
    );
    if (existingChatId != null) {
      return DirectConversationResult(
        outcome: DirectConversationOutcome.opened,
        chat: await fetchChat(
          chatId: existingChatId,
          currentUserId: currentUserId,
        ),
      );
    }

    final otherProfile = await _fetchVisibleProfile(userId: otherUserId);
    final otherPrivacy = otherProfile?.accountPrivacy ?? AccountPrivacy.public;

    if (otherPrivacy == AccountPrivacy.private) {
      final alreadyPending = await _hasPendingDirectRequest(
        currentUserId: currentUserId,
        otherUserId: otherUserId,
      );
      if (alreadyPending) {
        return const DirectConversationResult(
          outcome: DirectConversationOutcome.requestAlreadyPending,
        );
      }

      await createDirectRequest(
        senderId: currentUserId,
        receiverId: otherUserId,
      );
      return const DirectConversationResult(
        outcome: DirectConversationOutcome.requestSent,
      );
    }

    final chat = await createOrGetDirectChat(
      currentUserId: currentUserId,
      otherUserId: otherUserId,
    );
    return DirectConversationResult(
      outcome: DirectConversationOutcome.opened,
      chat: chat,
    );
  }

  Future<Chat> createOrGetDirectChat({
    required String currentUserId,
    required String otherUserId,
  }) async {
    final chatId =
        await _client.rpc(
              'ensure_direct_chat',
              params: {
                'p_left_user_id': currentUserId,
                'p_right_user_id': otherUserId,
              },
            )
            as String;

    return fetchChat(chatId: chatId, currentUserId: currentUserId);
  }

  Future<Chat> createGroupChat({
    required String currentUserId,
    String? title,
  }) async {
    final created = await _client
        .from('chats')
        .insert({
          'is_group': true,
          'created_by': currentUserId,
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        })
        .select()
        .single();

    final chatId = created['id'] as String;

    await _client.from('chat_members').insert({
      'chat_id': chatId,
      'user_id': currentUserId,
      'role': 'admin',
    });

    return fetchChat(chatId: chatId, currentUserId: currentUserId);
  }

  Future<Chat> updateGroupDetails({
    required String chatId,
    required String currentUserId,
    String? title,
    String? groupImageUrl,
    bool clearGroupImage = false,
  }) async {
    final updates = <String, dynamic>{};
    if (title != null) {
      updates['title'] = title.trim();
    }
    if (clearGroupImage) {
      updates['group_image_url'] = null;
    } else if (groupImageUrl != null) {
      updates['group_image_url'] = groupImageUrl;
    }

    if (updates.isNotEmpty) {
      await _client.from('chats').update(updates).eq('id', chatId);
    }

    return fetchChat(chatId: chatId, currentUserId: currentUserId);
  }

  Future<Chat> uploadGroupImage({
    required String chatId,
    required String currentUserId,
    required String sourcePath,
  }) async {
    final bytes = await _compressChatImage(sourcePath);
    final extension = p.extension(sourcePath).replaceFirst('.', '').trim();
    final objectPath = '$chatId/group.${extension.isEmpty ? 'jpg' : extension}';

    await _client.storage
        .from(AppConstants.groupImagesBucket)
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );

    return updateGroupDetails(
      chatId: chatId,
      currentUserId: currentUserId,
      groupImageUrl: objectPath,
    );
  }

  Future<void> removeGroupImage({
    required String chatId,
    required String currentUserId,
    String? existingPath,
  }) async {
    final trimmed = existingPath?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      await _client.storage.from(AppConstants.groupImagesBucket).remove([
        trimmed,
      ]);
    }
    await updateGroupDetails(
      chatId: chatId,
      currentUserId: currentUserId,
      clearGroupImage: true,
    );
  }

  Future<void> deleteChat({
    required String chatId,
    required String currentUserId,
  }) async {
    final chat = await fetchChat(chatId: chatId, currentUserId: currentUserId);
    if (chat.isGroup && !chat.isCurrentUserAdmin) {
      throw Exception('Only group admins can delete this chat.');
    }

    if (!chat.isGroup) {
      await _hideDirectChatForUser(
        chatId: chatId,
        currentUserId: currentUserId,
      );
      return;
    }

    await _deleteStoragePrefix(
      bucket: AppConstants.groupImagesBucket,
      prefix: chatId,
    );

    await _client.rpc('delete_chat', params: {'p_chat_id': chatId});
  }

  Future<void> ensurePublicKey({
    required String userId,
    required String publicKey,
  }) async {
    await _client
        .from('profiles')
        .update({'e2ee_public_key': publicKey})
        .eq('id', userId);
  }

  Future<void> createEncryptedMessage({
    required String messageId,
    required String chatId,
    required String senderId,
    required MessageKind kind,
    required Map<String, dynamic> payloadEnvelope,
    required Map<String, dynamic> keyEnvelopes,
    required String senderKeyPublic,
    String? stickerId,
    String? replyToMessageId,
  }) async {
    await _client.from('messages').insert({
      'id': messageId,
      'chat_id': chatId,
      'sender_id': senderId,
      'message_type': kind.name,
      'sticker_id': stickerId,
      'payload_encrypted': payloadEnvelope,
      'key_envelopes': keyEnvelopes,
      'sender_key_public': senderKeyPublic,
      'reply_to_message_id': replyToMessageId,
    });
  }

  Future<String> uploadEncryptedMedia({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    await _client.storage
        .from(AppConstants.secureMediaBucket)
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            cacheControl: '3600',
            upsert: false,
          ),
        );
    return objectPath;
  }

  Future<Uint8List> downloadEncryptedMedia(String objectPath) {
    return _client.storage
        .from(AppConstants.secureMediaBucket)
        .download(objectPath);
  }

  Future<void> deleteEncryptedMedia(String objectPath) async {
    if (objectPath.trim().isEmpty) {
      return;
    }

    await _client.storage.from(AppConstants.secureMediaBucket).remove([
      objectPath,
    ]);
  }

  Future<Message> markMessageDeletedForEveryone({
    required String messageId,
  }) async {
    await _client.rpc(
      'soft_delete_message_for_everyone',
      params: {'p_message_id': messageId},
    );

    return fetchMessageById(messageId);
  }

  Future<void> markMessagesDelivered({
    required String chatId,
    required String userId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) {
      return;
    }

    try {
      await _client.rpc(
        'mark_messages_delivered',
        params: {'p_chat_id': chatId, 'p_message_ids': messageIds},
      );
    } on PostgrestException catch (error) {
      if (!_isMissingRpcFunction(error, 'mark_messages_delivered')) {
        rethrow;
      }

      await _client
          .from('message_receipts')
          .update({'delivered_at': DateTime.now().toUtc().toIso8601String()})
          .eq('chat_id', chatId)
          .eq('user_id', userId)
          .inFilter('message_id', messageIds);
    }
  }

  Future<void> markMessagesRead({
    required String chatId,
    required String userId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) {
      return;
    }

    try {
      await _client.rpc(
        'mark_messages_read',
        params: {'p_chat_id': chatId, 'p_message_ids': messageIds},
      );
    } on PostgrestException catch (error) {
      if (!_isMissingRpcFunction(error, 'mark_messages_read')) {
        rethrow;
      }

      await _client
          .from('message_receipts')
          .update({
            'delivered_at': DateTime.now().toUtc().toIso8601String(),
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('chat_id', chatId)
          .eq('user_id', userId)
          .inFilter('message_id', messageIds);
    }
  }

  Future<void> markMessageConsumed({
    required String chatId,
    required String userId,
    required String messageId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client
        .from('message_receipts')
        .update({'delivered_at': now, 'read_at': now, 'consumed_at': now})
        .eq('chat_id', chatId)
        .eq('user_id', userId)
        .eq('message_id', messageId);
  }

  RealtimeChannel subscribeToMessages({
    required String chatId,
    required void Function(Message message) onInsert,
    required void Function(Message message) onUpdate,
  }) {
    return _realtimeService.subscribeToChatMessages(
      chatId: chatId,
      onInsert: (payload) => onInsert(MessageModel.fromMap(payload)),
      onUpdate: (payload) => onUpdate(MessageModel.fromMap(payload)),
    );
  }

  RealtimeChannel subscribeToReceipts({
    required String chatId,
    required void Function(MessageReceipt receipt) onUpsert,
  }) {
    return _realtimeService.subscribeToMessageReceipts(
      chatId: chatId,
      onUpsert: (payload) {
        onUpsert(
          MessageReceiptModel.fromMap(Map<String, dynamic>.from(payload)),
        );
      },
    );
  }

  RealtimeChannel subscribeToInboxChanges({
    required String userId,
    required void Function() onChange,
  }) {
    return _realtimeService.subscribeToInboxChanges(
      userId: userId,
      onChange: (_) => onChange(),
    );
  }

  RealtimeChannel subscribeToProfiles({
    required String channelName,
    required void Function(AppUser profile) onUpsert,
  }) {
    return _realtimeService.subscribeToProfiles(
      channelName: channelName,
      onUpsert: (payload) {
        onUpsert(ProfileModel.fromMap(Map<String, dynamic>.from(payload)));
      },
    );
  }

  RealtimeChannel subscribeToChatRequests({
    required String channelName,
    required void Function(
      PostgresChangeEvent event,
      Map<String, dynamic> payload,
    )
    onChange,
  }) {
    return _realtimeService.subscribeToChatRequests(
      channelName: channelName,
      onChange: onChange,
    );
  }

  Future<void> disposeProfileChannel(RealtimeChannel channel) {
    return _realtimeService.disposeChannel(channel);
  }

  Future<void> disposeMessageChannel(RealtimeChannel channel) {
    return _realtimeService.disposeChannel(channel);
  }

  Future<void> disposeRequestChannel(RealtimeChannel channel) {
    return _realtimeService.disposeChannel(channel);
  }

  bool _isMissingRpcFunction(PostgrestException error, String functionName) {
    final message = error.message.toLowerCase();
    return message.contains(functionName) &&
        (message.contains('does not exist') ||
            message.contains('could not find'));
  }

  Future<bool> isChatMember({
    required String chatId,
    required String userId,
  }) async {
    final row = await _client
        .from('chat_members')
        .select('id')
        .eq('chat_id', chatId)
        .eq('user_id', userId)
        .maybeSingle();

    return row != null;
  }

  Future<bool> isBlockedBetween({
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

  Future<void> blockUser({
    required String blockerId,
    required String blockedUserId,
  }) async {
    await _client.from('blocked_users').upsert({
      'blocker_id': blockerId,
      'blocked_user_id': blockedUserId,
    });
  }

  Future<void> unblockUser({
    required String blockerId,
    required String blockedUserId,
  }) async {
    await _client
        .from('blocked_users')
        .delete()
        .eq('blocker_id', blockerId)
        .eq('blocked_user_id', blockedUserId);
  }

  Future<List<AppUser>> fetchBlockedUsers(String blockerId) async {
    final rows = await _client
        .from('blocked_users')
        .select('blocked_user_id')
        .eq('blocker_id', blockerId)
        .order('created_at', ascending: false);

    final blockedIds = (rows as List<dynamic>)
        .map((item) => item['blocked_user_id'] as String)
        .toList();
    if (blockedIds.isEmpty) {
      return const [];
    }

    final byId = await _fetchVisibleProfilesByIds(userIds: blockedIds);

    return blockedIds.map((id) => byId[id]).whereType<AppUser>().toList();
  }

  Future<void> createJoinRequest({
    required String chatId,
    required String userId,
  }) async {
    final existing = await _client
        .from('chat_requests')
        .select('id')
        .eq('chat_id', chatId)
        .eq('user_id', userId)
        .eq('type', 'join_request')
        .eq('status', 'pending')
        .maybeSingle();

    if (existing != null) {
      return;
    }

    await _client.from('chat_requests').insert({
      'chat_id': chatId,
      'user_id': userId,
      'requested_by': userId,
      'type': 'join_request',
      'status': 'pending',
    });
  }

  Future<void> createDirectRequest({
    required String senderId,
    required String receiverId,
  }) async {
    await _client.from('chat_requests').insert({
      'chat_id': null,
      'user_id': receiverId,
      'requested_by': senderId,
      'type': 'direct_request',
      'status': 'pending',
    });
  }

  Future<void> sendInvite({
    required String chatId,
    required String adminUserId,
    required String targetUserId,
  }) async {
    if (await isChatMember(chatId: chatId, userId: targetUserId)) {
      return;
    }

    if (await isBlockedBetween(
      currentUserId: adminUserId,
      otherUserId: targetUserId,
    )) {
      throw Exception('You cannot invite a blocked user.');
    }

    final existing = await _client
        .from('chat_requests')
        .select('id')
        .eq('chat_id', chatId)
        .eq('user_id', targetUserId)
        .eq('type', 'invite')
        .eq('status', 'pending')
        .maybeSingle();

    if (existing != null) {
      return;
    }

    await _client.from('chat_requests').insert({
      'chat_id': chatId,
      'user_id': targetUserId,
      'requested_by': adminUserId,
      'type': 'invite',
      'status': 'pending',
    });
  }

  Future<List<ChatRequest>> fetchIncomingInvites(String userId) async {
    final rows = await _client
        .from('chat_requests')
        .select()
        .eq('user_id', userId)
        .eq('type', 'invite')
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return _enrichRequests(
      (rows as List<dynamic>)
          .map((item) => ChatRequestModel.fromMap(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Future<List<ChatRequest>> fetchIncomingDirectRequests(String userId) async {
    final rows = await _client
        .from('chat_requests')
        .select()
        .eq('user_id', userId)
        .eq('type', 'direct_request')
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return _enrichRequests(
      (rows as List<dynamic>)
          .map((item) => ChatRequestModel.fromMap(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Future<List<String>> fetchAdminOwnedGroupIds(String adminUserId) async {
    final groups = await _client
        .from('chats')
        .select('id')
        .eq('is_group', true)
        .eq('created_by', adminUserId);

    return (groups as List<dynamic>)
        .map((item) => item['id'] as String)
        .toList(growable: false);
  }

  Future<List<ChatRequest>> fetchAdminRequests(
    String adminUserId, {
    List<String>? groupIds,
  }) async {
    final effectiveGroupIds =
        groupIds ?? await fetchAdminOwnedGroupIds(adminUserId);

    if (effectiveGroupIds.isEmpty) {
      return const [];
    }

    final rows = await _client
        .from('chat_requests')
        .select()
        .eq('type', 'join_request')
        .eq('status', 'pending')
        .inFilter('chat_id', effectiveGroupIds)
        .order('created_at', ascending: false);

    return _enrichRequests(
      (rows as List<dynamic>)
          .map((item) => ChatRequestModel.fromMap(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Future<List<ChatRequest>> fetchSentRequests(String userId) async {
    final rows = await _client
        .from('chat_requests')
        .select()
        .eq('requested_by', userId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return _enrichRequests(
      (rows as List<dynamic>)
          .map((item) => ChatRequestModel.fromMap(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Future<Chat?> respondToRequest({
    required ChatRequest request,
    required String status,
    required String currentUserId,
  }) async {
    await _client
        .from('chat_requests')
        .update({'status': status})
        .eq('id', request.id);

    if (status != 'accepted') {
      return null;
    }

    if (request.isDirectRequest) {
      final chatId = await _findExistingDirectChatId(
        currentUserId: request.requestedBy,
        otherUserId: request.userId,
      );
      if (chatId == null) {
        return null;
      }
      return fetchChat(chatId: chatId, currentUserId: currentUserId);
    }

    final chatId = request.chatId;
    if (chatId == null) {
      return null;
    }

    final alreadyMember = await isChatMember(
      chatId: chatId,
      userId: request.userId,
    );

    if (!alreadyMember) {
      await _client.from('chat_members').insert({
        'chat_id': chatId,
        'user_id': request.userId,
        'role': 'member',
      });
    }

    return fetchChat(chatId: chatId, currentUserId: currentUserId);
  }

  Future<Chat> _buildChat(
    Map<String, dynamic> raw,
    String currentUserId, {
    int unreadCount = 0,
  }) async {
    final base = ChatModel.fromMap(raw);
    final members = await fetchChatMembers(
      base.id,
      currentUserId: currentUserId,
    );

    final isMember = members.any((member) => member.userId == currentUserId);
    final isAdmin =
        members.any(
          (member) => member.userId == currentUserId && member.isAdmin,
        ) ||
        base.createdBy == currentUserId;
    final latestMessage = isMember || !base.isGroup
        ? await fetchLatestMessage(base.id)
        : null;

    return base.copyWith(
      members: members,
      latestMessage: latestMessage,
      unreadCount: unreadCount,
      isCurrentUserMember: isMember,
      isCurrentUserAdmin: isAdmin,
    );
  }

  Chat _chatFromInboxRow(Map<String, dynamic> raw, String currentUserId) {
    final base = ChatModel.fromMap(raw);
    final memberRows = raw['members'] as List<dynamic>? ?? const [];
    final members = memberRows
        .whereType<Map>()
        .map((item) => _chatMemberFromInboxMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    final latestMessageRow = raw['latest_message'];
    final latestMessage = latestMessageRow is Map
        ? MessageModel.fromMap(Map<String, dynamic>.from(latestMessageRow))
        : null;
    final unreadRaw = raw['unread_count'];
    final unreadCount = unreadRaw is int
        ? unreadRaw
        : unreadRaw is num
        ? unreadRaw.toInt()
        : 0;
    final isMember = members.any((member) => member.userId == currentUserId);
    final isAdmin =
        members.any(
          (member) => member.userId == currentUserId && member.isAdmin,
        ) ||
        base.createdBy == currentUserId;

    return base.copyWith(
      members: members,
      latestMessage: latestMessage,
      unreadCount: unreadCount,
      isCurrentUserMember: isMember,
      isCurrentUserAdmin: isAdmin,
    );
  }

  ChatMember _chatMemberFromInboxMap(Map<String, dynamic> raw) {
    final member = ChatMemberModel.fromMap(raw);
    final profileRaw = raw['profile'];
    if (profileRaw is! Map) {
      return member;
    }

    final profile = ProfileModel.fromMap(Map<String, dynamic>.from(profileRaw));
    return member.withProfile(
      username: profile.username,
      avatarId: profile.avatarId,
      profileImageUrl: profile.profileImageUrl,
      genderLabel: profile.gender.label,
      bioPreview: profile.bio,
      isOnline: profile.isOnline,
      lastSeenAt: profile.lastSeenAt,
    );
  }

  Future<int> _fetchUnreadCount({
    required String currentUserId,
    required String chatId,
  }) async {
    final counts = await _fetchUnreadCounts(currentUserId, [chatId]);
    return counts[chatId] ?? 0;
  }

  Future<Map<String, int>> _fetchUnreadCounts(
    String currentUserId,
    List<String> chatIds,
  ) async {
    if (chatIds.isEmpty) {
      return const {};
    }

    final rows = await _client
        .from('message_receipts')
        .select('chat_id')
        .eq('user_id', currentUserId)
        .isFilter('read_at', null)
        .inFilter('chat_id', chatIds);

    final counts = <String, int>{};
    for (final row in rows as List<dynamic>) {
      final chatId = (row as Map<String, dynamic>)['chat_id'] as String?;
      if (chatId == null) {
        continue;
      }
      counts.update(chatId, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  Future<List<ChatRequest>> _enrichRequests(
    List<ChatRequestModel> models,
  ) async {
    if (models.isEmpty) {
      return const [];
    }

    final chatIds = models
        .map((model) => model.chatId)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    final userIds = <String>{
      for (final model in models) model.userId,
      for (final model in models) model.requestedBy,
    }.toList(growable: false);

    final chatsFuture = chatIds.isEmpty
        ? Future.value(const <String, Chat>{})
        : _fetchBasicChatsByIds(chatIds);
    final usersFuture = userIds.isEmpty
        ? Future.value(const <String, AppUser>{})
        : _fetchUsersByIds(userIds);

    final results = await Future.wait<dynamic>([chatsFuture, usersFuture]);
    final chatsById = results[0] as Map<String, Chat>;
    final usersById = results[1] as Map<String, AppUser>;

    return models
        .map(
          (model) => model.enrich(
            chatId: model.chatId,
            chat: model.chatId == null ? null : chatsById[model.chatId],
            user: usersById[model.userId],
            requestedByUser: usersById[model.requestedBy],
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, Chat>> _fetchBasicChatsByIds(List<String> chatIds) async {
    final rows = await _client.from('chats').select().inFilter('id', chatIds);
    return {
      for (final row in rows as List<dynamic>)
        (row['id'] as String): ChatModel.fromMap(row as Map<String, dynamic>),
    };
  }

  Future<Map<String, AppUser>> _fetchUsersByIds(List<String> userIds) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null || userIds.isEmpty) {
      return const {};
    }

    return _fetchVisibleProfilesByIds(userIds: userIds);
  }

  Future<Map<String, AppUser>> _fetchVisibleProfilesByIds({
    required List<String> userIds,
  }) async {
    if (userIds.isEmpty) {
      return const {};
    }

    final rows = await _client.rpc(
      'get_visible_profiles_by_ids',
      params: {'p_user_ids': userIds},
    );
    return {
      for (final row in rows as List<dynamic>)
        (row['id'] as String): ProfileModel.fromMap(
          Map<String, dynamic>.from(row as Map),
        ),
    };
  }

  Future<AppUser?> _fetchVisibleProfile({required String userId}) async {
    final rows = await _client.rpc(
      'get_visible_profiles_by_ids',
      params: {
        'p_user_ids': [userId],
      },
    );
    if (rows is! List || rows.isEmpty) {
      return null;
    }

    return ProfileModel.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  String _searchableTextForMessage(ResolvedChatMessage message) {
    if (message.isDeletedForEveryone) {
      return '';
    }

    final text = message.text?.trim();
    if (text != null && text.isNotEmpty) {
      return text;
    }

    final fileName = message.attachment?.fileName.trim();
    if (fileName != null && fileName.isNotEmpty) {
      return fileName;
    }

    return message.previewText.trim();
  }

  String _snippetForSearch(String text, String query) {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return '';
    }

    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return normalizedText;
    }

    final matchIndex = normalizedText.toLowerCase().indexOf(normalizedQuery);
    if (matchIndex < 0) {
      return normalizedText;
    }

    final start = matchIndex <= 24 ? 0 : matchIndex - 24;
    final end = (matchIndex + query.length + 24).clamp(
      0,
      normalizedText.length,
    );
    final prefix = start > 0 ? '...' : '';
    final suffix = end < normalizedText.length ? '...' : '';
    return '$prefix${normalizedText.substring(start, end)}$suffix';
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

  Future<void> _deleteStoragePrefix({
    required String bucket,
    required String prefix,
  }) async {
    final entries = await _client.storage.from(bucket).list(path: prefix);
    if (entries.isEmpty) {
      return;
    }

    final objectPaths = entries
        .map((item) => '$prefix/${item.name}'.replaceAll('//', '/'))
        .toList(growable: false);
    if (objectPaths.isEmpty) {
      return;
    }

    await _client.storage.from(bucket).remove(objectPaths);
  }

  Future<void> _hideDirectChatForUser({
    required String chatId,
    required String currentUserId,
  }) async {
    await _client.from('chat_user_state').upsert({
      'chat_id': chatId,
      'user_id': currentUserId,
      'hidden_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'chat_id,user_id');
  }

  Future<Uint8List> _compressChatImage(String sourcePath) async {
    final compressed = await FlutterImageCompress.compressWithFile(
      sourcePath,
      format: CompressFormat.jpeg,
      quality: 84,
      minWidth: 1024,
      minHeight: 1024,
    );

    if (compressed == null || compressed.isEmpty) {
      throw Exception('Unable to prepare group image.');
    }

    return compressed;
  }
}
