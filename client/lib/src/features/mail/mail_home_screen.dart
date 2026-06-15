import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../api/api_client.dart';
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
                      '${_folderDisplayName(folder)}  ${folder.unreadCount > 0 ? folder.unreadCount : ''}'),
                ),
            ],
          ),
          Expanded(
            child: Text(
              _selectedFolderTitle(state),
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
          Tooltip(
            message: '添加邮箱',
            child: IconButton(
              onPressed: () => _showAddAccount(context, state),
              icon: const Icon(Icons.add_rounded),
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
                child: Text('邮箱',
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
            child: _StatusPill(icon: Icons.cloud_off_rounded, text: '离线模式'),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: OutlinedButton.icon(
            onPressed: () => _showAddAccount(context, state),
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加邮箱'),
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
    final scheme = Theme.of(context).colorScheme;
    final folders = state.folders.take(5).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: IconButton.filled(
            tooltip: '写信',
            onPressed: () => _showComposer(context, state),
            icon: const Icon(Icons.edit_rounded),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final folder in folders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Tooltip(
                    message: _folderDisplayName(folder),
                    child: IconButton(
                      isSelected: state.selectedFolder?.id == folder.id,
                      style: IconButton.styleFrom(
                        backgroundColor: state.selectedFolder?.id == folder.id
                            ? scheme.secondaryContainer
                            : null,
                        foregroundColor: state.selectedFolder?.id == folder.id
                            ? scheme.onSecondaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                      onPressed: () => state.selectFolder(folder.id),
                      icon: Icon(_folderIcon(folder.role)),
                      selectedIcon:
                          Icon(_folderIcon(folder.role, selected: true)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: IconButton(
            tooltip: '同步',
            onPressed: state.syncSelectedAccount,
            icon: const Icon(Icons.sync_rounded),
          ),
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
              PopupMenuButton<String>(
                tooltip: '更多操作',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  if (value == 'delete') {
                    state.deleteMessage(message);
                  } else if (value.startsWith('move:')) {
                    state.moveMessage(message, value.substring(5));
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text('删除'),
                      dense: true,
                    ),
                  ),
                  const PopupMenuDivider(),
                  ...state.folders
                      .where((f) => f.id != message.folderId)
                      .map((folder) => PopupMenuItem(
                            value: 'move:${folder.id}',
                            child: ListTile(
                              leading: Icon(_folderIcon(folder.role)),
                              title: Text('移到 ${_folderDisplayName(folder)}'),
                              dense: true,
                            ),
                          )),
                ],
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
              _MessageBody(message: message),
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

class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.message});

  final MailMessage message;

  @override
  Widget build(BuildContext context) {
    final html = _sanitizeMailHtml(message.bodyHtml);
    if (html.isNotEmpty) {
      return _HtmlMessageView(html: html);
    }
    return SelectableText(
      message.bodyText.isEmpty ? message.snippet : message.bodyText,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
    );
  }
}

class _HtmlMessageView extends StatelessWidget {
  const _HtmlMessageView({required this.html});

  final String html;

  @override
  Widget build(BuildContext context) {
    final document = html_parser.parse(html);
    final nodes = document.body?.nodes ?? document.nodes;
    final blocks = [
      for (final node in nodes)
        ..._htmlNodeToWidgets(
          context,
          node,
          Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55) ??
              const TextStyle(fontSize: 16, height: 1.55),
        ),
    ];
    if (blocks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks,
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account});

  final MailAccount account;

  @override
  Widget build(BuildContext context) {
    final error = account.lastError.trim();
    return ListTile(
      leading: const Icon(Icons.account_circle_outlined),
      title: Text(account.displayName, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        error.isEmpty ? account.email : '${account.email} · ${account.status}',
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error.isNotEmpty)
            Tooltip(
              message: error,
              child: Icon(Icons.error_outline_rounded,
                  color: Theme.of(context).colorScheme.error, size: 18),
            ),
          _ProviderBadge(provider: account.provider),
        ],
      ),
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
      title: Text(_folderDisplayName(folder), overflow: TextOverflow.ellipsis),
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
                ListenableBuilder(
                  listenable: widget.state,
                  builder: (context, _) {
                    if (widget.state.error != null) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(widget.state.error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      );
                    }
                    return const SizedBox.shrink();
                  },
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
      if (widget.state.error == null) {
        Navigator.of(context).pop();
      } else {
        setState(() => _sending = false);
      }
    }
  }
}

class _AddAccountDialog extends StatefulWidget {
  const _AddAccountDialog({required this.state});

  final AppState state;

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _email = TextEditingController();
  final _displayName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _gmailClientId = TextEditingController();
  final _gmailClientSecret = TextEditingController();
  final _microsoftClientId = TextEditingController();
  final _microsoftClientSecret = TextEditingController();
  final _imapHost = TextEditingController();
  final _imapPort = TextEditingController(text: '993');
  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController(text: '587');
  String _provider = 'gmail';
  bool _imapTls = true;
  bool _smtpTls = true;
  bool _saving = false;
  OAuthStart? _oauthStart;
  OAuthStatus? _oauthStatus;
  Timer? _oauthPoller;
  String? _oauthStatusError;
  String? _formError;

  @override
  void dispose() {
    _oauthPoller?.cancel();
    _email.dispose();
    _displayName.dispose();
    _username.dispose();
    _password.dispose();
    _gmailClientId.dispose();
    _gmailClientSecret.dispose();
    _microsoftClientId.dispose();
    _microsoftClientSecret.dispose();
    _imapHost.dispose();
    _imapPort.dispose();
    _smtpHost.dispose();
    _smtpPort.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final settings = widget.state.snapshot?.settings;
    _gmailClientId.text = settings?.gmailClientId ?? '';
    _gmailClientSecret.text = settings?.gmailClientSecret ?? '';
    _microsoftClientId.text = settings?.microsoftClientId ?? '';
    _microsoftClientSecret.text = settings?.microsoftClientSecret ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('添加邮箱'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _provider,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                  labelText: '邮箱类型',
                ),
                items: const [
                  DropdownMenuItem(value: 'gmail', child: Text('Gmail 官方授权')),
                  DropdownMenuItem(
                      value: 'outlook', child: Text('Outlook 官方授权')),
                  DropdownMenuItem(
                      value: 'imap', child: Text('其他邮箱 IMAP/SMTP')),
                ],
                onChanged: (value) => _setProvider(value ?? 'gmail'),
              ),
              const SizedBox(height: 12),
              if (_isOAuthProvider) ...[
                _OAuthProviderPanel(
                  provider: _provider,
                  oauthStart: _oauthStart,
                  oauthStatus: _oauthStatus,
                  oauthStatusError: _oauthStatusError,
                  clientIdController: _provider == 'gmail'
                      ? _gmailClientId
                      : _microsoftClientId,
                  clientSecretController: _provider == 'gmail'
                      ? _gmailClientSecret
                      : _microsoftClientSecret,
                  onCopy: _copyOAuthUrl,
                ),
              ] else ...[
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                    labelText: '邮箱地址',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _displayName,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.badge_outlined),
                    labelText: '显示名称，可选',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _username,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.person_outline_rounded),
                    labelText: '登录用户名',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.key_rounded),
                    labelText: '邮箱密码 / 应用专用密码',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _imapHost,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.move_to_inbox_rounded),
                          labelText: 'IMAP 服务器',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 96,
                      child: TextField(
                        controller: _imapPort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '端口'),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _imapTls,
                  onChanged: (value) => setState(() => _imapTls = value),
                  secondary: const Icon(Icons.lock_outline_rounded),
                  title: const Text('IMAP TLS'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _smtpHost,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.outbox_rounded),
                          labelText: 'SMTP 服务器',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 96,
                      child: TextField(
                        controller: _smtpPort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '端口'),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _smtpTls,
                  onChanged: (value) => setState(() => _smtpTls = value),
                  secondary: const Icon(Icons.lock_outline_rounded),
                  title: const Text('SMTP TLS / STARTTLS'),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: scheme.onSecondaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '这里只用于其他邮箱服务商。Gmail 和 Outlook 请使用官方授权入口，不要填写邮箱密码。',
                          style: TextStyle(color: scheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_formError != null) ...[
                const SizedBox(height: 12),
                _InlineError(text: _formError!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _saving
              ? null
              : _oauthStatus?.status == 'completed'
                  ? _finishOAuth
                  : _submit,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_oauthStatus?.status == 'completed'
                  ? Icons.check_rounded
                  : _isOAuthProvider
                      ? Icons.open_in_browser_rounded
                      : Icons.add_rounded),
          label: Text(_oauthStatus?.status == 'completed'
              ? '完成'
              : _isOAuthProvider
                  ? '生成授权链接'
                  : '添加'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_isOAuthProvider) {
      final clientId =
          (_provider == 'gmail' ? _gmailClientId : _microsoftClientId)
              .text
              .trim();
      final clientSecret =
          (_provider == 'gmail' ? _gmailClientSecret : _microsoftClientSecret)
              .text
              .trim();
      if (clientId.isEmpty) {
        setState(() => _formError = _provider == 'gmail'
            ? '请填写 Google OAuth Client ID'
            : '请填写 Microsoft OAuth Client ID');
        return;
      }
      if (clientSecret.isEmpty) {
        setState(() => _formError = _provider == 'gmail'
            ? '请填写 Google OAuth Client Secret'
            : '请填写 Microsoft OAuth Client Secret');
        return;
      }
      setState(() {
        _saving = true;
        _formError = null;
        _oauthStart = null;
        _oauthStatus = null;
        _oauthStatusError = null;
      });
      _oauthPoller?.cancel();
      final current =
          widget.state.snapshot?.settings ?? MailboxSnapshot.empty().settings;
      await widget.state.updateSettings(
        current.copyWith(
          gmailClientId: _provider == 'gmail' ? clientId : null,
          gmailClientSecret: _provider == 'gmail' ? clientSecret : null,
          microsoftClientId: _provider == 'outlook' ? clientId : null,
          microsoftClientSecret: _provider == 'outlook' ? clientSecret : null,
        ),
      );
      if (!mounted) {
        return;
      }
      if (widget.state.error != null) {
        setState(() {
          _saving = false;
          _formError = widget.state.error;
        });
        return;
      }
      final oauth = await widget.state.startOAuth(_provider);
      if (!mounted) {
        return;
      }
      if (oauth == null || widget.state.error != null) {
        setState(() {
          _saving = false;
          _formError = widget.state.error ?? '授权链接生成失败';
        });
        return;
      }
      await Clipboard.setData(ClipboardData(text: oauth.authUrl));
      setState(() {
        _saving = false;
        _oauthStart = oauth;
        _oauthStatus = OAuthStatus(
          state: oauth.state,
          provider: oauth.provider,
          status: 'pending',
        );
        _oauthStatusError = null;
      });
      _startOAuthPolling(oauth.state);
      return;
    }

    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _formError = '请填写有效邮箱地址');
      return;
    }
    final imapPort = _parsePort(_imapPort.text);
    final smtpPort = _parsePort(_smtpPort.text);
    if (_provider != 'mock' &&
        (_password.text.isEmpty ||
            _imapHost.text.trim().isEmpty ||
            _smtpHost.text.trim().isEmpty ||
            imapPort == null ||
            smtpPort == null)) {
      setState(() => _formError = '请补全密码、服务器和端口');
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    await widget.state.addAccount(
      provider: _provider,
      email: email,
      displayName: _displayName.text.trim(),
      username: _username.text.trim(),
      password: _password.text,
      imapHost: _imapHost.text.trim(),
      imapPort: imapPort ?? 0,
      imapTls: _imapTls,
      smtpHost: _smtpHost.text.trim(),
      smtpPort: smtpPort ?? 0,
      smtpTls: _smtpTls,
    );
    if (!mounted) {
      return;
    }
    if (widget.state.error != null) {
      setState(() => _saving = false);
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _copyOAuthUrl() async {
    final url = _oauthStart?.authUrl;
    if (url == null || url.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('授权链接已复制')),
    );
  }

  void _setProvider(String provider) {
    _oauthPoller?.cancel();
    setState(() {
      _provider = provider;
      _formError = null;
      _oauthStart = null;
      _oauthStatus = null;
      _oauthStatusError = null;
      switch (provider) {
        case 'gmail':
        case 'outlook':
          _email.clear();
          _displayName.clear();
          _username.clear();
          _password.clear();
          _imapHost.clear();
          _smtpHost.clear();
          _imapTls = true;
          _smtpTls = true;
          break;
        case 'imap':
          _imapHost.clear();
          _imapPort.text = '993';
          _smtpHost.clear();
          _smtpPort.text = '587';
          _imapTls = true;
          _smtpTls = true;
          break;
      }
    });
  }

  bool get _isOAuthProvider => _provider == 'gmail' || _provider == 'outlook';

  void _startOAuthPolling(String state) {
    _oauthPoller?.cancel();
    _checkOAuthStatus(state);
    _oauthPoller = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkOAuthStatus(state),
    );
  }

  Future<void> _checkOAuthStatus(String state) async {
    try {
      final status = await widget.state.getOAuthStatus(state);
      if (!mounted) {
        return;
      }
      setState(() {
        _oauthStatus = status;
        _oauthStatusError = null;
      });
      if (status.isTerminal) {
        _oauthPoller?.cancel();
      }
      if (status.status == 'callback_received' ||
          status.status == 'completed') {
        widget.state.reload();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _oauthStatusError = error.toString());
      return;
    }
  }

  void _finishOAuth() {
    widget.state.reload();
    Navigator.of(context).pop();
  }

  int? _parsePort(String value) {
    final port = int.tryParse(value.trim());
    if (port == null || port <= 0 || port > 65535) {
      return null;
    }
    return port;
  }
}

class _OAuthProviderPanel extends StatelessWidget {
  const _OAuthProviderPanel({
    required this.provider,
    required this.oauthStart,
    required this.oauthStatus,
    required this.oauthStatusError,
    required this.clientIdController,
    required this.clientSecretController,
    required this.onCopy,
  });

  final String provider;
  final OAuthStart? oauthStart;
  final OAuthStatus? oauthStatus;
  final String? oauthStatusError;
  final TextEditingController clientIdController;
  final TextEditingController clientSecretController;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isGmail = provider == 'gmail';
    final title =
        isGmail ? '使用 Google 官方授权连接 Gmail' : '使用 Microsoft 官方授权连接 Outlook';
    final subtitle = isGmail
        ? '不会保存你的 Gmail 密码。后端将通过 Gmail API 读取、同步和发送邮件。'
        : '不会保存你的 Outlook 密码。后端将通过 Microsoft Graph Mail API 读取、同步和发送邮件。';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withOpacity(0.45),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.primary.withOpacity(0.18)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isGmail ? Icons.mail_rounded : Icons.business_center_rounded,
                color: scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(subtitle,
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: clientIdController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.key_rounded),
            labelText: isGmail
                ? 'Google OAuth Client ID'
                : 'Microsoft OAuth Client ID',
            hintText: isGmail
                ? 'xxxx.apps.googleusercontent.com'
                : 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: clientSecretController,
          obscureText: true,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.password_rounded),
            labelText: isGmail
                ? 'Google OAuth Client Secret'
                : 'Microsoft OAuth Client Secret',
          ),
        ),
        const SizedBox(height: 12),
        const _OAuthStep(text: '1. 在官方控制台创建 OAuth 应用，并把回调地址填进去'),
        const _OAuthStep(text: '2. 在这里填写 Client ID 和 Secret，客户端会上传保存到后端'),
        const _OAuthStep(text: '3. 生成授权链接，复制到浏览器打开并登录官方账号授权'),
        if (oauthStart != null) ...[
          const SizedBox(height: 12),
          Text('回调地址', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          SelectableText(
            oauthStart!.redirectUri,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Text('授权链接', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withOpacity(0.72),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              oauthStart!.authUrl,
              style: TextStyle(color: scheme.primary),
            ),
          ),
          const SizedBox(height: 8),
          _OAuthStatusCard(status: oauthStatus, error: oauthStatusError),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('复制链接'),
            ),
          ),
        ],
      ],
    );
  }
}

class _OAuthStatusCard extends StatelessWidget {
  const _OAuthStatusCard({required this.status, required this.error});

  final OAuthStatus? status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = status;
    final queryError = error;
    final isError = current?.status == 'error' || queryError != null;
    final isCompleted = current?.status == 'completed';
    final isDone = current?.status == 'callback_received' || isCompleted;
    final icon = isError
        ? Icons.error_outline_rounded
        : isDone
            ? Icons.task_alt_rounded
            : Icons.hourglass_top_rounded;
    final title = isError
        ? current?.status == 'error'
            ? '授权失败'
            : '状态查询失败'
        : isDone
            ? isCompleted
                ? '邮箱绑定完成'
                : '浏览器授权已返回后端'
            : '等待浏览器授权回调';
    final body = isError
        ? (queryError ??
            (current?.error.isNotEmpty == true
                ? current!.error
                : '官方授权返回失败，请重新生成链接。'))
        : isDone
            ? isCompleted
                ? '后端已经完成 token 交换并创建账号。点击完成关闭窗口。'
                : '后端已经收到 OAuth 回调，正在交换 token 并创建账号。'
            : '授权链接已复制。请在浏览器打开链接并完成登录，这里会自动更新状态。';
    final background = isError
        ? scheme.errorContainer.withOpacity(0.72)
        : isDone
            ? scheme.tertiaryContainer.withOpacity(0.62)
            : scheme.secondaryContainer.withOpacity(0.52);
    final foreground = isError
        ? scheme.onErrorContainer
        : isDone
            ? scheme.onTertiaryContainer
            : scheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(body, style: TextStyle(color: foreground)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OAuthStep extends StatelessWidget {
  const _OAuthStep({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
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
              subtitle: Text(state.offlineMode ? '离线模式' : '已连接后端'),
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

void _showAddAccount(BuildContext context, AppState state) {
  showDialog<void>(
    context: context,
    builder: (_) => _AddAccountDialog(state: state),
  );
}

String _folderDisplayName(MailFolder folder) {
  switch (folder.role.toLowerCase()) {
    case 'inbox':
      return '收件箱';
    case 'sent':
      return '已发送';
    case 'drafts':
    case 'draft':
      return '草稿箱';
    case 'archive':
      return '归档';
    case 'trash':
    case 'deleted':
      return '已删除';
    case 'spam':
    case 'junk':
      return '垃圾邮件';
    case 'starred':
      return '星标邮件';
    default:
      return switch (folder.name.trim().toLowerCase()) {
        'inbox' => '收件箱',
        'sent' || 'sent mail' => '已发送',
        'draft' || 'drafts' => '草稿箱',
        'archive' || 'all mail' => '归档',
        'trash' || 'deleted items' => '已删除',
        'spam' || 'junk' || 'junk email' => '垃圾邮件',
        'starred' => '星标邮件',
        _ => folder.name,
      };
  }
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

String _sanitizeMailHtml(String html) {
  var value = html.trim();
  if (value.isEmpty) {
    return '';
  }
  value = value.replaceAll(
      RegExp(
          r'<\s*(script|style|iframe|object|embed|form)\b[^>]*>.*?<\s*/\s*\1\s*>',
          caseSensitive: false,
          dotAll: true),
      '');
  value = value.replaceAll(
      RegExp(r'<\s*(script|style|iframe|object|embed|form)\b[^>]*/?\s*>',
          caseSensitive: false),
      '');
  value = value.replaceAll(
      RegExp(r"<img\b[^>]*\bsrc\s*=\s*[" "']https?:[^>]*>",
          caseSensitive: false),
      '');
  value = value.replaceAll(
      RegExp(r"\son[a-z]+\s*=\s*([" "']).*?\1",
          caseSensitive: false, dotAll: true),
      '');
  value = value.replaceAll(
      RegExp(r"\s(href|src)\s*=\s*([" "'])\s*javascript:.*?\2",
          caseSensitive: false, dotAll: true),
      '');
  return value.trim();
}

List<Widget> _htmlNodeToWidgets(
  BuildContext context,
  dom.Node node,
  TextStyle style,
) {
  final scheme = Theme.of(context).colorScheme;
  if (node is dom.Text) {
    final text = _softWrapLongRuns(node.text.replaceAll(RegExp(r'\s+'), ' '));
    if (text.trim().isEmpty) {
      return const [];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SelectableText(text.trim(), style: style),
      ),
    ];
  }
  if (node is! dom.Element) {
    return const [];
  }
  final tag = node.localName?.toLowerCase() ?? '';
  final align = _htmlAlignment(node);
  final children = () => [
        for (final child in node.nodes)
          ..._htmlNodeToWidgets(context, child, style),
      ];
  switch (tag) {
    case 'br':
      return const [SizedBox(height: 8)];
    case 'img':
      return [_HtmlImagePlaceholder(element: node)];
    case 'a':
      final href = node.attributes['href']?.trim() ?? '';
      return [
        Align(
          alignment: align,
          child: _HtmlLinkChip(
            text: _plainText(node).isEmpty ? href : _plainText(node),
            href: href,
          ),
        ),
        const SizedBox(height: 12),
      ];
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
      return [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 10),
          child: Align(
            alignment: align,
            child: SelectableText.rich(
              TextSpan(
                style: style.copyWith(
                  fontSize: switch (tag) {
                    'h1' => 26,
                    'h2' => 22,
                    'h3' => 19,
                    _ => 17,
                  },
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
                children: _htmlInlineSpans(context, node.nodes, style),
              ),
            ),
          ),
        ),
      ];
    case 'p':
    case 'div':
    case 'section':
    case 'article':
    case 'main':
    case 'header':
    case 'footer':
    case 'blockquote':
      if (_hasBlockChildren(node)) {
        return [
          Padding(
            padding: _htmlBlockPadding(tag),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children(),
            ),
          ),
        ];
      }
      final spans = _htmlInlineSpans(context, node.nodes, style);
      if (_isBlankSpans(spans)) {
        return const [SizedBox(height: 10)];
      }
      return [
        Padding(
          padding: _htmlBlockPadding(tag),
          child: Align(
            alignment: align,
            child: SelectableText.rich(
              TextSpan(style: style, children: spans),
              textAlign: _htmlTextAlign(node),
            ),
          ),
        ),
      ];
    case 'ul':
    case 'ol':
      return [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < node.children.length; index++)
                _HtmlListItem(
                  marker: tag == 'ol' ? '${index + 1}.' : '-',
                  element: node.children[index],
                  style: style,
                ),
            ],
          ),
        ),
      ];
    case 'table':
      return [_HtmlTable(element: node, baseStyle: style)];
    case 'tbody':
    case 'thead':
    case 'tfoot':
      return children();
    case 'center':
      return [
        Align(
          alignment: Alignment.center,
          child: Column(children: children()),
        ),
      ];
    default:
      if (_hasBlockChildren(node)) {
        return children();
      }
      final spans = _htmlInlineSpans(context, node.nodes, style);
      if (_isBlankSpans(spans)) {
        return const [];
      }
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SelectableText.rich(TextSpan(style: style, children: spans)),
        ),
      ];
  }
}

List<InlineSpan> _htmlInlineSpans(
  BuildContext context,
  List<dom.Node> nodes,
  TextStyle style,
) {
  final linkColor = Theme.of(context).colorScheme.primary;
  final spans = <InlineSpan>[];
  for (final node in nodes) {
    spans.addAll(_htmlNodeToInlineSpans(node, style, linkColor));
  }
  return _trimTrailingBreaks(spans);
}

List<InlineSpan> _htmlNodeToInlineSpans(
  dom.Node node,
  TextStyle style,
  Color linkColor,
) {
  if (node is dom.Text) {
    final text = _softWrapLongRuns(node.text.replaceAll(RegExp(r'\s+'), ' '));
    if (text.trim().isEmpty) {
      return const [];
    }
    return [TextSpan(text: text, style: style)];
  }
  if (node is! dom.Element) {
    return const [];
  }
  final tag = node.localName?.toLowerCase() ?? '';
  switch (tag) {
    case 'br':
      return const [TextSpan(text: '\n')];
    case 'img':
      final alt = node.attributes['alt']?.trim();
      return [
        TextSpan(
          text: alt == null || alt.isEmpty
              ? '[图片]'
              : '[图片: ${_softWrapLongRuns(alt)}]',
          style: style.copyWith(color: linkColor),
        ),
      ];
    case 'strong':
    case 'b':
      return _htmlChildrenToInlineSpans(
          node, style.copyWith(fontWeight: FontWeight.w700), linkColor);
    case 'em':
    case 'i':
      return _htmlChildrenToInlineSpans(
          node, style.copyWith(fontStyle: FontStyle.italic), linkColor);
    case 'u':
      return _htmlChildrenToInlineSpans(node,
          style.copyWith(decoration: TextDecoration.underline), linkColor);
    case 'code':
      return _htmlChildrenToInlineSpans(
          node,
          style.copyWith(
            fontFamily: 'monospace',
            backgroundColor: const Color(0x14000000),
          ),
          linkColor);
    case 'a':
      final href = node.attributes['href']?.trim() ?? '';
      final label = _plainText(node).trim();
      final text = label.isEmpty ? href : label;
      if (text.isEmpty) {
        return const [];
      }
      return [
        TextSpan(
          text: _softWrapLongRuns(text),
          style: style.copyWith(
            color: linkColor,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
        ),
      ];
    case 'span':
      return _htmlChildrenToInlineSpans(
          node, _styleFromHtml(node, style), linkColor);
    default:
      return _htmlChildrenToInlineSpans(node, style, linkColor);
  }
}

List<InlineSpan> _htmlChildrenToInlineSpans(
  dom.Element element,
  TextStyle style,
  Color linkColor,
) {
  return [
    for (final child in element.nodes)
      ..._htmlNodeToInlineSpans(child, style, linkColor),
  ];
}

class _HtmlLinkChip extends StatelessWidget {
  const _HtmlLinkChip({required this.text, required this.href});

  final String text;
  final String href;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = text.trim().isEmpty ? href : text.trim();
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_rounded, color: scheme.primary, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: SelectableText(
              _softWrapLongRuns(label),
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HtmlImagePlaceholder extends StatelessWidget {
  const _HtmlImagePlaceholder({required this.element});

  final dom.Element element;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alt = element.attributes['alt']?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withOpacity(0.7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.image_not_supported_outlined,
                color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                alt.isEmpty ? '远程图片已阻止' : '远程图片已阻止：$alt',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HtmlListItem extends StatelessWidget {
  const _HtmlListItem({
    required this.marker,
    required this.element,
    required this.style,
  });

  final String marker;
  final dom.Element element;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 28, child: Text(marker, style: style)),
          Expanded(
            child: SelectableText.rich(
              TextSpan(
                style: style,
                children: _htmlInlineSpans(context, element.nodes, style),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HtmlTable extends StatelessWidget {
  const _HtmlTable({required this.element, required this.baseStyle});

  final dom.Element element;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final rows = element.querySelectorAll('tr');
    if (rows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in element.nodes)
            ..._htmlNodeToWidgets(context, child, baseStyle),
        ],
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: scheme.outlineVariant),
          children: [
            for (final row in rows)
              TableRow(
                children: [
                  for (final cell in row.children.where((item) =>
                      item.localName == 'td' || item.localName == 'th'))
                    Container(
                      constraints: const BoxConstraints(minWidth: 96),
                      padding: const EdgeInsets.all(10),
                      color: cell.localName == 'th'
                          ? scheme.surfaceContainerHighest
                          : null,
                      child: SelectableText.rich(
                        TextSpan(
                          style: baseStyle.copyWith(
                            fontWeight:
                                cell.localName == 'th' ? FontWeight.w700 : null,
                          ),
                          children:
                              _htmlInlineSpans(context, cell.nodes, baseStyle),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

bool _hasBlockChildren(dom.Element element) {
  const blockTags = {
    'address',
    'article',
    'aside',
    'blockquote',
    'center',
    'div',
    'footer',
    'h1',
    'h2',
    'h3',
    'h4',
    'header',
    'li',
    'main',
    'ol',
    'p',
    'section',
    'table',
    'ul',
  };
  return element.children.any((child) => blockTags.contains(child.localName));
}

bool _isBlankSpans(List<InlineSpan> spans) {
  return spans
      .every((span) => span is TextSpan && (span.text ?? '').trim().isEmpty);
}

String _plainText(dom.Element element) {
  return element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

Alignment _htmlAlignment(dom.Element element) {
  return switch (_htmlTextAlign(element)) {
    TextAlign.center => Alignment.center,
    TextAlign.right || TextAlign.end => Alignment.centerRight,
    _ => Alignment.centerLeft,
  };
}

TextAlign _htmlTextAlign(dom.Element element) {
  final align =
      '${element.attributes['align'] ?? ''} ${element.attributes['style'] ?? ''}'
          .toLowerCase();
  if (align.contains('center')) {
    return TextAlign.center;
  }
  if (align.contains('right')) {
    return TextAlign.right;
  }
  return TextAlign.start;
}

EdgeInsets _htmlBlockPadding(String tag) {
  return switch (tag) {
    'blockquote' => const EdgeInsets.fromLTRB(16, 4, 0, 14),
    'div' ||
    'section' ||
    'article' ||
    'main' ||
    'header' ||
    'footer' =>
      const EdgeInsets.only(bottom: 8),
    _ => const EdgeInsets.only(bottom: 14),
  };
}

TextStyle _styleFromHtml(dom.Element element, TextStyle base) {
  final style = element.attributes['style']?.toLowerCase() ?? '';
  var out = base;
  if (style.contains('font-weight:bold') ||
      style.contains('font-weight: bold')) {
    out = out.copyWith(fontWeight: FontWeight.w700);
  }
  if (style.contains('font-style:italic') ||
      style.contains('font-style: italic')) {
    out = out.copyWith(fontStyle: FontStyle.italic);
  }
  return out;
}

String _selectedFolderTitle(AppState state) {
  final folder = state.selectedFolder;
  return folder == null ? '收件箱' : _folderDisplayName(folder);
}

String _softWrapLongRuns(String value) {
  const chunkSize = 48;
  return value.splitMapJoin(
    RegExp(r'\S{' '$chunkSize' r',}'),
    onMatch: (match) {
      final text = match.group(0) ?? '';
      final buffer = StringBuffer();
      for (var index = 0; index < text.length; index += chunkSize) {
        if (index > 0) {
          buffer.write('\u200B');
        }
        final end = (index + chunkSize).clamp(0, text.length);
        buffer.write(text.substring(index, end));
      }
      return buffer.toString();
    },
    onNonMatch: (text) => text,
  );
}

List<InlineSpan> _trimTrailingBreaks(List<InlineSpan> spans) {
  final out = [...spans];
  while (out.isNotEmpty) {
    final last = out.last;
    if (last is TextSpan && (last.text ?? '').trim().isEmpty) {
      out.removeLast();
      continue;
    }
    break;
  }
  return out;
}
