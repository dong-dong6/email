import 'package:flutter/material.dart';

import '../features/auth/login_screen.dart';
import '../features/mail/mail_home_screen.dart';
import '../theme/app_theme.dart';
import 'app_state.dart';

class EmailApp extends StatelessWidget {
  const EmailApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return MaterialApp(
          title: 'Self-hosted Mail',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: state.isAuthenticated
              ? MailHomeScreen(state: state)
              : LoginScreen(state: state),
        );
      },
    );
  }
}
