# 自托管跨平台邮箱客户端

这个仓库是一个从零开始的 monorepo：

- `backend/`：Go 后端，部署到 VPS，统一连接 Gmail、Outlook、IMAP/SMTP，并向客户端暴露 HTTP API。
- `client/`：Flutter 客户端，面向 Android、iOS、Windows、macOS、Linux、Web 的自适应邮箱界面。
- `docker-compose.yml`：Go API 与 PostgreSQL 的 VPS 部署配置。
- `docs/`：OpenAPI、架构说明和部署手册。

当前实现已经包含认证、账户/文件夹/邮件/草稿/发件/规则/设置 API、SSE 事件、加密 blob 存储、mock connector、IMAP 收信、SMTP 发信、Flutter 自适应 UI 和 HTTP 接入层。Gmail/Outlook 已改为官方 OAuth 授权入口，后续接入 Gmail API / Microsoft Graph token 交换和同步；其他邮箱继续使用通用 IMAP/SMTP。

## 本地运行

后端：

```bash
cd backend
go test ./...
go run ./cmd/api
```

客户端：

```bash
cd client
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
```

VPS 部署：

```bash
docker compose up -d --build
```

默认会把 Go 后端直接暴露在 `http://服务器IP:8080`，客户端登录页填写这个服务地址即可。需要改端口或公开地址时再复制 `.env.example` 为 `.env`。

## 添加真实邮箱

客户端点左侧“添加邮箱”：

- Gmail：邮箱类型选择 `Gmail 官方授权`，在客户端填写 Google OAuth Client ID 后生成授权链接。
- Outlook：邮箱类型选择 `Outlook 官方授权`，在客户端填写 Microsoft OAuth Client ID 后生成授权链接。
- 其他邮箱：邮箱类型选择 `其他邮箱 IMAP/SMTP`，填写邮箱服务商提供的 IMAP/SMTP 服务器、端口和应用专用密码。

通用 IMAP/SMTP 添加后后端会立即执行一次 INBOX 初始同步，之后可以点客户端同步按钮再次拉取最近邮件。发信走后端 `/api/v1/send`，客户端不会直连 SMTP。Gmail/Outlook 需要完成 OAuth token 交换和官方 API connector 后再同步。

## 首次启动

全新服务第一次打开客户端时，只需要填写服务地址。客户端会检测到后端还没有管理员用户，然后进入创建管理员账户流程。加密主密钥会在服务端数据卷中自动生成并保存为 `master.key`，不要删除或替换这个数据卷。
