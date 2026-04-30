import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../common/widgets/app_avatar.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/app_error_helper.dart';
import '../../../../core/widgets/app_error_card.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../profile/widgets/profile_image_modal.dart';
import '../providers/chat_provider.dart';

class GroupInfoScreen extends ConsumerStatefulWidget {
  const GroupInfoScreen({super.key, required this.chatId});

  final String chatId;

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  bool _isSaving = false;
  final ImagePicker _imagePicker = ImagePicker();

  String _memberJoinedLabel(DateTime joinedAt) {
    final localJoinedAt = joinedAt.toLocal();
    final now = DateTime.now();
    final isToday =
        localJoinedAt.year == now.year &&
        localJoinedAt.month == now.month &&
        localJoinedAt.day == now.day;

    if (isToday) {
      return "Joined Today ${DateFormat('HH:mm').format(localJoinedAt)}";
    }

    return "Joined ${DateFormat('dd/MM/yy').format(localJoinedAt)}";
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    final chatAsync = ref.watch(chatDetailsProvider(widget.chatId));

    return Scaffold(
      appBar: AppBar(title: const Text('Group Info')),
      body: chatAsync.when(
        data: (chat) {
          if (currentUserId == null) {
            return const Center(child: Text('Please sign in.'));
          }

          if (!chat.isCurrentUserMember) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chat.titleFor(currentUserId),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'You are not a member of this group yet. Send a join request to ask the admin for access.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        try {
                          await ref
                              .read(chatActionsProvider)
                              .requestToJoin(chat.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Join request sent.'),
                              ),
                            );
                          }
                        } catch (error) {
                          _showSnackBar(AppErrorHelper.messageFor(error));
                        }
                      },
                      child: const Text('Request to Join'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () => ProfileImageModal.show(
                              context,
                              imageUrl: chat.groupImageUrl,
                              avatarId: null,
                              title: chat.titleFor(currentUserId),
                              heroTag: 'group-${chat.id}',
                              storageBucket: AppConstants.groupImagesBucket,
                              useSignedUrl: true,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            child: Hero(
                              tag: 'group-${chat.id}',
                              child: AppAvatar(
                                size: 68,
                                avatarId: null,
                                imageUrl: chat.groupImageUrl,
                                storageBucket: AppConstants.groupImagesBucket,
                                useSignedUrl: true,
                                fallbackIcon: Icons.groups_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  chat.titleFor(currentUserId),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                Text('Group ID: ${chat.id}'),
                                const SizedBox(height: 8),
                                Text(
                                  '${chat.members.length} members',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (chat.isCurrentUserAdmin) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _isSaving
                                  ? null
                                  : () => _editGroupName(chat.title),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit Name'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _isSaving ? null : _pickGroupImage,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Edit Photo'),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: () => context.push('/chat/${chat.id}'),
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                            label: const Text('Open Chat'),
                          ),
                          if (chat.isCurrentUserAdmin)
                            FilledButton.icon(
                              onPressed: () =>
                                  context.push('/search?chatId=${chat.id}'),
                              icon: const Icon(Icons.person_add_alt_rounded),
                              label: const Text('Invite People'),
                            ),
                          if (chat.isCurrentUserAdmin)
                            OutlinedButton.icon(
                              onPressed: () => context.push('/invites'),
                              icon: const Icon(Icons.rule_rounded),
                              label: const Text('Manage Requests'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Members',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ...chat.members.map(
                (member) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      leading: AppAvatar(
                        size: 44,
                        avatarId: member.avatarId ?? 'avatar_1',
                        imageUrl: member.profileImageUrl,
                      ),
                      title: Text(member.username ?? member.userId),
                      subtitle: Text(_memberJoinedLabel(member.joinedAt)),
                      trailing: member.isAdmin
                          ? const Chip(label: Text('Admin'))
                          : const Chip(label: Text('Member')),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const GroupDetailsSkeletonView(),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AppErrorCard(
              message: AppErrorHelper.messageFor(error),
              actionLabel: 'Retry',
              onAction: () =>
                  ref.invalidate(chatDetailsProvider(widget.chatId)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editGroupName(String? currentTitle) async {
    final controller = TextEditingController(text: currentTitle ?? '');
    final nextTitle = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit group name',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Group name'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );

    controller.dispose();

    if (nextTitle == null || !mounted) {
      return;
    }

    await _saveGroupChanges(title: nextTitle);
  }

  Future<void> _pickGroupImage() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final currentUserId = ref.read(currentUserIdProvider);
      if (currentUserId == null) {
        return;
      }

      await ref
          .read(chatRepositoryProvider)
          .uploadGroupImage(
            chatId: widget.chatId,
            currentUserId: currentUserId,
            sourcePath: image.path,
          );
      if (!mounted) {
        return;
      }
      _refreshViews();
      _showSnackBar('Group photo updated.');
    } catch (error) {
      _showSnackBar(AppErrorHelper.messageFor(error));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveGroupChanges({required String title}) async {
    setState(() => _isSaving = true);
    try {
      final currentUserId = ref.read(currentUserIdProvider);
      if (currentUserId == null) {
        return;
      }

      await ref
          .read(chatRepositoryProvider)
          .updateGroupDetails(
            chatId: widget.chatId,
            currentUserId: currentUserId,
            title: title,
          );
      if (!mounted) {
        return;
      }
      _refreshViews();
      _showSnackBar('Group updated.');
    } catch (error) {
      _showSnackBar(AppErrorHelper.messageFor(error));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _refreshViews() {
    if (!mounted) {
      return;
    }

    ref.invalidate(chatDetailsProvider(widget.chatId));
    ref.invalidate(chatListProvider);
    ref.invalidate(discoverGroupsProvider);
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
