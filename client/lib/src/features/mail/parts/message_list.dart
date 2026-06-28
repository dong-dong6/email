part of '../mail_home_screen.dart';

class _MessageList extends StatefulWidget {
  const _MessageList(
      {required this.state, required this.compact, this.onOpenMessage});

  final AppState state;
  final bool compact;
  final VoidCallback? onOpenMessage;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.state.query);
  }

  @override
  void didUpdateWidget(covariant _MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_searchController.text != widget.state.query) {
      _searchController.text = widget.state.query;
      _searchController.selection = TextSelection.collapsed(
        offset: _searchController.text.length,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final messages = widget.state.visibleMessages;
    final hasSelection = widget.state.selectedMessageIds.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            widget.compact ? 12 : 16,
            14,
            widget.compact ? 12 : 16,
            10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedFolderTitle(widget.state),
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
                      _messageCountLabel(widget.state),
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
                controller: _searchController,
                leading: const Icon(Icons.search_rounded),
                hintText: '搜索邮件',
                onChanged: widget.state.setQuery,
                trailing: [
                  if (widget.state.query.isNotEmpty)
                    IconButton(
                      tooltip: '清除',
                      onPressed: () {
                        _searchController.clear();
                        widget.state.setQuery('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _MessageFilterBar(state: widget.state),
              if (hasSelection) ...[
                const SizedBox(height: 10),
                _BulkSelectionBar(
                  state: widget.state,
                  compact: widget.compact,
                ),
              ],
            ],
          ),
        ),
        if (widget.state.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _InlineError(text: widget.state.error!),
          ),
        Expanded(
          child: messages.isEmpty
              ? _EmptyState(
                  icon: widget.state.isLoading
                      ? Icons.sync_rounded
                      : widget.state.query.trim().isEmpty
                          ? Icons.inbox_rounded
                          : Icons.search_off_rounded,
                  text: widget.state.isLoading
                      ? '正在同步邮件'
                      : widget.state.query.trim().isEmpty
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
                      selected: widget.state.selectedMessage?.id == message.id,
                      selectedForBatch:
                          widget.state.selectedMessageIds.contains(message.id),
                      compact: widget.compact,
                      onTap: () {
                        widget.state.selectMessage(message.id);
                        widget.onOpenMessage?.call();
                      },
                      onToggleSelected: () =>
                          widget.state.toggleMessageSelection(message.id),
                      onStar: () => widget.state.toggleStar(message),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _MessageFilterBar extends StatelessWidget {
  const _MessageFilterBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<MailMessageFilter>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: MailMessageFilter.all,
            icon: const Icon(Icons.all_inbox_rounded),
            label: Text('全部 ${state.matchingMessages.length}'),
          ),
          ButtonSegment(
            value: MailMessageFilter.unread,
            icon: const Icon(Icons.mark_email_unread_outlined),
            label: Text('未读 ${state.matchingUnreadCount}'),
          ),
          ButtonSegment(
            value: MailMessageFilter.starred,
            icon: const Icon(Icons.star_outline_rounded),
            label: Text('星标 ${state.matchingStarredCount}'),
          ),
        ],
        selected: {state.messageFilter},
        onSelectionChanged: (values) => state.setMessageFilter(values.first),
      ),
    );
  }
}

class _BulkSelectionBar extends StatelessWidget {
  const _BulkSelectionBar({required this.state, required this.compact});

  final AppState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = state.selectedMessages;
    final selectedCount = selected.length;
    final allSelected = state.allVisibleMessagesSelected;
    final hasUnread = selected.any((message) => !message.isRead);
    final hasUnstarred = selected.any((message) => !message.isStarred);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withOpacity(0.58),
        borderRadius: BorderRadius.circular(_MailDimens.radius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Checkbox(
              tristate: true,
              value: allSelected
                  ? true
                  : state.anyVisibleMessagesSelected
                      ? null
                      : false,
              onChanged: (_) => state.setVisibleMessagesSelected(!allSelected),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Text(
                '已选 $selectedCount',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Tooltip(
              message: hasUnread ? '标为已读' : '标为未读',
              child: IconButton(
                onPressed: selectedCount == 0
                    ? null
                    : () => state.markSelectedRead(hasUnread),
                icon: Icon(hasUnread
                    ? Icons.mark_email_read_outlined
                    : Icons.mark_email_unread_outlined),
              ),
            ),
            Tooltip(
              message: hasUnstarred ? '添加星标' : '取消星标',
              child: IconButton(
                onPressed: selectedCount == 0
                    ? null
                    : () => state.starSelected(hasUnstarred),
                icon: Icon(hasUnstarred
                    ? Icons.star_outline_rounded
                    : Icons.star_rounded),
                color: hasUnstarred ? null : _MailAccent.starred,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '移动到',
              icon: const Icon(Icons.drive_file_move_outlined),
              enabled: selectedCount > 0,
              onSelected: state.moveSelectedMessages,
              itemBuilder: (context) => [
                for (final folder in state.visibleFolders.where(
                  (folder) => folder.id != state.selectedFolder?.id,
                ))
                  PopupMenuItem(
                    value: folder.id,
                    child: ListTile(
                      dense: true,
                      leading: Icon(_folderIcon(folder.role)),
                      title: Text(_folderDisplayName(folder)),
                    ),
                  ),
              ],
            ),
            Tooltip(
              message: '删除',
              child: IconButton(
                onPressed: selectedCount == 0
                    ? null
                    : () => _confirmDeleteSelected(context, state),
                icon: const Icon(Icons.delete_outline_rounded),
                color: scheme.error,
              ),
            ),
            if (!compact)
              Tooltip(
                message: '取消选择',
                child: IconButton(
                  onPressed: state.clearMessageSelection,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSelected(
    BuildContext context,
    AppState state,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除所选邮件'),
        content: Text('确认删除 ${state.selectedMessages.length} 封邮件？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await state.deleteSelectedMessages();
    }
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.selected,
    required this.selectedForBatch,
    required this.compact,
    required this.onTap,
    required this.onToggleSelected,
    required this.onStar,
  });

  final MailMessage message;
  final bool selected;
  final bool selectedForBatch;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onToggleSelected;
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
      color: selectedForBatch
          ? scheme.tertiaryContainer.withOpacity(0.48)
          : selected
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
              SizedBox(
                width: compact ? 38 : 42,
                child: Center(
                  child: Checkbox(
                    value: selectedForBatch,
                    onChanged: (_) => onToggleSelected(),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    4,
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
                      const SizedBox(width: 8),
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
                              message.subject.isEmpty
                                  ? '(无主题)'
                                  : message.subject,
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

String _messageCountLabel(AppState state) {
  final visible = state.visibleMessages.length;
  final matching = state.matchingMessages.length;
  if (visible == matching) {
    return '$visible';
  }
  return '$visible/$matching';
}
