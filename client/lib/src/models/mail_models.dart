class Address {
  const Address({this.name = '', required this.email});

  final String name;
  final String email;

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'email': email};

  String get label => name.isEmpty ? email : '$name <$email>';
}

class MailAccount {
  const MailAccount({
    required this.id,
    required this.provider,
    required this.email,
    required this.displayName,
    required this.status,
    this.lastError = '',
  });

  final String id;
  final String provider;
  final String email;
  final String displayName;
  final String status;
  final String lastError;

  factory MailAccount.fromJson(Map<String, dynamic> json) {
    return MailAccount(
      id: json['id'] as String,
      provider: json['provider'] as String? ?? 'mock',
      email: json['email'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      lastError: json['last_error'] as String? ?? '',
    );
  }
}

class MailFolder {
  const MailFolder({
    required this.id,
    required this.accountId,
    required this.name,
    required this.role,
    required this.unreadCount,
    required this.totalCount,
  });

  final String id;
  final String accountId;
  final String name;
  final String role;
  final int unreadCount;
  final int totalCount;

  factory MailFolder.fromJson(Map<String, dynamic> json) {
    return MailFolder(
      id: json['id'] as String,
      accountId: json['account_id'] as String,
      name: json['name'] as String? ?? 'Folder',
      role: json['role'] as String? ?? 'folder',
      unreadCount: json['unread_count'] as int? ?? 0,
      totalCount: json['total_count'] as int? ?? 0,
    );
  }
}

class MailAttachment {
  const MailAttachment({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.size,
  });

  final String id;
  final String fileName;
  final String contentType;
  final int size;

  factory MailAttachment.fromJson(Map<String, dynamic> json) {
    return MailAttachment(
      id: json['id'] as String? ?? '',
      fileName: json['file_name'] as String? ?? 'attachment',
      contentType:
          json['content_type'] as String? ?? 'application/octet-stream',
      size: json['size'] as int? ?? 0,
    );
  }
}

class MailMessage {
  const MailMessage({
    required this.id,
    required this.accountId,
    required this.folderId,
    required this.threadId,
    required this.from,
    required this.to,
    required this.subject,
    required this.snippet,
    required this.bodyText,
    required this.bodyHtml,
    required this.isRead,
    required this.isStarred,
    required this.labels,
    required this.attachments,
    this.receivedAt,
    this.sentAt,
  });

  final String id;
  final String accountId;
  final String folderId;
  final String threadId;
  final Address from;
  final List<Address> to;
  final String subject;
  final String snippet;
  final String bodyText;
  final String bodyHtml;
  final bool isRead;
  final bool isStarred;
  final List<String> labels;
  final List<MailAttachment> attachments;
  final DateTime? receivedAt;
  final DateTime? sentAt;

  factory MailMessage.fromJson(Map<String, dynamic> json) {
    return MailMessage(
      id: json['id'] as String,
      accountId: json['account_id'] as String,
      folderId: json['folder_id'] as String,
      threadId: json['thread_id'] as String? ?? '',
      from: Address.fromJson((json['from'] as Map).cast<String, dynamic>()),
      to: ((json['to'] as List?) ?? const [])
          .map(
              (item) => Address.fromJson((item as Map).cast<String, dynamic>()))
          .toList(),
      subject: json['subject'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      bodyText: json['body_text'] as String? ?? '',
      bodyHtml: json['body_html'] as String? ?? '',
      isRead: json['is_read'] as bool? ?? false,
      isStarred: json['is_starred'] as bool? ?? false,
      labels: ((json['labels'] as List?) ?? const []).cast<String>(),
      attachments: ((json['attachments'] as List?) ?? const [])
          .map((item) =>
              MailAttachment.fromJson((item as Map).cast<String, dynamic>()))
          .toList(),
      receivedAt: _date(json['received_at']),
      sentAt: _date(json['sent_at']),
    );
  }

  MailMessage copyWith({bool? isRead, bool? isStarred, String? folderId}) {
    return MailMessage(
      id: id,
      accountId: accountId,
      folderId: folderId ?? this.folderId,
      threadId: threadId,
      from: from,
      to: to,
      subject: subject,
      snippet: snippet,
      bodyText: bodyText,
      bodyHtml: bodyHtml,
      isRead: isRead ?? this.isRead,
      isStarred: isStarred ?? this.isStarred,
      labels: labels,
      attachments: attachments,
      receivedAt: receivedAt,
      sentAt: sentAt,
    );
  }

  DateTime? get displayTime => receivedAt ?? sentAt;
}

class MailDraft {
  const MailDraft({
    required this.id,
    required this.accountId,
    required this.subject,
    required this.body,
  });

  final String id;
  final String accountId;
  final String subject;
  final String body;
}

class MailSettings {
  const MailSettings({
    required this.remoteImagesDefault,
    required this.density,
    required this.signatureHtml,
  });

  final bool remoteImagesDefault;
  final String density;
  final String signatureHtml;

  factory MailSettings.fromJson(Map<String, dynamic> json) {
    return MailSettings(
      remoteImagesDefault: json['remote_images_default'] as bool? ?? false,
      density: json['density'] as String? ?? 'comfortable',
      signatureHtml: json['signature_html'] as String? ?? '',
    );
  }
}

class MailboxSnapshot {
  const MailboxSnapshot({
    required this.accounts,
    required this.folders,
    required this.messages,
    required this.settings,
  });

  final List<MailAccount> accounts;
  final List<MailFolder> folders;
  final List<MailMessage> messages;
  final MailSettings settings;

  factory MailboxSnapshot.fromJson(Map<String, dynamic> json) {
    return MailboxSnapshot(
      accounts: ((json['accounts'] as List?) ?? const [])
          .map((item) =>
              MailAccount.fromJson((item as Map).cast<String, dynamic>()))
          .toList(),
      folders: ((json['folders'] as List?) ?? const [])
          .map((item) =>
              MailFolder.fromJson((item as Map).cast<String, dynamic>()))
          .toList(),
      messages: ((json['messages'] as List?) ?? const [])
          .map((item) =>
              MailMessage.fromJson((item as Map).cast<String, dynamic>()))
          .toList(),
      settings: MailSettings.fromJson(
        ((json['settings'] as Map?) ?? const {}).cast<String, dynamic>(),
      ),
    );
  }

  factory MailboxSnapshot.demo() {
    final now = DateTime.now();
    const account = MailAccount(
      id: 'acc_demo',
      provider: 'mock',
      email: 'owner@example.com',
      displayName: 'Personal Mail',
      status: 'active',
    );
    const inbox = MailFolder(
      id: 'fld_inbox',
      accountId: 'acc_demo',
      name: 'Inbox',
      role: 'inbox',
      unreadCount: 2,
      totalCount: 2,
    );
    const sent = MailFolder(
      id: 'fld_sent',
      accountId: 'acc_demo',
      name: 'Sent',
      role: 'sent',
      unreadCount: 0,
      totalCount: 1,
    );
    return MailboxSnapshot(
      accounts: const [account],
      folders: const [
        inbox,
        sent,
        MailFolder(
            id: 'fld_drafts',
            accountId: 'acc_demo',
            name: 'Drafts',
            role: 'drafts',
            unreadCount: 0,
            totalCount: 0),
        MailFolder(
            id: 'fld_archive',
            accountId: 'acc_demo',
            name: 'Archive',
            role: 'archive',
            unreadCount: 0,
            totalCount: 0),
      ],
      messages: [
        MailMessage(
          id: 'msg_welcome',
          accountId: account.id,
          folderId: inbox.id,
          threadId: 'thr_welcome',
          from:
              const Address(name: 'Email System', email: 'system@example.com'),
          to: const [Address(name: 'Owner', email: 'owner@example.com')],
          subject: '欢迎使用自托管邮箱',
          snippet: '后端 API、SSE、草稿、发件队列和自适应客户端已经准备好。',
          bodyText: '欢迎使用自托管邮箱。当前客户端会优先连接后端；连接失败时进入离线演示模式。',
          bodyHtml: '',
          isRead: false,
          isStarred: true,
          labels: const ['inbox'],
          attachments: const [],
          receivedAt: now.subtract(const Duration(hours: 2)),
        ),
        MailMessage(
          id: 'msg_ui',
          accountId: account.id,
          folderId: inbox.id,
          threadId: 'thr_ui',
          from:
              const Address(name: 'Product Notes', email: 'notes@example.com'),
          to: const [Address(email: 'owner@example.com')],
          subject: '多端布局策略',
          snippet: '手机单栏、平板双栏、桌面三栏，键鼠和触控都能用。',
          bodyText: 'Flutter 客户端使用 Material 3、自适应断点、简洁邮件列表、阅读面板和写信弹窗。',
          bodyHtml: '',
          isRead: false,
          isStarred: false,
          labels: const ['inbox'],
          attachments: const [],
          receivedAt: now.subtract(const Duration(minutes: 24)),
        ),
      ],
      settings: const MailSettings(
        remoteImagesDefault: false,
        density: 'comfortable',
        signatureHtml: '<p>Sent from self-hosted mail.</p>',
      ),
    );
  }
}

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toLocal();
}
