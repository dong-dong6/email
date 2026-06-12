# Provider 实现路线

## Gmail

- 建立 Google Cloud OAuth client，授权 scope 覆盖读取、发送、草稿、标签。
- 授权回调后加密保存 refresh token。
- 首次同步使用 full sync，保存最近消息和最新 `historyId`。
- 后续同步使用 `history.list`，`historyId` 失效时退回 full sync。
- 配置 Pub/Sub push，webhook 收到事件后触发对应账号增量同步。

## Outlook

- 建立 Microsoft Entra app registration，使用 delegated mail scopes。
- 每个 folder 保存独立 delta link。
- change notification webhook 只作为触发器，实际变更以 delta query 为准。
- 定时续订 subscription；收到 lifecycle notification 后重建 subscription。

## IMAP/SMTP

- 保存 IMAP/SMTP host、port、TLS、安全策略和 app password。
- 首次同步按 UID 拉取文件夹和最近邮件。
- 支持 IMAP IDLE；断线后指数退避重连；轮询作为兜底。
- SMTP 发送前构建 MIME，保留 Message-ID、In-Reply-To、References。
