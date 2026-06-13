import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ServerConfig {
  const ServerConfig({
    required this.url,
    this.email = '',
    this.lastLogin,
  });

  final String url;
  final String email;
  final DateTime? lastLogin;

  Map<String, dynamic> toJson() => {
        'url': url,
        'email': email,
        'lastLogin': lastLogin?.toIso8601String(),
      };

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      url: json['url'] as String? ?? '',
      email: json['email'] as String? ?? '',
      lastLogin: json['lastLogin'] != null
          ? DateTime.tryParse(json['lastLogin'] as String)
          : null,
    );
  }
}

class ServerCacheService {
  static const _key = 'saved_servers';
  static const _lastServerKey = 'last_server_url';

  Future<List<ServerConfig>> loadServers() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null) return [];
    final list = (jsonDecode(data) as List).cast<Map<String, dynamic>>();
    return list.map(ServerConfig.fromJson).toList();
  }

  Future<void> saveServer(ServerConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final servers = await loadServers();
    final index = servers.indexWhere((s) => s.url == config.url);
    if (index >= 0) {
      servers[index] = config;
    } else {
      servers.add(config);
    }
    await prefs.setString(
        _key, jsonEncode(servers.map((s) => s.toJson()).toList()));
    await prefs.setString(_lastServerKey, config.url);
  }

  Future<String?> getLastServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastServerKey);
  }

  Future<void> removeServer(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final servers = await loadServers();
    servers.removeWhere((s) => s.url == url);
    await prefs.setString(
        _key, jsonEncode(servers.map((s) => s.toJson()).toList()));
    if (prefs.getString(_lastServerKey) == url) {
      await prefs.remove(_lastServerKey);
    }
  }
}
