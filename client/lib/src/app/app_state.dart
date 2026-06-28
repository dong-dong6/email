import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/mail_models.dart';

enum MailMessageFilter { all, unread, starred }

class AppState extends ChangeNotifier {
  AppState(
    this.api, {
    this.syncPollAttempts = 60,
    this.syncPollDelay = const Duration(seconds: 1),
  });

  final ApiClient api;
  final int syncPollAttempts;
  final Duration syncPollDelay;

  bool isAuthenticated = false;
  bool isLoading = false;
  bool needsRegistration = false;
  String? error;
  MailboxSnapshot? snapshot;
  String? selectedFolderId;
  String? selectedMessageId;
  String query = '';
  MailMessageFilter messageFilter = MailMessageFilter.all;
  final Set<String> selectedMessageIds = <String>{};

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
    return visibleMessages.where((message) => message.id == id).firstOrNull;
  }

  List<MailMessage> get matchingMessages => _messagesMatchingFolderAndQuery;

  int get matchingUnreadCount =>
      matchingMessages.where((message) => !message.isRead).length;

  int get matchingStarredCount =>
      matchingMessages.where((message) => message.isStarred).length;

  List<MailMessage> get selectedMessages => messages
      .where((message) => selectedMessageIds.contains(message.id))
      .toList(growable: false);

  bool get allVisibleMessagesSelected =>
      visibleMessages.isNotEmpty &&
      visibleMessages
          .every((message) => selectedMessageIds.contains(message.id));

  bool get anyVisibleMessagesSelected =>
      visibleMessages.any((message) => selectedMessageIds.contains(message.id));

  List<MailMessage> get visibleMessages {
    final matches = _messagesMatchingFolderAndQuery;
    return switch (messageFilter) {
      MailMessageFilter.all => matches,
      MailMessageFilter.unread =>
        matches.where((message) => !message.isRead).toList(growable: false),
      MailMessageFilter.starred =>
        matches.where((message) => message.isStarred).toList(growable: false),
    };
  }

  List<MailMessage> get _messagesMatchingFolderAndQuery {
    final folder = selectedFolder;
    final q = query.trim().toLowerCase();
    return messages.where((message) {
      final folderMatches = folder == null || message.folderId == folder.id;
      final queryMatches = q.isEmpty ||
          message.subject.toLowerCase().contains(q) ||
          message.snippet.toLowerCase().contains(q) ||
          message.from.label.toLowerCase().contains(q) ||
          message.bodyText.toLowerCase().contains(q) ||
          message.to
              .any((address) => address.label.toLowerCase().contains(q)) ||
          message.attachments.any(
              (attachment) => attachment.fileName.toLowerCase().contains(q));
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
      _ensureSelectionInVisibleScope();
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
      _ensureSelectionInVisibleScope();
    });
  }

  Future<void> reload() async {
    await _run(() async {
      snapshot = await api.snapshot();
      _ensureSelectionInVisibleScope();
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
        await _refreshSnapshotUntilSyncSettled(account.id);
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
    selectedMessageIds.clear();
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
    selectedMessageIds.clear();
    selectedMessageId = visibleMessages.firstOrNull?.id;
    notifyListeners();
  }

  void selectMessage(String id) {
    selectedMessageId = id;
    final message = messages.where((message) => message.id == id).firstOrNull;
    if (message != null && !message.isRead) {
      _patchLocal(id, isRead: true);
    }
    notifyListeners();
    if (message != null && !message.isRead) {
      api.patchMessage(id, isRead: true).catchError((_) {
        _patchLocal(id, isRead: false);
        _ensureSelectionInVisibleScope();
        notifyListeners();
      });
    }
  }

  void setQuery(String value) {
    query = value;
    _ensureSelectionInVisibleScope();
    notifyListeners();
  }

  void setMessageFilter(MailMessageFilter filter) {
    messageFilter = filter;
    _ensureSelectionInVisibleScope();
    notifyListeners();
  }

  void toggleMessageSelection(String id) {
    if (selectedMessageIds.contains(id)) {
      selectedMessageIds.remove(id);
    } else {
      selectedMessageIds.add(id);
    }
    notifyListeners();
  }

  void setVisibleMessagesSelected(bool selected) {
    final ids = visibleMessages.map((message) => message.id);
    if (selected) {
      selectedMessageIds.addAll(ids);
    } else {
      selectedMessageIds.removeAll(ids);
    }
    notifyListeners();
  }

  void clearMessageSelection() {
    if (selectedMessageIds.isEmpty) {
      return;
    }
    selectedMessageIds.clear();
    notifyListeners();
  }

  Future<void> markMessageRead(MailMessage message, bool isRead) async {
    if (message.isRead == isRead) {
      return;
    }
    _patchLocal(message.id, isRead: isRead);
    _ensureSelectionInVisibleScope();
    notifyListeners();
    try {
      await api.patchMessage(message.id, isRead: isRead);
    } catch (_) {
      _patchLocal(message.id, isRead: message.isRead);
      _ensureSelectionInVisibleScope();
      notifyListeners();
    }
  }

  Future<void> toggleStar(MailMessage message) async {
    final newValue = !message.isStarred;
    _patchLocal(message.id, isStarred: newValue);
    _ensureSelectionInVisibleScope();
    notifyListeners();
    try {
      await api.patchMessage(message.id, isStarred: newValue);
    } catch (_) {
      _patchLocal(message.id, isStarred: !newValue);
      _ensureSelectionInVisibleScope();
      notifyListeners();
    }
  }

  Future<void> moveMessage(MailMessage message, String folderId) async {
    final previous = snapshot;
    _patchLocal(message.id, folderId: folderId);
    _ensureSelectionInVisibleScope();
    notifyListeners();
    try {
      await api.moveMessage(message.id, folderId);
      snapshot = await api.snapshot();
      _ensureSelectionInVisibleScope();
    } catch (_) {
      snapshot = previous;
      _ensureSelectionInVisibleScope();
      notifyListeners();
    }
  }

  Future<void> deleteMessage(MailMessage message) async {
    final current = snapshot;
    if (current == null) return;
    _removeMessagesLocal({message.id});
    selectedMessageIds.remove(message.id);
    _ensureSelectionInVisibleScope();
    notifyListeners();
    try {
      await api.deleteMessage(message.id);
    } catch (_) {
      snapshot = current;
      _ensureSelectionInVisibleScope();
      notifyListeners();
    }
  }

  Future<void> markSelectedRead(bool isRead) async {
    await _patchSelectedMessages(isRead: isRead);
  }

  Future<void> starSelected(bool isStarred) async {
    await _patchSelectedMessages(isStarred: isStarred);
  }

  Future<void> moveSelectedMessages(String folderId) async {
    final selected = selectedMessages;
    if (selected.isEmpty) {
      return;
    }
    final ids = selected.map((message) => message.id).toSet();
    await _run(() async {
      final previous = snapshot;
      _patchManyLocal(ids, folderId: folderId);
      selectedMessageIds.clear();
      _ensureSelectionInVisibleScope();
      notifyListeners();
      try {
        for (final id in ids) {
          await api.moveMessage(id, folderId);
        }
        snapshot = await api.snapshot();
        _ensureSelectionInVisibleScope();
      } catch (_) {
        snapshot = previous;
        _ensureSelectionInVisibleScope();
        rethrow;
      }
    });
  }

  Future<void> deleteSelectedMessages() async {
    final selected = selectedMessages;
    if (selected.isEmpty) {
      return;
    }
    final ids = selected.map((message) => message.id).toSet();
    await _run(() async {
      final previous = snapshot;
      _removeMessagesLocal(ids);
      selectedMessageIds.clear();
      _ensureSelectionInVisibleScope();
      notifyListeners();
      try {
        for (final id in ids) {
          await api.deleteMessage(id);
        }
      } catch (_) {
        snapshot = previous;
        _ensureSelectionInVisibleScope();
        rethrow;
      }
    });
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
      await _refreshSnapshotUntilSyncSettled(account.id);
    });
  }

  Future<void> sendMessage({
    required String accountId,
    required List<Address> to,
    List<Address> cc = const [],
    List<Address> bcc = const [],
    required String subject,
    required String body,
  }) async {
    final account =
        accounts.where((account) => account.id == accountId).firstOrNull;
    if (account == null) {
      error = '请选择可用的发件账号';
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

  Future<void> _refreshSnapshotUntilSyncSettled(String accountId) async {
    final attempts = syncPollAttempts < 1 ? 1 : syncPollAttempts;
    for (var attempt = 0; attempt < attempts; attempt++) {
      snapshot = await api.snapshot();
      _ensureSelectionInVisibleScope();
      final account =
          accounts.where((account) => account.id == accountId).firstOrNull;
      if (account == null || account.status != 'syncing') {
        return;
      }
      if (attempt < attempts - 1 && syncPollDelay > Duration.zero) {
        await Future<void>.delayed(syncPollDelay);
      }
    }
  }

  void _ensureSelectionInVisibleScope() {
    if (selectedFolderId == null ||
        !folders.any((folder) => folder.id == selectedFolderId)) {
      selectedFolderId = folders.firstOrNull?.id;
    }
    if (selectedMessageId == null ||
        !visibleMessages.any((message) => message.id == selectedMessageId)) {
      selectedMessageId = visibleMessages.firstOrNull?.id;
    }
    _pruneSelectedMessageIds();
  }

  void _pruneSelectedMessageIds() {
    if (selectedMessageIds.isEmpty) {
      return;
    }
    final visibleIds = visibleMessages.map((message) => message.id).toSet();
    selectedMessageIds.removeWhere((id) => !visibleIds.contains(id));
  }

  Future<void> _patchSelectedMessages({bool? isRead, bool? isStarred}) async {
    final selected = selectedMessages;
    if (selected.isEmpty) {
      return;
    }
    final ids = selected.map((message) => message.id).toSet();
    await _run(() async {
      final previous = snapshot;
      _patchManyLocal(ids, isRead: isRead, isStarred: isStarred);
      selectedMessageIds.clear();
      _ensureSelectionInVisibleScope();
      notifyListeners();
      try {
        for (final id in ids) {
          await api.patchMessage(id, isRead: isRead, isStarred: isStarred);
        }
      } catch (_) {
        snapshot = previous;
        _ensureSelectionInVisibleScope();
        rethrow;
      }
    });
  }

  void _patchLocal(String id,
      {bool? isRead, bool? isStarred, String? folderId}) {
    _patchManyLocal({id},
        isRead: isRead, isStarred: isStarred, folderId: folderId);
  }

  void _patchManyLocal(Set<String> ids,
      {bool? isRead, bool? isStarred, String? folderId}) {
    final current = snapshot;
    if (current == null) {
      return;
    }
    final nextMessages = current.messages
        .map((message) => ids.contains(message.id)
            ? message.copyWith(
                isRead: isRead, isStarred: isStarred, folderId: folderId)
            : message)
        .toList();
    snapshot = MailboxSnapshot(
      accounts: current.accounts,
      folders: _foldersWithMessageCounts(current.folders, nextMessages),
      messages: nextMessages,
      settings: current.settings,
    );
  }

  void _removeMessagesLocal(Set<String> ids) {
    final current = snapshot;
    if (current == null) {
      return;
    }
    final nextMessages = current.messages
        .where((message) => !ids.contains(message.id))
        .toList(growable: false);
    snapshot = MailboxSnapshot(
      accounts: current.accounts,
      folders: _foldersWithMessageCounts(current.folders, nextMessages),
      messages: nextMessages,
      settings: current.settings,
    );
  }

  List<MailFolder> _foldersWithMessageCounts(
    List<MailFolder> folders,
    List<MailMessage> messages,
  ) {
    final totalCounts = <String, int>{};
    final unreadCounts = <String, int>{};
    for (final message in messages) {
      totalCounts[message.folderId] = (totalCounts[message.folderId] ?? 0) + 1;
      if (!message.isRead) {
        unreadCounts[message.folderId] =
            (unreadCounts[message.folderId] ?? 0) + 1;
      }
    }
    return folders
        .map((folder) => folder.copyWith(
              totalCount: totalCounts[folder.id] ?? 0,
              unreadCount: unreadCounts[folder.id] ?? 0,
            ))
        .toList(growable: false);
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
