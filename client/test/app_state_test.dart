import 'package:flutter_test/flutter_test.dart';

import 'package:inbox_client/src/api/api_client.dart';
import 'package:inbox_client/src/app/app_state.dart';
import 'package:inbox_client/src/models/mail_models.dart';

void main() {
  test('sendMessage uses the requested account id', () async {
    final api = _RecordingApiClient(_snapshot());
    final state = AppState(api)
      ..isAuthenticated = true
      ..snapshot = _snapshot()
      ..selectedFolderId = 'fld_work_inbox';

    await state.sendMessage(
      accountId: 'acc_personal',
      to: const [Address(email: 'reader@example.com')],
      subject: 'Hello',
      body: 'Body',
    );

    expect(api.sentAccountId, 'acc_personal');
    expect(state.error, isNull);
  });

  test('sendMessage rejects an unknown sender account', () async {
    final api = _RecordingApiClient(_snapshot());
    final state = AppState(api)
      ..isAuthenticated = true
      ..snapshot = _snapshot();

    await state.sendMessage(
      accountId: 'missing',
      to: const [Address(email: 'reader@example.com')],
      subject: 'Hello',
      body: 'Body',
    );

    expect(api.sentAccountId, isNull);
    expect(state.error, '请选择可用的发件账号');
  });

  test('reload drops a selected message outside the visible folder', () async {
    final api = _RecordingApiClient(_snapshot());
    final state = AppState(api)
      ..isAuthenticated = true
      ..snapshot = _snapshot()
      ..selectedFolderId = 'fld_work_inbox'
      ..selectedMessageId = 'msg_personal';

    await state.reload();

    expect(state.selectedMessageId, 'msg_work');
    expect(state.selectedMessage?.id, 'msg_work');
  });

  test('syncSelectedAccount waits until backend sync settles', () async {
    final oldSnapshot = _snapshot(workStatus: 'syncing', workSubject: 'Old');
    final newSnapshot = _snapshot(workStatus: 'active', workSubject: 'New');
    final api = _RecordingApiClient(oldSnapshot)
      ..queuedSnapshots = [oldSnapshot, newSnapshot];
    final state = AppState(
      api,
      syncPollAttempts: 3,
      syncPollDelay: Duration.zero,
    )
      ..isAuthenticated = true
      ..snapshot = oldSnapshot
      ..selectedFolderId = 'fld_work_inbox'
      ..selectedMessageId = 'msg_work';

    await state.syncSelectedAccount();

    expect(api.syncedAccountId, 'acc_work');
    expect(state.error, isNull);
    expect(state.selectedMessage?.subject, 'New');
    expect(state.selectedAccount?.status, 'active');
  });

  test('message filter narrows visible messages without changing folder scope',
      () {
    final snapshot = _snapshot(workIsStarred: true);
    final state = AppState(_RecordingApiClient(snapshot))
      ..isAuthenticated = true
      ..snapshot = snapshot
      ..selectedFolderId = 'fld_work_inbox';

    state.setMessageFilter(MailMessageFilter.starred);

    expect(state.visibleMessages.map((message) => message.id), ['msg_work']);
    expect(state.matchingMessages.map((message) => message.id), ['msg_work']);
    expect(state.matchingStarredCount, 1);

    state.setMessageFilter(MailMessageFilter.unread);

    expect(state.visibleMessages.map((message) => message.id), ['msg_work']);
    expect(state.matchingUnreadCount, 1);
  });

  test('markSelectedRead patches backend and updates local folder counts',
      () async {
    final snapshot = _snapshot();
    final api = _RecordingApiClient(snapshot);
    final state = AppState(api)
      ..isAuthenticated = true
      ..snapshot = snapshot
      ..selectedFolderId = 'fld_work_inbox'
      ..selectedMessageId = 'msg_work';

    state.toggleMessageSelection('msg_work');
    await state.markSelectedRead(true);

    final message =
        state.messages.where((message) => message.id == 'msg_work').single;
    final folder =
        state.folders.where((folder) => folder.id == 'fld_work_inbox').single;

    expect(api.patchedRead, {'msg_work': true});
    expect(message.isRead, isTrue);
    expect(folder.unreadCount, 0);
    expect(state.selectedMessageIds, isEmpty);
    expect(state.error, isNull);
  });
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient(this.snapshotData) : super('http://localhost:8080');

  final MailboxSnapshot snapshotData;
  List<MailboxSnapshot> queuedSnapshots = [];
  String? sentAccountId;
  String? syncedAccountId;
  final Map<String, bool> patchedRead = {};
  final Map<String, bool> patchedStarred = {};

  @override
  Future<void> send({
    required String accountId,
    required List<Address> to,
    List<Address> cc = const [],
    List<Address> bcc = const [],
    required String subject,
    required String bodyText,
  }) async {
    sentAccountId = accountId;
  }

  @override
  Future<MailboxSnapshot> snapshot() async {
    if (queuedSnapshots.isNotEmpty) {
      return queuedSnapshots.removeAt(0);
    }
    return snapshotData;
  }

  @override
  Future<void> syncAccount(String accountId) async {
    syncedAccountId = accountId;
  }

  @override
  Future<void> patchMessage(String id, {bool? isRead, bool? isStarred}) async {
    if (isRead != null) {
      patchedRead[id] = isRead;
    }
    if (isStarred != null) {
      patchedStarred[id] = isStarred;
    }
  }
}

MailboxSnapshot _snapshot({
  String workStatus = 'active',
  String workSubject = 'Work',
  bool workIsRead = false,
  bool workIsStarred = false,
}) {
  final now = DateTime(2026, 6, 17, 9, 30);
  return MailboxSnapshot(
    accounts: [
      MailAccount(
        id: 'acc_work',
        provider: 'imap',
        email: 'work@example.com',
        displayName: '工作邮箱',
        status: workStatus,
      ),
      const MailAccount(
        id: 'acc_personal',
        provider: 'imap',
        email: 'me@example.com',
        displayName: '个人邮箱',
        status: 'active',
      ),
    ],
    folders: const [
      MailFolder(
        id: 'fld_work_inbox',
        accountId: 'acc_work',
        name: 'INBOX',
        role: 'inbox',
        unreadCount: 1,
        totalCount: 1,
      ),
      MailFolder(
        id: 'fld_personal_inbox',
        accountId: 'acc_personal',
        name: 'INBOX',
        role: 'inbox',
        unreadCount: 1,
        totalCount: 1,
      ),
    ],
    messages: [
      MailMessage(
        id: 'msg_work',
        accountId: 'acc_work',
        folderId: 'fld_work_inbox',
        threadId: 'thr_work',
        from: const Address(email: 'alice@example.com'),
        to: const [Address(email: 'work@example.com')],
        cc: const [],
        bcc: const [],
        subject: workSubject,
        snippet: 'Work message',
        bodyText: 'Work body',
        bodyHtml: '',
        isRead: workIsRead,
        isStarred: workIsStarred,
        labels: const ['inbox'],
        attachments: const [],
        receivedAt: now,
      ),
      MailMessage(
        id: 'msg_personal',
        accountId: 'acc_personal',
        folderId: 'fld_personal_inbox',
        threadId: 'thr_personal',
        from: const Address(email: 'bob@example.com'),
        to: const [Address(email: 'me@example.com')],
        cc: const [],
        bcc: const [],
        subject: 'Personal',
        snippet: 'Personal message',
        bodyText: 'Personal body',
        bodyHtml: '',
        isRead: false,
        isStarred: false,
        labels: const ['inbox'],
        attachments: const [],
        receivedAt: now,
      ),
    ],
    settings: MailboxSnapshot.empty().settings,
  );
}
