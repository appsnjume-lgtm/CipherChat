import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/services/chat_background_storage_service.dart';
import '../../../../core/utils/app_error_helper.dart';
import '../../domain/entities/chat_background_config.dart';

final chatBackgroundProvider = StateNotifierProvider.autoDispose
    .family<ChatBackgroundController, ChatBackgroundState, String?>((
      ref,
      chatId,
    ) {
      final controller = ChatBackgroundController(
        storageService: ref.watch(chatBackgroundStorageServiceProvider),
        chatId: chatId,
      );
      controller.load();
      return controller;
    });

class ChatBackgroundState {
  const ChatBackgroundState({
    required this.globalConfig,
    required this.chatConfig,
    required this.isLoading,
    required this.isSaving,
    required this.errorMessage,
  });

  factory ChatBackgroundState.initial() {
    return const ChatBackgroundState(
      globalConfig: null,
      chatConfig: null,
      isLoading: true,
      isSaving: false,
      errorMessage: null,
    );
  }

  final ChatBackgroundConfig? globalConfig;
  final ChatBackgroundConfig? chatConfig;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  ChatBackgroundConfig get resolvedConfig =>
      chatConfig ?? globalConfig ?? ChatBackgroundConfig.defaults();

  ChatBackgroundConfig get editableConfig =>
      chatConfig ?? globalConfig ?? ChatBackgroundConfig.defaults();

  bool get hasChatOverride => chatConfig != null;

  ChatBackgroundState copyWith({
    ChatBackgroundConfig? globalConfig,
    bool setGlobalConfig = false,
    ChatBackgroundConfig? chatConfig,
    bool setChatConfig = false,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChatBackgroundState(
      globalConfig: setGlobalConfig ? globalConfig : this.globalConfig,
      chatConfig: setChatConfig ? chatConfig : this.chatConfig,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class ChatBackgroundController extends StateNotifier<ChatBackgroundState> {
  ChatBackgroundController({
    required ChatBackgroundStorageService storageService,
    required String? chatId,
  }) : _storageService = storageService,
       _chatId = chatId,
       super(ChatBackgroundState.initial());

  final ChatBackgroundStorageService _storageService;
  final String? _chatId;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final chatId = _chatId;
      final globalFuture = _storageService.readGlobalConfig();
      final chatFuture = chatId == null
          ? Future<ChatBackgroundConfig?>.value(null)
          : _storageService.readChatConfig(chatId);
      final results = await Future.wait<ChatBackgroundConfig?>([
        globalFuture,
        chatFuture,
      ]);
      state = state.copyWith(
        globalConfig: results[0],
        setGlobalConfig: true,
        chatConfig: results[1],
        setChatConfig: true,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: AppErrorHelper.messageFor(error),
      );
    }
  }

  Future<void> saveConfig(
    ChatBackgroundConfig config, {
    String? replacementImageSourcePath,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final chatId = _chatId;
      if (chatId == null) {
        final saved = await _storageService.saveGlobalConfig(
          config: config,
          replacementImageSourcePath: replacementImageSourcePath,
          previousConfig: state.globalConfig,
        );
        state = state.copyWith(
          globalConfig: saved,
          setGlobalConfig: true,
          isSaving: false,
          clearError: true,
        );
        return;
      }

      final saved = await _storageService.saveChatConfig(
        chatId: chatId,
        config: config,
        replacementImageSourcePath: replacementImageSourcePath,
        previousConfig: state.chatConfig,
      );
      final globalConfig = await _storageService.readGlobalConfig();
      state = state.copyWith(
        globalConfig: globalConfig,
        setGlobalConfig: true,
        chatConfig: saved,
        setChatConfig: true,
        isSaving: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: AppErrorHelper.messageFor(error),
      );
      rethrow;
    }
  }

  Future<void> resetGlobal() async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _storageService.deleteGlobalConfig(
        previousConfig: state.globalConfig,
      );
      state = state.copyWith(
        globalConfig: null,
        setGlobalConfig: true,
        isSaving: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: AppErrorHelper.messageFor(error),
      );
      rethrow;
    }
  }

  Future<void> clearChatOverride() async {
    final chatId = _chatId;
    if (chatId == null) {
      await resetGlobal();
      return;
    }

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _storageService.deleteChatConfig(
        chatId,
        previousConfig: state.chatConfig,
      );
      final globalConfig = await _storageService.readGlobalConfig();
      state = state.copyWith(
        globalConfig: globalConfig,
        setGlobalConfig: true,
        chatConfig: null,
        setChatConfig: true,
        isSaving: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: AppErrorHelper.messageFor(error),
      );
      rethrow;
    }
  }
}
