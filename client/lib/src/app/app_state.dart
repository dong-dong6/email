import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/mail_models.dart';

class AppState extends ChangeNotifier {
  AppState(this.api);

  final ApiClient api;

  bool isAuthenticated = false;
  bool isLoading = false;
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
      snapshot = await api.snapshot();
      selectedFolderId = folders.firstOrNull?.id;
      selectedMessageId = visibleMessages.firstOrNull?.id;
    });
  }

  Future<void> reload() async {
    await _run(() async {
      snapshot = await api.snapshot();
      selectedFolderId ??= folders.firstOrNull?.id;
      selectedMessageId ??= visibleMessages.firstOrNull?.id;
    });
  }

  Future<void> addAccount({
    required String provider,
    required String email,
    required String displayName,
  }) async {
    await _run(() async {
      final account = await api.createAccount(
        provider: provider,
        email: email,
        displayName: displayName.isEmpty ? email : displayName,
      );
      if (api.offlineMode) {
        final current = snapshot ?? MailboxSnapshot.demo();
        final folders = [
          ...current.folders,
          MailFolder(
            id: 'fld_${account.id}_inbox',
            accountId: account.id,
            name: 'Inbox',
            role: 'inbox',
            unreadCount: 0,
            totalCount: 0,
          ),
          MailFolder(
            id: 'fld_${account.id}_sent',
            accountId: account.id,
            name: 'Sent',
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

  void selectFolder(String id) {
    selectedFolderId = id;
    selectedMessageId = visibleMessages.firstOrNull?.id;
    notifyListeners();
  }

  void selectMessage(String id) {
    selectedMessageId = id;
    _patchLocal(id, isRead: true);
    api.patchMessage(id, isRead: true);
    notifyListeners();
  }

  void setQuery(String value) {
    query = value;
    selectedMessageId = visibleMessages.firstOrNull?.id;
    notifyListeners();
  }

  Future<void> toggleStar(MailMessage message) async {
    _patchLocal(message.id, isStarred: !message.isStarred);
    notifyListeners();
    await api.patchMessage(message.id, isStarred: !message.isStarred);
  }

  Future<void> syncSelectedAccount() async {
    final account = accounts.firstOrNull;
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
    required String subject,
    required String body,
  }) async {
    final account = accounts.firstOrNull;
    if (account == null) {
      return;
    }
    await _run(() async {
      await api.send(
          accountId: account.id, to: to, subject: subject, bodyText: body);
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

  void _patchLocal(String id, {bool? isRead, bool? isStarred}) {
    final current = snapshot;
    if (current == null) {
      return;
    }
    snapshot = MailboxSnapshot(
      accounts: current.accounts,
      folders: current.folders,
      messages: current.messages
          .map((message) => message.id == id
              ? message.copyWith(isRead: isRead, isStarred: isStarred)
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
