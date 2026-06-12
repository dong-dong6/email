import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../models/mail_models.dart';

class MailHomeScreen extends StatelessWidget {
  const MailHomeScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 720) {
              return _PhoneLayout(state: state);
            }
            if (constraints.maxWidth < 1080) {
              return _TabletLayout(state: state);
            }
            return _DesktopLayout(state: state);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showComposer(context, state),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('写信'),
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 276, child: _Sidebar(state: state)),
        const VerticalDivider(width: 1),
        SizedBox(width: 420, child: _MessageList(state: state, compact: false)),
        const VerticalDivider(width: 1),
        Expanded(child: _MessageDetail(state: state)),
      ],
    );
  }
}

class _TabletLayout extends StatelessWidget {
  const _TabletLayout({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 88, child: _Rail(state: state)),
        const VerticalDivider(width: 1),
        SizedBox(width: 360, child: _MessageList(state: state, compact: true)),
        const VerticalDivider(width: 1),
        Expanded(child: _MessageDetail(state: state)),
      ],
    );
  }
}

class _PhoneLayout extends StatefulWidget {
  const _PhoneLayout({required this.state});

  final AppState state;

  @override
  State<_PhoneLayout> createState() => _PhoneLayoutState();
}

class _PhoneLayoutState extends State<_PhoneLayout> {
  bool _showDetail = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: _showDetail && widget.state.selectedMessage != null
          ? _MessageDetail(
              key: const ValueKey('detail'),
              state: widget.state,
              onBack: () => setState(() => _showDetail = false),
            )
          : Column(
              key: const ValueKey('list'),
              children: [
                _MobileTopBar(state: widget.state),
                Expanded(
                  child: _MessageList(
                    state: widget.state,
                    compact: false,
                    onOpenMessage: () => setState(() => _showDetail = true),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          PopupMenuButton<String>(
            tooltip: '文件夹',
            icon: const Icon(Icons.menu_rounded),
            onSelected: state.selectFolder,
            itemBuilder: (context) => [
              for (final folder in state.folders)
                PopupMenuItem(
                  value: folder.id,
                  child: Text(
                      '${folder.name}  ${folder.unreadCount > 0 ? folder.unreadCount : ''}'),
                ),
            ],
          ),
          Expanded(
            child: Text(
              state.selectedFolder?.name ?? 'Inbox',
              style: Theme.of(context).textTheme.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Tooltip(
            message: '同步',
            child: IconButton(
              onPressed: state.isLoading ? null : state.syncSelectedAccount,
              icon: const Icon(Icons.sync_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.alternate_email_rounded, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Mail',
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis),
              ),
              Tooltip(
                message: '同步',
                child: IconButton(
                  onPressed: state.isLoading ? null : state.syncSelectedAccount,
                  icon: const Icon(Icons.sync_rounded),
                ),
              ),
            ],
          ),
        ),
        if (state.offlineMode)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _StatusPill(icon: Icons.cloud_off_rounded, text: '离线演示'),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.icon(
            onPressed: () => _showComposer(context, state),
            icon: const Icon(Icons.edit_rounded),
            label: const Text('写信'),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              for (final account in state.accounts)
                _AccountTile(account: account),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Text('文件夹'),
              ),
              for (final folder in state.folders)
                _FolderTile(
                  folder: folder,
                  selected: state.selectedFolder?.id == folder.id,
                  onTap: () => state.selectFolder(folder.id),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Tooltip(
                message: '设置',
                child: IconButton(
                  onPressed: () => _showSettings(context, state),
                  icon: const Icon(Icons.settings_rounded),
                ),
              ),
              Tooltip(
                message: '刷新',
                child: IconButton(
                  onPressed: state.reload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final folders = state.folders.take(5).toList();
    final selectedIndex =
        folders.indexWhere((folder) => folder.id == state.selectedFolder?.id);
    return NavigationRail(
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      onDestinationSelected: (index) => state.selectFolder(folders[index].id),
      labelType: NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 16),
        child: IconButton.filled(
          tooltip: '写信',
          onPressed: () => _showComposer(context, state),
          icon: const Icon(Icons.edit_rounded),
        ),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IconButton(
              tooltip: '同步',
              onPressed: state.syncSelectedAccount,
              icon: const Icon(Icons.sync_rounded),
            ),
          ),
        ),
      ),
      destinations: [
        for (final folder in folders)
          NavigationRailDestination(
            icon: Icon(_folderIcon(folder.role)),
            selectedIcon: Icon(_folderIcon(folder.role, selected: true)),
            label: Text(folder.name, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList(
      {required this.state, required this.compact, this.onOpenMessage});

  final AppState state;
  final bool compact;
  final VoidCallback? onOpenMessage;

  @override
  Widget build(BuildContext context) {
    final messages = state.visibleMessages;
    return Column(
      children: [
        Padding(
          padding:
              EdgeInsets.fromLTRB(compact ? 12 : 16, 12, compact ? 12 : 16, 8),
          child: SearchBar(
            leading: const Icon(Icons.search_rounded),
            hintText: '搜索邮件',
            onChanged: state.setQuery,
            trailing: [
              if (state.query.isNotEmpty)
                IconButton(
                  tooltip: '清除',
                  onPressed: () => state.setQuery(''),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _InlineError(text: state.error!),
          ),
        Expanded(
          child: messages.isEmpty
              ? const _EmptyState(icon: Icons.inbox_rounded, text: '没有邮件')
              : ListView.separated(
                  itemCount: messages.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return _MessageTile(
                      message: message,
                      selected: state.selectedMessage?.id == message.id,
                      compact: compact,
                      onTap: () {
                        state.selectMessage(message.id);
                        onOpenMessage?.call();
                      },
                      onStar: () => state.toggleStar(message),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.selected,
    required this.compact,
    required this.onTap,
    required this.onStar,
  });

  final MailMessage message;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onStar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: message.isRead ? FontWeight.w500 : FontWeight.w800,
        );
    return Material(
      color: selected
          ? scheme.secondaryContainer.withOpacity(0.55)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              EdgeInsets.fromLTRB(16, compact ? 10 : 12, 8, compact ? 10 : 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  message.isRead
                      ? Icons.mark_email_read_outlined
                      : Icons.mark_email_unread_rounded,
                  size: 20,
                  color:
                      message.isRead ? scheme.onSurfaceVariant : scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              message.from.name.isEmpty
                                  ? message.from.email
                                  : message.from.name,
                              style: titleStyle,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text(_shortTime(message.displayTime),
                            style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(message.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle),
                    const SizedBox(height: 4),
                    Text(message.snippet,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Tooltip(
                message: message.isStarred ? '取消星标' : '星标',
                child: IconButton(
                  onPressed: onStar,
                  icon: Icon(message.isStarred
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded),
                  color: message.isStarred ? const Color(0xFFE2A100) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageDetail extends StatelessWidget {
  const _MessageDetail({super.key, required this.state, this.onBack});

  final AppState state;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final message = state.selectedMessage;
    if (message == null) {
      return const _EmptyState(
          icon: Icons.mail_outline_rounded, text: '选择一封邮件');
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              if (onBack != null)
                IconButton(
                  tooltip: '返回',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              Expanded(
                child: Text(message.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              Tooltip(
                message: '回复',
                child: IconButton(
                  onPressed: () =>
                      _showComposer(context, state, replyTo: message),
                  icon: const Icon(Icons.reply_rounded),
                ),
              ),
              Tooltip(
                message: '转发',
                child: IconButton(
                  onPressed: () =>
                      _showComposer(context, state, forwardFrom: message),
                  icon: const Icon(Icons.forward_rounded),
                ),
              ),
              Tooltip(
                message: message.isStarred ? '取消星标' : '星标',
                child: IconButton(
                  onPressed: () => state.toggleStar(message),
                  icon: Icon(message.isStarred
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Text(_initial(message.from),
                        style: TextStyle(color: scheme.onPrimaryContainer)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message.from.label,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                            '发给 ${message.to.map((item) => item.label).join(', ')}',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Text(_longTime(message.displayTime),
                      style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
              const SizedBox(height: 28),
              SelectableText(
                message.bodyText.isEmpty ? message.snippet : message.bodyText,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(height: 1.55),
              ),
              if (message.attachments.isNotEmpty) ...[
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final attachment in message.attachments)
                      InputChip(
                        avatar: const Icon(Icons.attach_file_rounded, size: 18),
                        label: Text(attachment.fileName),
                        onPressed: () {},
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account});

  final MailAccount account;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.account_circle_outlined),
      title: Text(account.displayName, overflow: TextOverflow.ellipsis),
      subtitle: Text(account.email, overflow: TextOverflow.ellipsis),
      trailing: _ProviderBadge(provider: account.provider),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile(
      {required this.folder, required this.selected, required this.onTap});

  final MailFolder folder;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      selectedTileColor:
          Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.5),
      leading: Icon(_folderIcon(folder.role)),
      title: Text(folder.name, overflow: TextOverflow.ellipsis),
      trailing: folder.unreadCount == 0
          ? null
          : _CountBadge(count: folder.unreadCount),
      onTap: onTap,
    );
  }
}

class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge({required this.provider});

  final String provider;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: provider,
      child: Icon(
        provider == 'gmail'
            ? Icons.mail_rounded
            : provider == 'outlook'
                ? Icons.business_center_rounded
                : Icons.storage_rounded,
        size: 18,
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
          color: scheme.primary, borderRadius: BorderRadius.circular(999)),
      child: Text('$count',
          style:
              TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700)),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: scheme.onTertiaryContainer),
                  overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: scheme.onErrorContainer),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ComposeDialog extends StatefulWidget {
  const _ComposeDialog({required this.state, this.replyTo, this.forwardFrom});

  final AppState state;
  final MailMessage? replyTo;
  final MailMessage? forwardFrom;

  @override
  State<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<_ComposeDialog> {
  late final TextEditingController _to;
  late final TextEditingController _subject;
  late final TextEditingController _body;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final reply = widget.replyTo;
    final forward = widget.forwardFrom;
    _to = TextEditingController(text: reply == null ? '' : reply.from.email);
    _subject = TextEditingController(
      text: reply != null
          ? 'Re: ${reply.subject}'
          : forward != null
              ? 'Fwd: ${forward.subject}'
              : '',
    );
    _body = TextEditingController(
      text: forward == null
          ? ''
          : '\n\n---------- Forwarded message ----------\n${forward.bodyText}',
    );
  }

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Dialog.fullscreen(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: width < 720 ? double.infinity : 760),
          child: Scaffold(
            appBar: AppBar(
              title: const Text('写信'),
              actions: [
                TextButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                  label: const Text('发送'),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _to,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.person_add_alt_1_rounded),
                      labelText: '收件人'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _subject,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.subject_rounded), labelText: '主题'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _body,
                  minLines: 14,
                  maxLines: 24,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                      alignLabelWithHint: true, labelText: '正文'),
                ),
                const SizedBox(height: 12),
                const Wrap(
                  spacing: 8,
                  children: [
                    InputChip(
                        avatar: Icon(Icons.attach_file_rounded),
                        label: Text('附件')),
                    InputChip(
                        avatar: Icon(Icons.image_outlined),
                        label: Text('内联图片')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _send() async {
    final recipients = _to.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map((email) => Address(email: email))
        .toList();
    if (recipients.isEmpty) {
      return;
    }
    setState(() => _sending = true);
    await widget.state.sendMessage(
        to: recipients, subject: _subject.text.trim(), body: _body.text);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final settings = state.snapshot?.settings;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('设置', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: settings?.remoteImagesDefault ?? false,
              onChanged: null,
              secondary: const Icon(Icons.image_not_supported_outlined),
              title: const Text('默认加载远程图片'),
              subtitle: const Text('当前默认关闭，防止追踪像素泄露阅读行为'),
            ),
            ListTile(
              leading: const Icon(Icons.density_medium_rounded),
              title: const Text('显示密度'),
              subtitle: Text(settings?.density ?? 'comfortable'),
            ),
            ListTile(
              leading: const Icon(Icons.key_rounded),
              title: const Text('账号安全'),
              subtitle: Text(state.offlineMode ? '离线演示模式' : '已连接后端'),
            ),
          ],
        ),
      ),
    );
  }
}

void _showComposer(BuildContext context, AppState state,
    {MailMessage? replyTo, MailMessage? forwardFrom}) {
  showDialog<void>(
    context: context,
    builder: (_) => _ComposeDialog(
        state: state, replyTo: replyTo, forwardFrom: forwardFrom),
  );
}

void _showSettings(BuildContext context, AppState state) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _SettingsSheet(state: state),
  );
}

IconData _folderIcon(String role, {bool selected = false}) {
  switch (role) {
    case 'inbox':
      return selected ? Icons.inbox_rounded : Icons.inbox_outlined;
    case 'sent':
      return selected ? Icons.send_rounded : Icons.send_outlined;
    case 'drafts':
      return selected ? Icons.drafts_rounded : Icons.drafts_outlined;
    case 'archive':
      return selected ? Icons.archive_rounded : Icons.archive_outlined;
    case 'trash':
      return selected ? Icons.delete_rounded : Icons.delete_outline_rounded;
    default:
      return selected ? Icons.folder_rounded : Icons.folder_outlined;
  }
}

String _shortTime(DateTime? value) {
  if (value == null) {
    return '';
  }
  final now = DateTime.now();
  if (now.difference(value).inDays == 0) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
  return '${value.month}/${value.day}';
}

String _longTime(DateTime? value) {
  if (value == null) {
    return '';
  }
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

String _initial(Address address) {
  final source = address.name.isNotEmpty ? address.name : address.email;
  if (source.isEmpty) {
    return '?';
  }
  return source.substring(0, 1).toUpperCase();
}
