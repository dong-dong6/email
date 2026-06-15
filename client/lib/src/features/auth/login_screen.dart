import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../services/server_cache.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _server;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _totp = TextEditingController();
  final _cacheService = ServerCacheService();
  List<ServerConfig> _savedServers = [];
  bool _isRegistering = false;
  bool _serverChecked = false;
  String _checkedServerUrl = '';
  bool _checkingServer = false;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: widget.state.apiBaseUrl);
    _loadSavedServers();
  }

  Future<void> _loadSavedServers() async {
    final servers = await _cacheService.loadServers();
    final lastUrl = await _cacheService.getLastServerUrl();
    if (mounted) {
      setState(() {
        _savedServers = servers;
        if (lastUrl != null && lastUrl.isNotEmpty) {
          _server.text = lastUrl;
        }
      });
    }
  }

  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _totp.dispose();
    super.dispose();
  }

  Future<void> _onServerChanged(String value) async {
    final url = value.trim();
    if (url.isEmpty) return;

    setState(() {
      _checkingServer = true;
      _serverChecked = false;
      _checkedServerUrl = '';
      _isRegistering = false;
    });
    await widget.state.checkServer(url);
    if (mounted) {
      setState(() {
        _checkingServer = false;
        if (widget.state.error == null) {
          _serverChecked = true;
          _checkedServerUrl = url;
          _isRegistering = widget.state.needsRegistration;
        }
      });
    }
  }

  Future<void> _submit() async {
    final serverUrl = _server.text.trim();
    if (serverUrl.isEmpty) return;
    if (!_serverChecked || _checkedServerUrl != serverUrl) {
      await _onServerChanged(serverUrl);
      return;
    }

    if (_isRegistering) {
      if (_password.text != _confirmPassword.text) {
        setState(() {
          widget.state.error = '密码不匹配';
        });
        return;
      }
      if (_password.text.length < 8) {
        setState(() {
          widget.state.error = '密码至少需要8个字符';
        });
        return;
      }
      await widget.state.register(
        serverUrl,
        _email.text.trim(),
        _password.text,
      );
    } else {
      await widget.state.login(
        serverUrl,
        _email.text.trim(),
        _password.text,
        _totp.text.trim(),
      );
    }

    if (widget.state.isAuthenticated) {
      await _cacheService.saveServer(ServerConfig(
        url: serverUrl,
        email: _email.text.trim(),
        lastLogin: DateTime.now(),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.alternate_email_rounded,
                        size: 48, color: scheme.primary),
                    const SizedBox(height: 24),
                    Text('Self-hosted Mail',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      !_serverChecked
                          ? '连接你的 VPS 邮箱后端'
                          : _isRegistering
                              ? '创建管理员账户'
                              : '登录管理员账户',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    _buildServerField(),
                    if (_savedServers.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildSavedServers(),
                    ],
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _serverChecked
                          ? _buildCredentialsFields()
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: widget.state.isLoading || _checkingServer
                          ? null
                          : _submit,
                      icon: widget.state.isLoading || _checkingServer
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(!_serverChecked
                              ? Icons.arrow_forward_rounded
                              : _isRegistering
                                  ? Icons.person_add
                                  : Icons.login_rounded),
                      label: Text(!_serverChecked
                          ? '继续'
                          : _isRegistering
                              ? '注册'
                              : '登录'),
                    ),
                    if (widget.state.error != null) ...[
                      const SizedBox(height: 12),
                      Text(widget.state.error!,
                          style: TextStyle(color: scheme.error)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerField() {
    return TextField(
      controller: _server,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.dns_outlined),
        labelText: '服务地址',
        hintText: 'http://你的服务器IP:8080',
        suffixIcon: _checkingServer
            ? const SizedBox(
                width: 20,
                height: 20,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      onSubmitted: (_) => _onServerChanged(_server.text),
      onChanged: (value) {
        final url = value.trim();
        if (_serverChecked && url != _checkedServerUrl) {
          setState(() {
            _serverChecked = false;
            _checkedServerUrl = '';
            _isRegistering = false;
          });
        }
      },
    );
  }

  Widget _buildCredentialsFields() {
    return Column(
      key: ValueKey(_isRegistering ? 'register' : 'login'),
      children: [
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          autofillHints: const [AutofillHints.username],
          decoration: InputDecoration(
              prefixIcon: const Icon(Icons.person_outline),
              labelText: _isRegistering ? '管理员邮箱' : '邮箱'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.lock_outline), labelText: '密码'),
          onSubmitted: (_) => _submit(),
        ),
        if (_isRegistering) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPassword,
            obscureText: true,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.lock_outline), labelText: '确认密码'),
            onSubmitted: (_) => _submit(),
          ),
        ] else ...[
          const SizedBox(height: 12),
          TextField(
            controller: _totp,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.pin_outlined), labelText: 'TOTP，可选'),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ],
    );
  }

  Widget _buildSavedServers() {
    return Wrap(
      spacing: 8,
      children: _savedServers.map((server) {
        return ActionChip(
          avatar: const Icon(Icons.history, size: 18),
          label: Text(
            Uri.tryParse(server.url)?.host ?? server.url,
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: () {
            _server.text = server.url;
            if (server.email.isNotEmpty) {
              _email.text = server.email;
            }
            _onServerChanged(server.url);
          },
        );
      }).toList(),
    );
  }
}
