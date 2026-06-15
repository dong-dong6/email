import 'dart:convert';

import '../models/mail_models.dart';
import 'http_transport.dart';

class ApiClient {
  ApiClient(String baseUrl)
      : _base = _parseBaseUrl(baseUrl),
        _transport = createTransport();

  Uri _base;
  final HttpTransport _transport;
  String? _accessToken;
  bool offlineMode = false;

  String get baseUrl => _base.toString().replaceFirst(RegExp(r'/$'), '');

  void setBaseUrl(String value) {
    _base = _parseBaseUrl(value);
    _accessToken = null;
    offlineMode = false;
  }

  Future<void> login(String email, String password, {String totp = ''}) async {
    final response = await _json('POST', '/api/v1/auth/login',
        body: {
          'email': email,
          'password': password,
          'totp': totp,
        },
        auth: false);
    _accessToken = response['access_token'] as String?;
    offlineMode = false;
  }

  Future<MailboxSnapshot> snapshot() async {
    final response = await _json('GET', '/api/v1/snapshot');
    return MailboxSnapshot.fromJson(response);
  }

  Future<MailAccount> createAccount({
    required String provider,
    required String email,
    required String displayName,
    required String username,
    required String password,
    required String imapHost,
    required int imapPort,
    required bool imapTls,
    required String smtpHost,
    required int smtpPort,
    required bool smtpTls,
  }) async {
    if (offlineMode) {
      return MailAccount(
        id: 'acc_${DateTime.now().microsecondsSinceEpoch}',
        provider: provider,
        email: email,
        displayName: displayName,
        status: provider == 'mock' ? 'active' : 'needs_auth',
      );
    }
    final response = await _json('POST', '/api/v1/accounts', body: {
      'provider': provider,
      'email': email,
      'display_name': displayName,
      'username': username,
      'password': password,
      'imap_host': imapHost,
      'imap_port': imapPort,
      'imap_tls': imapTls,
      'smtp_host': smtpHost,
      'smtp_port': smtpPort,
      'smtp_tls': smtpTls,
    });
    return MailAccount.fromJson(response);
  }

  Future<OAuthStart> startOAuth(String provider) async {
    final response =
        await _json('GET', '/api/v1/accounts/oauth/start?provider=$provider');
    return OAuthStart.fromJson(response);
  }

  Future<OAuthStatus> oauthStatus(String state) async {
    final encodedState = Uri.encodeQueryComponent(state);
    final response =
        await _json('GET', '/api/v1/accounts/oauth/status?state=$encodedState');
    return OAuthStatus.fromJson(response);
  }

  Future<MailSettings> updateSettings(MailSettings settings) async {
    final response =
        await _json('PUT', '/api/v1/settings', body: settings.toJson());
    return MailSettings.fromJson(response);
  }

  Future<void> patchMessage(String id, {bool? isRead, bool? isStarred}) async {
    if (offlineMode) {
      return;
    }
    await _json('PATCH', '/api/v1/messages/$id', body: {
      if (isRead != null) 'is_read': isRead,
      if (isStarred != null) 'is_starred': isStarred,
    });
  }

  Future<void> send({
    required String accountId,
    required List<Address> to,
    required String subject,
    required String bodyText,
  }) async {
    if (offlineMode) {
      return;
    }
    await _json('POST', '/api/v1/send', body: {
      'account_id': accountId,
      'to': to.map((item) => item.toJson()).toList(),
      'subject': subject,
      'body_text': bodyText,
    });
  }

  Future<void> syncAccount(String accountId) async {
    if (offlineMode) {
      return;
    }
    await _json('POST', '/api/v1/accounts/$accountId/sync');
  }

  Future<void> moveMessage(String id, String folderId) async {
    if (offlineMode) return;
    await _json('POST', '/api/v1/messages/$id/move', body: {
      'folder_id': folderId,
    });
  }

  Future<void> deleteMessage(String id) async {
    if (offlineMode) return;
    await _json('DELETE', '/api/v1/messages/$id');
  }

  Future<bool> checkUsers() async {
    final response = await _json('GET', '/api/v1/auth/check', auth: false);
    return response['has_users'] as bool? ?? true;
  }

  Future<void> register(String email, String password) async {
    await _json('POST', '/api/v1/auth/register',
        body: {'email': email, 'password': password}, auth: false);
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth && _accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    final response = await _transport.request(
      method,
      _base.resolve(path),
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }
    return (jsonDecode(response.body) as Map).cast<String, dynamic>();
  }
}

Uri _parseBaseUrl(String value) {
  var normalized = value.trim();
  if (normalized.isEmpty) {
    normalized = 'http://localhost:8080';
  }
  if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
    normalized = 'http://$normalized';
  }
  final uri = Uri.parse(normalized);
  if (!uri.hasScheme || uri.host.isEmpty) {
    throw FormatException('服务地址无效: $value');
  }
  return uri;
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}

class OAuthStart {
  const OAuthStart({
    required this.provider,
    required this.authUrl,
    required this.redirectUri,
    required this.state,
  });

  final String provider;
  final String authUrl;
  final String redirectUri;
  final String state;

  factory OAuthStart.fromJson(Map<String, dynamic> json) {
    return OAuthStart(
      provider: json['provider'] as String? ?? '',
      authUrl: json['auth_url'] as String? ?? '',
      redirectUri: json['redirect_uri'] as String? ?? '',
      state: json['state'] as String? ?? '',
    );
  }
}

class OAuthStatus {
  const OAuthStatus({
    required this.state,
    required this.provider,
    required this.status,
    this.error = '',
    this.accountId = '',
    this.email = '',
    this.updatedAt,
  });

  final String state;
  final String provider;
  final String status;
  final String error;
  final String accountId;
  final String email;
  final DateTime? updatedAt;

  bool get isTerminal =>
      status == 'callback_received' ||
      status == 'completed' ||
      status == 'error';

  factory OAuthStatus.fromJson(Map<String, dynamic> json) {
    final updatedAtValue = json['updated_at'] as String?;
    return OAuthStatus(
      state: json['state'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      status: json['status'] as String? ?? '',
      error: json['error'] as String? ?? '',
      accountId: json['account_id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      updatedAt:
          updatedAtValue == null ? null : DateTime.tryParse(updatedAtValue),
    );
  }
}
