part of '../mail_home_screen.dart';

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: _MailDimens.sidebarWidth, child: _Sidebar(state: state)),
        const VerticalDivider(width: 1),
        SizedBox(
          width: _MailDimens.messageListWidth,
          child: _MessageList(state: state, compact: false),
        ),
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
        SizedBox(width: _MailDimens.railWidth, child: _Rail(state: state)),
        const VerticalDivider(width: 1),
        SizedBox(
          width: _MailDimens.tabletMessageListWidth,
          child: _MessageList(state: state, compact: true),
        ),
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
      duration: _MailDurations.medium,
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

