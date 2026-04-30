import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/utils/app_error_helper.dart';
import '../auth/presentation/providers/auth_provider.dart';
import '../chat/domain/entities/chat.dart';
import '../chat/presentation/providers/chat_provider.dart';
import '../chat/presentation/providers/message_provider.dart';

enum SharedType { text, image, file }

class SharedContent {
  const SharedContent({
    required this.text,
    required this.filePaths,
    required this.type,
  });

  final String? text;
  final List<String>? filePaths;
  final SharedType type;

  bool get hasFiles => (filePaths?.isNotEmpty ?? false);
  int get fileCount => filePaths?.length ?? 0;
}

class ShareTargetDecision {
  const ShareTargetDecision._({required this.isAllowed, this.message});

  const ShareTargetDecision.allow() : this._(isAllowed: true);

  const ShareTargetDecision.deny(String message)
    : this._(isAllowed: false, message: message);

  final bool isAllowed;
  final String? message;
}

const _unset = Object();

class ShareState {
  const ShareState({
    required this.pendingContent,
    required this.selectedChatId,
    required this.draftText,
    required this.isSending,
    required this.errorMessage,
  });

  factory ShareState.initial() {
    return const ShareState(
      pendingContent: null,
      selectedChatId: null,
      draftText: '',
      isSending: false,
      errorMessage: null,
    );
  }

  final SharedContent? pendingContent;
  final String? selectedChatId;
  final String draftText;
  final bool isSending;
  final String? errorMessage;

  bool get hasPendingContent => pendingContent != null;

  ShareState copyWith({
    Object? pendingContent = _unset,
    Object? selectedChatId = _unset,
    String? draftText,
    bool? isSending,
    Object? errorMessage = _unset,
  }) {
    return ShareState(
      pendingContent: pendingContent == _unset
          ? this.pendingContent
          : pendingContent as SharedContent?,
      selectedChatId: selectedChatId == _unset
          ? this.selectedChatId
          : selectedChatId as String?,
      draftText: draftText ?? this.draftText,
      isSending: isSending ?? this.isSending,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

final shareControllerProvider =
    StateNotifierProvider<ShareController, ShareState>((ref) {
      return ShareController(ref);
    });

class ShareController extends StateNotifier<ShareState> {
  ShareController(this._ref) : super(ShareState.initial());

  static const int maxFileSizeBytes = 50 * 1024 * 1024;

  final Ref _ref;

  String? get _currentUserId => _ref.read(currentUserIdProvider);

  static SharedContent? fromSharedMedia(List<SharedMediaFile> media) {
    if (media.isEmpty) {
      return null;
    }

    final textParts = <String>[];
    final filePaths = <String>[];
    var allImages = true;

    for (final item in media) {
      final path = item.path.trim();
      final message = item.message?.trim();
      if (message != null && message.isNotEmpty) {
        textParts.add(message);
      }

      if (item.type == SharedMediaType.text ||
          item.type == SharedMediaType.url) {
        if (path.isNotEmpty) {
          textParts.add(path);
        }
        continue;
      }

      if (path.isEmpty) {
        continue;
      }

      filePaths.add(path);
      final mimeType = item.mimeType?.trim().toLowerCase();
      final isImage =
          item.type == SharedMediaType.image ||
          (mimeType != null && mimeType.startsWith('image/'));
      allImages = allImages && isImage;
    }

    final text = textParts
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join('\n\n')
        .trim();

    if (filePaths.isEmpty) {
      if (text.isEmpty) {
        return null;
      }
      return SharedContent(text: text, filePaths: null, type: SharedType.text);
    }

    return SharedContent(
      text: text.isEmpty ? null : text,
      filePaths: filePaths,
      type: allImages ? SharedType.image : SharedType.file,
    );
  }

  Future<void> receiveSharedContent(SharedContent content) async {
    try {
      final normalized = await _normalizeContent(content);
      if (normalized == null) {
        return;
      }

      state = ShareState.initial().copyWith(
        pendingContent: normalized,
        draftText: normalized.text ?? '',
        errorMessage: null,
      );
    } catch (error) {
      setError(AppErrorHelper.messageFor(error));
    }
  }

  void setError(String message) {
    state = state.copyWith(errorMessage: message);
  }

  void clearShare() {
    state = ShareState.initial();
  }

  void selectChat(String chatId) {
    state = state.copyWith(selectedChatId: chatId, errorMessage: null);
  }

  void clearSelectedChat() {
    state = state.copyWith(selectedChatId: null, errorMessage: null);
  }

  void updateDraftText(String value) {
    state = state.copyWith(draftText: value, errorMessage: null);
  }

  Future<ShareTargetDecision> validateChatSelection(Chat chat) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return const ShareTargetDecision.deny('Sign in to continue sharing.');
    }

    if (!chat.isCurrentUserMember) {
      return const ShareTargetDecision.deny(
        'You can only share into chats you are a member of.',
      );
    }

    if (chat.isGroup) {
      return const ShareTargetDecision.allow();
    }

    final participant = chat.otherMemberFor(currentUserId);
    if (participant == null) {
      return const ShareTargetDecision.deny(
        'This conversation is not ready yet.',
      );
    }

    final isBlocked = await _ref
        .read(chatRepositoryProvider)
        .isBlockedBetween(
          currentUserId: currentUserId,
          otherUserId: participant.userId,
        );
    if (isBlocked) {
      return const ShareTargetDecision.deny(
        'This user cannot be contacted right now.',
      );
    }

    return const ShareTargetDecision.allow();
  }

  Future<String> sendSelectedContent() async {
    final content = state.pendingContent;
    final chatId = state.selectedChatId;
    if (content == null || chatId == null) {
      throw StateError('No shared content is ready to send.');
    }

    final chat = await _ref.read(chatDetailsProvider(chatId).future);
    final decision = await validateChatSelection(chat);
    if (!decision.isAllowed) {
      throw StateError(decision.message ?? 'This chat is unavailable.');
    }

    state = state.copyWith(isSending: true, errorMessage: null);

    try {
      final messageController = _ref.read(messageProvider(chatId).notifier);
      final draftText = state.draftText.trim();
      final filePaths = content.filePaths ?? const <String>[];

      switch (content.type) {
        case SharedType.text:
          if (draftText.isEmpty) {
            throw StateError('Shared text is empty.');
          }
          await messageController.sendText(draftText);
          break;
        case SharedType.image:
          for (final path in filePaths) {
            await messageController.sendImage(path);
          }
          if (draftText.isNotEmpty) {
            await messageController.sendText(draftText);
          }
          break;
        case SharedType.file:
          for (final path in filePaths) {
            await messageController.sendFile(path);
          }
          if (draftText.isNotEmpty) {
            await messageController.sendText(draftText);
          }
          break;
      }

      clearShare();
      return chatId;
    } catch (error) {
      final message = AppErrorHelper.messageFor(error);
      state = state.copyWith(isSending: false, errorMessage: message);
      rethrow;
    }
  }

  Future<SharedContent?> _normalizeContent(SharedContent content) async {
    final normalizedText = content.text?.trim();
    final normalizedPaths = <String>[];

    for (final rawPath in content.filePaths ?? const <String>[]) {
      final path = rawPath.trim();
      if (path.isEmpty || normalizedPaths.contains(path)) {
        continue;
      }

      final file = File(path);
      if (!await file.exists()) {
        continue;
      }

      final size = await file.length();
      if (size > maxFileSizeBytes) {
        throw StateError(
          '${p.basename(path)} is larger than 50 MB and cannot be shared yet.',
        );
      }

      normalizedPaths.add(path);
    }

    if (normalizedPaths.isEmpty) {
      if (normalizedText == null || normalizedText.isEmpty) {
        return null;
      }
      return SharedContent(
        text: normalizedText,
        filePaths: null,
        type: SharedType.text,
      );
    }

    final resolvedType =
        content.type == SharedType.image && normalizedPaths.every(_isImagePath)
        ? SharedType.image
        : SharedType.file;

    return SharedContent(
      text: normalizedText == null || normalizedText.isEmpty
          ? null
          : normalizedText,
      filePaths: normalizedPaths,
      type: resolvedType,
    );
  }

  bool _isImagePath(String path) {
    final mimeType = lookupMimeType(path)?.toLowerCase();
    return (mimeType?.startsWith('image/') ?? false) ||
        const {
          '.png',
          '.jpg',
          '.jpeg',
          '.gif',
          '.webp',
          '.bmp',
        }.contains(p.extension(path).toLowerCase());
  }
}
