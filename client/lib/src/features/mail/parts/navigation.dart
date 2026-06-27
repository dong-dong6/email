part of '../mail_home_screen.dart';

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedAccount = state.selectedAccount;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(_MailDimens.panelPadding),
            child: Row(
              children: [
                _IconSurface(
                  icon: Icons.alternate_email_rounded,
                  color: scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '邮箱工作台',
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _sidebarSubtitle(state),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: '同步当前账号',
                  child: IconButton(
                    onPressed:
                        state.isLoading ? null : state.syncSelectedAccount,
                    icon: state.isLoading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                  ),
                ),
              ],
            ),
          ),
          if (state.offlineMode || state.isLoading || state.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _StatusPill(
                icon: state.error != null
                    ? Icons.error_outline_rounded
                    : state.offlineMode
                        ? Icons.cloud_off_rounded
                        : Icons.sync_rounded,
                text: state.error != null
                    ? '需要处理：${state.error}'
                    : state.offlineMode
                        ? '离线模式'
                        : '正在同步',
              ),
            ),
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
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                _SectionLabel(
                  text: '账号',
                  trailing: Text(
                    '${state.accounts.length}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
                for (final account in state.accounts)
                  _AccountTile(
                    account: account,
                    selected: selectedAccount?.id == account.id,
                    onTap: () => state.selectAccount(account.id),
                  ),
                _SectionLabel(
                  text: selectedAccount == null
                      ? '文件夹'
                      : '${selectedAccount.displayName} 的文件夹',
                ),
                for (final folder in state.visibleFolders)
                  _FolderTile(
                    folder: folder,
                    selected: state.selectedFolder?.id == folder.id,
                    onTap: () => state.selectFolder(folder.id),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withOpacity(0.55),
                borderRadius: BorderRadius.circular(_MailDimens.radius),
              ),
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
                    message: '刷新快照',
                    child: IconButton(
                      onPressed: state.reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      state.offlineMode ? 'OFFLINE' : 'ONLINE',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: state.offlineMode
                                ? scheme.error
                                : scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final folders = state.visibleFolders.take(6).toList();
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
          padding: const EdgeInsets.only(bottom: 8),
          child: IconButton(
            tooltip: '添加邮箱',
            onPressed: () => _showAddAccount(context, state),
            icon: const Icon(Icons.add_rounded),
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

String _sidebarSubtitle(AppState state) {
  final account = state.selectedAccount;
  if (account == null) {
    return state.accounts.isEmpty ? '还没有邮箱账号' : '${state.accounts.length} 个账号';
  }
  return '${account.email} · ${account.status}';
}

