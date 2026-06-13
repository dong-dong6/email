# 架构说明

## 进程与模块

后端当前是一个 Go 单体服务，内部按职责拆分：

- `cmd/api`：启动 HTTP API、SSE、outbox worker。
- `internal/httpapi`：REST API、认证中间件、CORS、SSE、webhook 入口。
- `internal/auth`：owner 登录、HMAC access/refresh token、refresh token rotation、TOTP 校验、PBKDF2 密码哈希。
- `internal/blob`：AES-GCM 加密 blob 存储，用于正文和附件。
- `internal/mail`：统一 connector 接口、mock connector、Gmail/Outlook/IMAP connector 占位、发件队列 worker。
- `internal/store`：当前为内存仓库，保留与 PostgreSQL 迁移一致的数据模型。

## 数据流

客户端启动后调用 `/api/v1/auth/login` 获取 access token，再调用 `/api/v1/snapshot` 拉取账号、文件夹、邮件、草稿、规则和设置。后续所有读写都通过 `/api/v1/*`，浏览器端可用 `/api/v1/events?token=...` 监听 SSE。

发件流程为 `/api/v1/send` 写入 outbox，后台 worker 根据账号 provider 调用 connector。mock connector 会立即写入 Sent 文件夹；Gmail、Outlook、IMAP connector 已经挂在 registry 中，下一步补真实 API 调用即可。

## Provider 接入边界

统一接口是 `mail.Connector`：

- `AuthorizeURL`：生成 OAuth 或账号授权入口。
- `Sync`：执行首次同步、增量同步或 webhook 触发同步。
- `Send`：发送 MIME 邮件并返回 provider message id。

Gmail 应实现 OAuth、`messages.list/get/send`、drafts、labels、historyId 增量同步和 Pub/Sub webhook。Outlook 应实现 Microsoft Graph OAuth、messages/delta、subscriptions、sendMail、attachments。IMAP/SMTP 应实现邮箱配置验证、IMAP IDLE、轮询兜底和 SMTP 发件。

## 持久化计划

`backend/migrations/001_init.sql` 已定义 PostgreSQL 表结构。当前代码使用内存仓库便于无数据库开发和 UI 验证；切换生产仓库时保持 API 和 model 不变，新增 `store.Postgres` 并在启动时根据 `DATABASE_URL` 选择即可。

## 安全默认值

生产环境必须设置 `MASTER_KEY_BASE64`。远程图片默认不加载，附件通过 blob id 读取，blob 使用文件名作为 AES-GCM additional data，避免路径穿越和密文替换。CORS 只允许 `.env` 中配置的 origin。

Go 后端直接对外提供 HTTP API，客户端通过登录页配置的服务地址访问。
