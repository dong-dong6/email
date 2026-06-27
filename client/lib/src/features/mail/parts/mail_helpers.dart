part of '../mail_home_screen.dart';

void _showComposer(BuildContext context, AppState state,
    {MailMessage? replyTo, MailMessage? forwardFrom}) {
  showDialog<void>(
    context: context,
    builder: (_) => _ComposeDialog(
        state: state, replyTo: replyTo, forwardFrom: forwardFrom),
  );
}

void _showSettings(BuildContext context, AppState state) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _SettingsSheet(state: state),
  );
}

void _showAddAccount(BuildContext context, AppState state) {
  showDialog<void>(
    context: context,
    builder: (_) => _AddAccountDialog(state: state),
  );
}

String _folderDisplayName(MailFolder folder) {
  switch (folder.role.toLowerCase()) {
    case 'inbox':
      return '收件箱';
    case 'sent':
      return '已发送';
    case 'drafts':
    case 'draft':
      return '草稿箱';
    case 'archive':
      return '归档';
    case 'trash':
    case 'deleted':
      return '已删除';
    case 'spam':
    case 'junk':
      return '垃圾邮件';
    case 'starred':
      return '星标邮件';
    default:
      return switch (folder.name.trim().toLowerCase()) {
        'inbox' => '收件箱',
        'sent' || 'sent mail' => '已发送',
        'draft' || 'drafts' => '草稿箱',
        'archive' || 'all mail' => '归档',
        'trash' || 'deleted items' => '已删除',
        'spam' || 'junk' || 'junk email' => '垃圾邮件',
        'starred' => '星标邮件',
        _ => folder.name,
      };
  }
}

IconData _folderIcon(String role, {bool selected = false}) {
  switch (role) {
    case 'inbox':
      return selected ? Icons.inbox_rounded : Icons.inbox_outlined;
    case 'sent':
      return selected ? Icons.send_rounded : Icons.send_outlined;
    case 'drafts':
      return selected ? Icons.drafts_rounded : Icons.drafts_outlined;
    case 'archive':
      return selected ? Icons.archive_rounded : Icons.archive_outlined;
    case 'trash':
      return selected ? Icons.delete_rounded : Icons.delete_outline_rounded;
    default:
      return selected ? Icons.folder_rounded : Icons.folder_outlined;
  }
}

String _shortTime(DateTime? value) {
  if (value == null) {
    return '';
  }
  final now = DateTime.now();
  if (now.difference(value).inDays == 0) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
  return '${value.month}/${value.day}';
}

String _longTime(DateTime? value) {
  if (value == null) {
    return '';
  }
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

String _initial(Address address) {
  final source = address.name.isNotEmpty ? address.name : address.email;
  if (source.isEmpty) {
    return '?';
  }
  return source.substring(0, 1).toUpperCase();
}

