part of '../mail_home_screen.dart';

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final settings = state.snapshot?.settings;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _IconSurface(
                  icon: Icons.settings_rounded,
                  color: scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '设置',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              title: '阅读与隐私',
              children: [
                _SettingRow(
                  icon: Icons.image_not_supported_outlined,
                  title: '默认加载远程图片',
                  value: settings?.remoteImagesDefault == true ? '开启' : '关闭',
                  subtitle: '关闭可减少追踪像素泄露阅读行为',
                ),
                _SettingRow(
                  icon: Icons.density_medium_rounded,
                  title: '显示密度',
                  value: settings?.density ?? 'comfortable',
                  subtitle: '列表和详情页会按这个密度继续优化',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SettingsSection(
              title: '账号与安全',
              children: [
                _SettingRow(
                  icon: Icons.key_rounded,
                  title: '后端连接',
                  value: state.offlineMode ? '离线' : '在线',
                  subtitle: state.apiBaseUrl,
                  valueColor: state.offlineMode ? scheme.error : scheme.primary,
                ),
                _SettingRow(
                  icon: Icons.mail_rounded,
                  title: 'Gmail OAuth Secret',
                  value: settings?.hasGmailClientSecret == true ? '已配置' : '未配置',
                  subtitle: settings?.gmailClientId.isNotEmpty == true
                      ? settings!.gmailClientId
                      : '添加 Gmail 时配置',
                ),
                _SettingRow(
                  icon: Icons.business_center_rounded,
                  title: 'Microsoft OAuth Secret',
                  value: settings?.hasMicrosoftClientSecret == true
                      ? '已配置'
                      : '未配置',
                  subtitle: settings?.microsoftClientId.isNotEmpty == true
                      ? settings!.microsoftClientId
                      : '添加 Outlook 时配置',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.34),
        borderRadius: BorderRadius.circular(_MailDimens.radius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            for (final child in children) child,
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.valueColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.primary),
      title: Text(title, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: valueColor ?? scheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

