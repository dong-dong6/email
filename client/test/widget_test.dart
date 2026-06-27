import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inbox_client/src/api/api_client.dart';
import 'package:inbox_client/src/app/app_state.dart';
import 'package:inbox_client/src/app/email_app.dart';
import 'package:inbox_client/src/models/mail_models.dart';

void main() {
  testWidgets('shows login screen', (tester) async {
    await tester.pumpWidget(
        EmailApp(state: AppState(ApiClient('http://localhost:8080'))));
    expect(find.text('Self-hosted Mail'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);
  });

  testWidgets('shows desktop mail workspace', (tester) async {
    await _setSurface(tester, const Size(1280, 800));
    final state = _mailState();

    await tester.pumpWidget(EmailApp(state: state));

    expect(find.text('邮箱工作台'), findsOneWidget);
    expect(find.text('收件箱'), findsWidgets);
    expect(find.text('设计评审'), findsWidgets);
    expect(find.text('写信'), findsOneWidget);
  });

  testWidgets('compose exposes cc and bcc fields', (tester) async {
    await _setSurface(tester, const Size(1280, 800));
    final state = _mailState();

    await tester.pumpWidget(EmailApp(state: state));
    await tester.tap(find.text('写信').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();

    expect(find.text('抄送 Cc'), findsOneWidget);
    expect(find.text('密送 Bcc'), findsOneWidget);
  });

  testWidgets('renders html mail without image and tracking noise',
      (tester) async {
    await _setSurface(tester, const Size(1280, 800));
    const trackingUrl =
        'https://click.redditmail.com/CLO/https:%2F%2Fwww.reddit.com%2Fr%2FOpenAI%2Fcomments%2Fabc';
    final state = _mailState(
      bodyHtml: '''
<table role="presentation">
  <tr><td><img src="https://example.com/pixel.png" alt="tracking"></td></tr>
  <tr><td>请查看 <a href="https://example.com/terms">服务条款</a></td></tr>
  <tr><td><a href="$trackingUrl">$trackingUrl</a></td></tr>
</table>
''',
    );

    await tester.pumpWidget(EmailApp(state: state));

    expect(find.textContaining('服务条款', findRichText: true), findsOneWidget);
    expect(find.textContaining('[图片]', findRichText: true), findsNothing);
    expect(
      find.textContaining('click.redditmail.com', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('keeps presentation table cells on the same row', (tester) async {
    await _setSurface(tester, const Size(1280, 800));
    final state = _mailState(
      bodyHtml: '''
<table role="presentation" width="600">
  <tr>
    <td align="center"><strong>208</strong></td>
    <td align="center"><strong>10</strong></td>
    <td align="center"><strong>1100</strong></td>
  </tr>
</table>
''',
    );

    await tester.pumpWidget(EmailApp(state: state));

    final firstTop = tester.getTopLeft(find.text('208', findRichText: true)).dy;
    final secondTop = tester.getTopLeft(find.text('10', findRichText: true)).dy;
    final thirdTop =
        tester.getTopLeft(find.text('1100', findRichText: true)).dy;
    expect((firstTop - secondTop).abs(), lessThan(2));
    expect((firstTop - thirdTop).abs(), lessThan(2));
  });
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

AppState _mailState({String bodyHtml = '', String bodyText = '请看新的工作台布局。'}) {
  final now = DateTime(2026, 6, 17, 9, 30);
  final state = AppState(ApiClient('http://localhost:8080'))
    ..isAuthenticated = true
    ..selectedFolderId = 'fld_inbox'
    ..selectedMessageId = 'msg_1'
    ..snapshot = MailboxSnapshot(
      accounts: const [
        MailAccount(
          id: 'acc_1',
          provider: 'imap',
          email: 'me@example.com',
          displayName: '工作邮箱',
          status: 'active',
        ),
      ],
      folders: const [
        MailFolder(
          id: 'fld_inbox',
          accountId: 'acc_1',
          name: 'INBOX',
          role: 'inbox',
          unreadCount: 1,
          totalCount: 1,
        ),
        MailFolder(
          id: 'fld_sent',
          accountId: 'acc_1',
          name: 'Sent',
          role: 'sent',
          unreadCount: 0,
          totalCount: 0,
        ),
      ],
      messages: [
        MailMessage(
          id: 'msg_1',
          accountId: 'acc_1',
          folderId: 'fld_inbox',
          threadId: 'thr_1',
          from: const Address(name: 'Alice', email: 'alice@example.com'),
          to: const [Address(email: 'me@example.com')],
          cc: const [Address(email: 'design@example.com')],
          bcc: const [Address(email: 'secret@example.com')],
          subject: '设计评审',
          snippet: '请看新的工作台布局。',
          bodyText: bodyText,
          bodyHtml: bodyHtml,
          isRead: false,
          isStarred: true,
          labels: const ['inbox'],
          attachments: const [
            MailAttachment(
              id: 'att_1',
              fileName: 'brief.pdf',
              contentType: 'application/pdf',
              size: 1024,
            ),
          ],
          receivedAt: now,
        ),
      ],
      settings: MailboxSnapshot.empty().settings,
    );
  return state;
}
