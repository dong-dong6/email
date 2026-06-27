part of '../mail_home_screen.dart';

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
    _microsoftClientId.text = settings?.microsoftClientId ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          _IconSurface(
            icon: Icons.add_link_rounded,
            color: scheme.primary,
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('添加邮箱')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'gmail',
                    icon: Icon(Icons.mail_rounded),
                    label: Text('Gmail'),
                  ),
                  ButtonSegment(
                    value: 'outlook',
                    icon: Icon(Icons.business_center_rounded),
                    label: Text('Outlook'),
                  ),
                  ButtonSegment(
                    value: 'imap',
                    icon: Icon(Icons.storage_rounded),
                    label: Text('IMAP'),
                  ),
                ],
                selected: {_provider},
                onSelectionChanged: (value) {
                  _setProvider(value.first);
                },
                showSelectedIcon: false,
                style: ButtonStyle(
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_MailDimens.radius),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
                  hasSavedSecret: _hasSavedOAuthSecret,
                  onCopy: _copyOAuthUrl,
                ),
              ] else ...[
                _FormSection(
                  icon: Icons.person_outline_rounded,
                  title: '登录信息',
                  child: Column(
                    children: [
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
                          prefixIcon: Icon(Icons.alternate_email_rounded),
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
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _FormSection(
                  icon: Icons.dns_outlined,
                  title: '服务器设置',
                  child: Column(
                    children: [
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
                              decoration:
                                  const InputDecoration(labelText: '端口'),
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
                              decoration:
                                  const InputDecoration(labelText: '端口'),
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
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(_MailDimens.radius),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: scheme.onSecondaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '这里用于其他邮箱服务商。Gmail 和 Outlook 请使用官方授权入口，不要填写邮箱密码。',
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
      final current =
          widget.state.snapshot?.settings ?? MailboxSnapshot.empty().settings;
      final clientIdChanged = _provider == 'gmail'
          ? current.gmailClientId != clientId
          : current.microsoftClientId != clientId;
      if (clientSecret.isEmpty && (!_hasSavedOAuthSecret || clientIdChanged)) {
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
      await widget.state.updateSettings(
        current.copyWith(
          gmailClientId: _provider == 'gmail' ? clientId : null,
          gmailClientSecret: _provider == 'gmail' && clientSecret.isNotEmpty
              ? clientSecret
              : null,
          microsoftClientId: _provider == 'outlook' ? clientId : null,
          microsoftClientSecret:
              _provider == 'outlook' && clientSecret.isNotEmpty
                  ? clientSecret
                  : null,
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

  bool get _hasSavedOAuthSecret {
    final settings = widget.state.snapshot?.settings;
    if (_provider == 'gmail') {
      return settings?.hasGmailClientSecret ?? false;
    }
    if (_provider == 'outlook') {
      return settings?.hasMicrosoftClientSecret ?? false;
    }
    return false;
  }

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
    required this.hasSavedSecret,
    required this.onCopy,
  });

  final String provider;
  final OAuthStart? oauthStart;
  final OAuthStatus? oauthStatus;
  final String? oauthStatusError;
  final TextEditingController clientIdController;
  final TextEditingController clientSecretController;
  final bool hasSavedSecret;
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
            hintText: hasSavedSecret ? '已保存，留空不修改' : null,
            helperText: hasSavedSecret ? 'Secret 只保存在后端，不会回填到客户端。' : null,
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

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(_MailDimens.radius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
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

