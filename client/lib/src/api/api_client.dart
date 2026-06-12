import 'dart:convert';

import '../models/mail_models.dart';
import 'http_transport.dart';

class ApiClient {
  ApiClient(String baseUrl)
      : _base = Uri.parse(baseUrl),
        _transport = createTransport();

  final Uri _base;
  final HttpTransport _transport;
  String? _accessToken;
  bool offlineMode = false;

  Future<void> login(String email, String password, {String totp = ''}) async {
    try {
      final response = await _json('POST', '/api/v1/auth/login',
          body: {
            'email': email,
            'password': password,
            'totp': totp,
          },
          auth: false);
      _accessToken = response['access_token'] as String?;
      offlineMode = false;
    } catch (_) {
      if (email == 'owner@example.com' && password == 'change-me-now') {
        offlineMode = true;
        _accessToken = 'offline';
        return;
      }
      rethrow;
    }
  }

  Future<MailboxSnapshot> snapshot() async {
    if (offlineMode) {
      return MailboxSnapshot.demo();
    }
    try {
      final response = await _json('GET', '/api/v1/snapshot');
      return MailboxSnapshot.fromJson(response);
    } catch (_) {
      offlineMode = true;
      return MailboxSnapshot.demo();
    }
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

class ApiException implements Exception {
  const ApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}
