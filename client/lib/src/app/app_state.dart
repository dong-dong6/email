import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/mail_models.dart';

class AppState extends ChangeNotifier {
  AppState(this.api);

  final ApiClient api;

  bool isAuthenticated = false;
  bool isLoading = false;
  bool needsRegistration = false;
  String? error;
  MailboxSnapshot? snapshot;
  String? selectedFolderId;
  String? selectedMessageId;
  String query = '';

  List<MailAccount> get accounts => snapshot?.accounts ?? const [];
  List<MailFolder> get folders => snapshot?.folders ?? const [];
  List<MailMessage> get messages => snapshot?.messages ?? const [];
  bool get offlineMode => api.offlineMode;
  String get apiBaseUrl => api.baseUrl;

  MailAccount? get selectedAccount {
    final folder = selectedFolder;
    if (folder != null) {
      return accounts
          .where((account) => account.id == folder.accountId)
          .firstOrNull;
    }
    return accounts.firstOrNull;
  }

  List<MailFolder> get visibleFolders {
    final account = selectedAccount;
    if (account == null) {
      return folders;
    }
    return folders
        .where((folder) => folder.accountId == account.id)
        .toList(growable: false);
  }

  MailFolder? get selectedFolder {
    final id = selectedFolderId;
    if (id == null) {
      return folders.isEmpty ? null : folders.first;
    }
    return folders.where((folder) => folder.id == id).firstOrNull;
  }

  MailMessage? get selectedMessage {
    final id = selectedMessageId;
    if (id == null) {
      return visibleMessages.isEmpty ? null : visibleMessages.first;
    }
    return messages.where((message) => message.id == id).firstOrNull;
  }

  List<MailMessage> get visibleMessages {
    final folder = selectedFolder;
    final q = query.trim().toLowerCase();
    return messages.where((message) {
      final folderMatches = folder == null || message.folderId == folder.id;
      final queryMatches = q.isEmpty ||
          message.subject.toLowerCase().contains(q) ||
          message.snippet.toLowerCase().contains(q) ||
          message.from.label.toLowerCase().contains(q) ||
          message.bodyText.toLowerCase().contains(q);
      return folderMatches && queryMatches;
    }).toList();
  }

  Future<void> login(
    String apiBaseUrl,
    String email,
    String password,
    String totp,
  ) async {
    await _run(() async {
      api.setBaseUrl(apiBaseUrl);
      await api.login(email, password, totp: totp);
      isAuthenticated = true;
      needsRegistration = false;
      snapshot = await api.snapshot();
      selectedFolderId = folders.firstOrNull?.id;
      selectedMessageId = visibleMessages.firstOrNull?.id;
    });
  }

  Future<void> checkServer(String apiBaseUrl) async {
    await _run(() async {
      api.setBaseUrl(apiBaseUrl);
      needsRegistration = false;
      final hasUsers = await api.checkUsers();
      needsRegistration = !hasUsers;
    });
  }

  Future<void> register(
    String apiBaseUrl,
    String email,
    String password,
  ) async {
    await _run(() async {
      api.setBaseUrl(apiBaseUrl);
      await api.register(email, password);
      await api.login(email, password);
      isAuthenticated = true;
      needsRegistration = false;
      snapshot = await api.snapshot();
      selectedFolderId = folders.firstOrNull?.id;
      selectedMessageId = visibleMessages.firstOrNull?.id;
    });
  }

  Future<void> reload() async {
    await _run(() async {
      snapshot = await api.snapshot();
      if (selectedFolderId == null ||
          !folders.any((folder) => folder.id == selectedFolderId)) {
        selectedFolderId = folders.firstOrNull?.id;
      }
      selectedMessageId ??= visibleMessages.firstOrNull?.id;
    });
  }

  Future<void> addAccount({
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
    await _run(() async {
      final account = await api.createAccount(
        provider: provider,
        email: email,
        displayName: displayName.isEmpty ? email : displayName,
        username: username.isEmpty ? email : username,
        password: password,
        imapHost: imapHost,
        imapPort: imapPort,
        imapTls: imapTls,
        smtpHost: smtpHost,
        smtpPort: smtpPort,
        smtpTls: smtpTls,
      );
      if (api.offlineMode) {
        final current = snapshot ?? MailboxSnapshot.empty();
        final folders = [
          ...current.folders,
          MailFolder(
            id: 'fld_${account.id}_inbox',
            accountId: account.id,
            name: '收件箱',
            role: 'inbox',
            unreadCount: 0,
            totalCount: 0,
          ),
          MailFolder(
            id: 'fld_${account.id}_sent',
            accountId: account.id,
            name: '已发送',
            role: 'sent',
            unreadCount: 0,
            totalCount: 0,
          ),
        ];
        snapshot = MailboxSnapshot(
          accounts: [...current.accounts, account],
          folders: folders,
          messages: current.messages,
          settings: current.settings,
        );
      } else {
        snapshot = await api.snapshot();
      }
      selectedFolderId = folders
              .where((folder) =>
                  folder.accountId == account.id && folder.role == 'inbox')
              .firstOrNull
              ?.id ??
          folders
              .where((folder) => folder.accountId == account.id)
              .firstOrNull
              ?.id ??
          folders.firstOrNull?.id;
      selectedMessageId = visibleMessages.firstOrNull?.id;
    });
  }

  Future<OAuthStart?> startOAuth(String provider) async {
    OAuthStart? result;
    await _run(() async {
      result = await api.startOAuth(provider);
    });
    return result;
  }

  Future<OAuthStatus?> fetchOAuthStatus(String state) async {
    try {
      return await api.oauthStatus(state);
    } catch (_) {
      return null;
    }
  }

  Future<OAuthStatus> getOAuthStatus(String state) {
    return api.oauthStatus(state);
  }

  Future<void> updateSettings(MailSettings settings) async {
    await _run(() async {
      final updated = await api.updateSettings(settings);
      final current = snapshot ?? MailboxSnapshot.empty();
      snapshot = MailboxSnapshot(
        accounts: current.accounts,
        folders: current.folders,
        messages: current.messages,
        settings: updated,
      );
    });
  }

  void selectFolder(String id) {
    selectedFolderId = id;
    selectedMessageId = visibleMessages.firstOrNull?.id;
    notifyListeners();
  }

  void selectAccount(String id) {
    selectedFolderId = folders
            .where((folder) => folder.accountId == id && folder.role == 'inbox')
            .firstOrNull
            ?.id ??
        folders.where((folder) => folder.accountId == id).firstOrNull?.id ??
        selectedFolderId;
    selectedMessageId = visibleMessages.firstOrNull?.id;
    notifyListeners();
  }

  void selectMessage(String id) {
    selectedMessageId = id;
    _patchLocal(id, isRead: true);
    notifyListeners();
    api.patchMessage(id, isRead: true).catchError((_) {
      _patchLocal(id, isRead: false);
      notifyListeners();
    });
  }

  void setQuery(String value) {
    query = value;
    selectedMessageId = visibleMessages.firstOrNull?.id;
    notifyListeners();
  }

  Future<void> toggleStar(MailMessage message) async {
    final newValue = !message.isStarred;
    _patchLocal(message.id, isStarred: newValue);
    notifyListeners();
    try {
      await api.patchMessage(message.id, isStarred: newValue);
    } catch (_) {
      _patchLocal(message.id, isStarred: !newValue);
      notifyListeners();
    }
  }

  Future<void> moveMessage(MailMessage message, String folderId) async {
    _patchLocal(message.id, folderId: folderId);
    notifyListeners();
    try {
      await api.moveMessage(message.id, folderId);
      snapshot = await api.snapshot();
    } catch (_) {
      _patchLocal(message.id, folderId: message.folderId);
      notifyListeners();
    }
  }

  Future<void> deleteMessage(MailMessage message) async {
    final current = snapshot;
    if (current == null) return;
    snapshot = MailboxSnapshot(
      accounts: current.accounts,
      folders: current.folders,
      messages: current.messages.where((m) => m.id != message.id).toList(),
      settings: current.settings,
    );
    if (selectedMessageId == message.id) {
      selectedMessageId = visibleMessages.firstOrNull?.id;
    }
    notifyListeners();
    try {
      await api.deleteMessage(message.id);
    } catch (_) {
      snapshot = current;
      notifyListeners();
    }
  }

  Future<void> syncSelectedAccount() async {
    final selectedAccountId = selectedFolder?.accountId;
    final account = accounts
            .where((account) => account.id == selectedAccountId)
            .firstOrNull ??
        accounts.firstOrNull;
    if (account == null) {
      return;
    }
    await _run(() async {
      await api.syncAccount(account.id);
      snapshot = await api.snapshot();
    });
  }

  Future<void> sendMessage({
    required List<Address> to,
    List<Address> cc = const [],
    List<Address> bcc = const [],
    required String subject,
    required String body,
  }) async {
    final account = accounts.firstOrNull;
    if (account == null) {
      error = '请先添加邮箱账户';
      notifyListeners();
      return;
    }
    await _run(() async {
      await api.send(
        accountId: account.id,
        to: to,
        cc: cc,
        bcc: bcc,
        subject: subject,
        bodyText: body,
      );
      snapshot = await api.snapshot();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (err) {
      error = err.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void _patchLocal(String id,
      {bool? isRead, bool? isStarred, String? folderId}) {
    final current = snapshot;
    if (current == null) {
      return;
    }
    snapshot = MailboxSnapshot(
      accounts: current.accounts,
      folders: current.folders,
      messages: current.messages
          .map((message) => message.id == id
              ? message.copyWith(
                  isRead: isRead, isStarred: isStarred, folderId: folderId)
              : message)
          .toList(),
      settings: current.settings,
    );
  }
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
