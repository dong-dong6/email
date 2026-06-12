import 'package:flutter_test/flutter_test.dart';

import 'package:inbox_client/src/api/api_client.dart';
import 'package:inbox_client/src/app/app_state.dart';
import 'package:inbox_client/src/app/email_app.dart';

void main() {
  testWidgets('shows login screen', (tester) async {
    await tester.pumpWidget(
        EmailApp(state: AppState(ApiClient('http://localhost:8080'))));
    expect(find.text('Self-hosted Mail'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
}
