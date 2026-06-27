import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../api/api_client.dart';
import '../../app/app_state.dart';
import '../../models/mail_models.dart';

part 'parts/layouts.dart';
part 'parts/navigation.dart';
part 'parts/message_list.dart';
part 'parts/message_detail.dart';
part 'parts/common_widgets.dart';
part 'parts/compose_dialog.dart';
part 'parts/account_dialog.dart';
part 'parts/settings_sheet.dart';
part 'parts/mail_helpers.dart';
part 'parts/mail_design.dart';
part 'parts/html_renderer.dart';

class MailHomeScreen extends StatelessWidget {
  const MailHomeScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 720;
        return Scaffold(
          body: SafeArea(
            child: isPhone
                ? _PhoneLayout(state: state)
                : constraints.maxWidth < 1080
                    ? _TabletLayout(state: state)
                    : _DesktopLayout(state: state),
          ),
          floatingActionButton: isPhone
              ? FloatingActionButton.extended(
                  onPressed: () => _showComposer(context, state),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('写信'),
                )
              : null,
        );
      },
    );
  }
}
