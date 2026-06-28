part of '../mail_home_screen.dart';

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
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                if (onBack != null)
                  IconButton(
                    tooltip: '返回',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                Expanded(
                  child: Text(
                    message.subject.isEmpty ? '(无主题)' : message.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Tooltip(
                  message: message.isRead ? '标为未读' : '标为已读',
                  child: IconButton(
                    onPressed: () =>
                        state.markMessageRead(message, !message.isRead),
                    icon: Icon(message.isRead
                        ? Icons.mark_email_unread_outlined
                        : Icons.mark_email_read_outlined),
                  ),
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
                    color: message.isStarred ? _MailAccent.starred : null,
                    icon: Icon(
                      message.isStarred
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                    ),
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
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(
                          Icons.delete_outline_rounded,
                          color: scheme.error,
                        ),
                        title: const Text('删除'),
                        dense: true,
                      ),
                    ),
                    const PopupMenuDivider(),
                    ...state.visibleFolders
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
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _MailDimens.messageBodyMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest
                                .withOpacity(0.36),
                            borderRadius:
                                BorderRadius.circular(_MailDimens.radius),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  backgroundColor: scheme.primaryContainer,
                                  child: Text(
                                    _initial(message.from),
                                    style: TextStyle(
                                      color: scheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        message.from.label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      _RecipientLine(
                                        label: '发给',
                                        addresses: message.to,
                                      ),
                                      if (message.cc.isNotEmpty)
                                        _RecipientLine(
                                          label: '抄送',
                                          addresses: message.cc,
                                        ),
                                      if (message.bcc.isNotEmpty)
                                        _RecipientLine(
                                          label: '密送',
                                          addresses: message.bcc,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _longTime(message.displayTime),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        _MessageBody(message: message),
                        if (message.attachments.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          Text(
                            '附件',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final attachment in message.attachments)
                                _AttachmentChip(attachment: attachment),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientLine extends StatelessWidget {
  const _RecipientLine({required this.label, required this.addresses});

  final String label;
  final List<Address> addresses;

  @override
  Widget build(BuildContext context) {
    final value = addresses.map((item) => item.label).join(', ');
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '$label $value',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment});

  final MailAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        Icons.attach_file_rounded,
        color: scheme.primary,
        size: 18,
      ),
      label: Text(attachment.fileName, overflow: TextOverflow.ellipsis),
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
    final blockedImageCount =
        nodes.fold<int>(0, (count, node) => count + _blockedImageCount(node));
    final blocks = [
      if (blockedImageCount > 0)
        _RemoteImagesNotice(blockedImageCount: blockedImageCount),
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

class _RemoteImagesNotice extends StatelessWidget {
  const _RemoteImagesNotice({required this.blockedImageCount});

  final int blockedImageCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer.withOpacity(0.58),
          borderRadius: BorderRadius.circular(_MailDimens.radius),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.privacy_tip_outlined,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '已阻止 $blockedImageCount 张远程图片',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
