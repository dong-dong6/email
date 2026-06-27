part of '../mail_home_screen.dart';

class _MessageList extends StatelessWidget {
  const _MessageList(
      {required this.state, required this.compact, this.onOpenMessage});

  final AppState state;
  final bool compact;
  final VoidCallback? onOpenMessage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final messages = state.visibleMessages;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            14,
            compact ? 12 : 16,
            10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedFolderTitle(state),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(_MailDimens.radius),
                    ),
                    child: Text(
                      '${messages.length}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SearchBar(
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
              ? _EmptyState(
                  icon: state.isLoading
                      ? Icons.sync_rounded
                      : state.query.trim().isEmpty
                          ? Icons.inbox_rounded
                          : Icons.search_off_rounded,
                  text: state.isLoading
                      ? '正在同步邮件'
                      : state.query.trim().isEmpty
                          ? '这个文件夹还没有邮件'
                          : '没有匹配的邮件',
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
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
    final height =
        compact ? _MailDimens.compactTileHeight : _MailDimens.regularTileHeight;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: message.isRead ? FontWeight.w600 : FontWeight.w900,
          color: scheme.onSurface,
        );
    return AnimatedContainer(
      duration: _MailDurations.quick,
      height: height,
      color: selected
          ? scheme.secondaryContainer.withOpacity(0.42)
          : message.isRead
              ? Colors.transparent
              : scheme.primaryContainer.withOpacity(0.16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              AnimatedContainer(
                duration: _MailDurations.quick,
                width: 4,
                height: double.infinity,
                color: !message.isRead || selected
                    ? scheme.primary
                    : Colors.transparent,
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    compact ? 10 : 12,
                    6,
                    compact ? 10 : 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _StatusDot(
                          color: message.isRead
                              ? scheme.outlineVariant
                              : scheme.primary,
                          size: message.isRead ? 6 : 9,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    message.from.name.isEmpty
                                        ? message.from.email
                                        : message.from.name,
                                    style: titleStyle,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (message.attachments.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.attach_file_rounded,
                                    size: 15,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ],
                                const SizedBox(width: 8),
                                Text(
                                  _shortTime(message.displayTime),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              message.subject.isEmpty ? '(无主题)' : message.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              message.snippet,
                              maxLines: compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Tooltip(
                        message: message.isStarred ? '取消星标' : '星标',
                        child: IconButton(
                          onPressed: onStar,
                          icon: Icon(
                            message.isStarred
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                          ),
                          color: message.isStarred ? _MailAccent.starred : null,
                        ),
                      ),
                    ],
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

