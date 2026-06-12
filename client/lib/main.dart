import 'package:flutter/material.dart';

import 'src/api/api_client.dart';
import 'src/app/app_state.dart';
import 'src/app/email_app.dart';

void main() {
  const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
  runApp(EmailApp(state: AppState(ApiClient(apiBaseUrl))));
}
