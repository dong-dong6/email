part of '../mail_home_screen.dart';

class _ComposeDialog extends StatefulWidget {
  const _ComposeDialog({required this.state, this.replyTo, this.forwardFrom});

  final AppState state;
  final MailMessage? replyTo;
  final MailMessage? forwardFrom;

  @override
  State<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<_ComposeDialog> {
  late final TextEditingController _to;
  late final TextEditingController _cc;
  late final TextEditingController _bcc;
  late final TextEditingController _subject;
  late final TextEditingController _body;
  bool _sending = false;
  bool _showCcBcc = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    final reply = widget.replyTo;
    final forward = widget.forwardFrom;
    _to = TextEditingController(text: reply == null ? '' : reply.from.email);
    _cc = TextEditingController();
    _bcc = TextEditingController();
    _subject = TextEditingController(
      text: reply != null
          ? 'Re: ${reply.subject}'
          : forward != null
              ? 'Fwd: ${forward.subject}'
              : '',
    );
    _body = TextEditingController(
      text: forward == null
          ? ''
          : '\n\n---------- Forwarded message ----------\n${forward.bodyText}',
    );
  }

  @override
  void dispose() {
    _to.dispose();
    _cc.dispose();
    _bcc.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final scheme = Theme.of(context).colorScheme;
    final account = widget.state.selectedAccount ?? widget.state.accounts.firstOrNull;
    return Dialog.fullscreen(
      child: ColoredBox(
        color: scheme.surface,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: width < 720 ? double.infinity : 820),
            child: Scaffold(
              appBar: AppBar(
                title: Text(widget.replyTo != null
                    ? '回复邮件'
                    : widget.forwardFrom != null
                        ? '转发邮件'
                        : '写信'),
                actions: [
                  IconButton(
                    tooltip: '关闭',
                    onPressed:
                        _sending ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(_MailDimens.radius),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          _IconSurface(
                            icon: Icons.send_outlined,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  account?.displayName ?? '未选择发件账号',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  account?.email ?? '请先添加邮箱账号',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _to,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            prefixIcon:
                                Icon(Icons.person_add_alt_1_rounded),
                            labelText: '收件人',
                            hintText: 'name@example.com, other@example.com',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: _showCcBcc ? '隐藏 Cc/Bcc' : '显示 Cc/Bcc',
                        onPressed:
                            () => setState(() => _showCcBcc = !_showCcBcc),
                        icon: Icon(_showCcBcc
                            ? Icons.expand_less_rounded
                            : Icons.more_horiz_rounded),
                      ),
                    ],
                  ),
                  if (_showCcBcc) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cc,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.people_alt_outlined),
                        labelText: '抄送 Cc',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bcc,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.visibility_off_outlined),
                        labelText: '密送 Bcc',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _subject,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.subject_rounded),
                      labelText: '主题',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _body,
                    minLines: 16,
                    maxLines: 28,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      alignLabelWithHint: true,
                      labelText: '正文',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      InputChip(
                        avatar: Icon(Icons.attach_file_rounded),
                        label: Text('附件'),
                      ),
                      InputChip(
                        avatar: Icon(Icons.image_outlined),
                        label: Text('内联图片'),
                      ),
                    ],
                  ),
                  ListenableBuilder(
                    listenable: widget.state,
                    builder: (context, _) {
                      final error = _localError ?? widget.state.error;
                      if (error != null) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _InlineError(text: error),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
              bottomNavigationBar: SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border(top: BorderSide(color: scheme.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '发件请求会先进入后端 outbox',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(_sending ? '发送中' : '发送'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _send() async {
    final recipients = _parseAddresses(_to.text);
    if (recipients.isEmpty) {
      setState(() => _localError = '请至少填写一个收件人');
      return;
    }
    setState(() {
      _sending = true;
      _localError = null;
    });
    await widget.state.sendMessage(
      to: recipients,
      cc: _parseAddresses(_cc.text),
      bcc: _parseAddresses(_bcc.text),
      subject: _subject.text.trim(),
      body: _body.text,
    );
    if (mounted) {
      if (widget.state.error == null) {
        Navigator.of(context).pop();
      } else {
        setState(() => _sending = false);
      }
    }
  }

  List<Address> _parseAddresses(String value) {
    return value
        .split(RegExp(r'[,;\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map((email) => Address(email: email))
        .toList(growable: false);
  }
}

