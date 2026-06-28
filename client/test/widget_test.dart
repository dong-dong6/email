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

  testWidgets('labels mobile folders with account names', (tester) async {
    await _setSurface(tester, const Size(390, 800));
    final state = _mailState(includeSecondAccount: true);

    await tester.pumpWidget(EmailApp(state: state));
    await tester.tap(find.byTooltip('文件夹'));
    await tester.pumpAndSettle();

    expect(find.text('工作邮箱 / 收件箱 1'), findsOneWidget);
    expect(find.text('个人邮箱 / 收件箱'), findsOneWidget);
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

  testWidgets('does not expose unsupported attachment actions', (tester) async {
    await _setSurface(tester, const Size(1280, 800));
    final state = _mailState();

    await tester.pumpWidget(EmailApp(state: state));
    expect(find.text('brief.pdf'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);

    await tester.tap(find.text('写信').first);
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNothing);
    expect(find.text('内联图片'), findsNothing);
  });

  testWidgets('clears search field and query together', (tester) async {
    await _setSurface(tester, const Size(1280, 800));
    final state = _mailState();

    await tester.pumpWidget(EmailApp(state: state));
    await tester.enterText(find.byType(SearchBar), 'Alice');
    await tester.pumpAndSettle();

    expect(state.query, 'Alice');

    await tester.tap(find.byTooltip('清除'));
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(SearchBar),
        matching: find.byType(EditableText),
      ),
    );
    expect(state.query, '');
    expect(editable.controller.text, '');
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

  testWidgets('renders quote, preformatted text, and blocked image notice',
      (tester) async {
    await _setSurface(tester, const Size(1280, 800));
    final state = _mailState(
      bodyHtml: '''
<p>下面是日志和引用。</p>
<blockquote><p>上一封邮件里的重点。</p></blockquote>
<pre>first line
  indented value</pre>
<hr>
<img src="https://example.com/chart.png" alt="Product chart">
<img width="1" height="1" src="https://example.com/pixel.png" alt="tracking pixel">
''',
    );

    await tester.pumpWidget(EmailApp(state: state));

    expect(find.text('已阻止 1 张远程图片'), findsOneWidget);
    expect(find.textContaining('Product chart'), findsOneWidget);
    expect(
      find.textContaining('上一封邮件里的重点', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('first line', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('tracking pixel'), findsNothing);
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

AppState _mailState({
  String bodyHtml = '',
  String bodyText = '请看新的工作台布局。',
  bool includeSecondAccount = false,
}) {
  final now = DateTime(2026, 6, 17, 9, 30);
  final state = AppState(ApiClient('http://localhost:8080'))
    ..isAuthenticated = true
    ..selectedFolderId = 'fld_inbox'
    ..selectedMessageId = 'msg_1'
    ..snapshot = MailboxSnapshot(
      accounts: [
        const MailAccount(
          id: 'acc_1',
          provider: 'imap',
          email: 'me@example.com',
          displayName: '工作邮箱',
          status: 'active',
        ),
        if (includeSecondAccount)
          const MailAccount(
            id: 'acc_2',
            provider: 'imap',
            email: 'home@example.com',
            displayName: '个人邮箱',
            status: 'active',
          ),
      ],
      folders: [
        const MailFolder(
          id: 'fld_inbox',
          accountId: 'acc_1',
          name: 'INBOX',
          role: 'inbox',
          unreadCount: 1,
          totalCount: 1,
        ),
        const MailFolder(
          id: 'fld_sent',
          accountId: 'acc_1',
          name: 'Sent',
          role: 'sent',
          unreadCount: 0,
          totalCount: 0,
        ),
        if (includeSecondAccount)
          const MailFolder(
            id: 'fld_personal_inbox',
            accountId: 'acc_2',
            name: 'INBOX',
            role: 'inbox',
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
