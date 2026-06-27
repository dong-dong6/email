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
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient(this.snapshotData) : super('http://localhost:8080');

  final MailboxSnapshot snapshotData;
  String? sentAccountId;

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
  Future<MailboxSnapshot> snapshot() async => snapshotData;
}

MailboxSnapshot _snapshot() {
  final now = DateTime(2026, 6, 17, 9, 30);
  return MailboxSnapshot(
    accounts: const [
      MailAccount(
        id: 'acc_work',
        provider: 'imap',
        email: 'work@example.com',
        displayName: '工作邮箱',
        status: 'active',
      ),
      MailAccount(
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
        subject: 'Work',
        snippet: 'Work message',
        bodyText: 'Work body',
        bodyHtml: '',
        isRead: false,
        isStarred: false,
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
