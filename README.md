# 自托管跨平台邮箱客户端

这个仓库是一个从零开始的 monorepo：

- `backend/`：Go 后端，部署到 VPS，统一连接 Gmail、Outlook、IMAP/SMTP，并向客户端暴露 HTTP API。
- `client/`：Flutter 客户端，面向 Android、iOS、Windows、macOS、Linux、Web 的自适应邮箱界面。
- `docker-compose.yml`：Go API 与 PostgreSQL 的 VPS 部署配置。
- `docs/`：OpenAPI、架构说明和部署手册。

当前实现已经包含认证、账户/文件夹/邮件/草稿/发件/规则/设置 API、SSE 事件、加密 blob 存储、mock connector、IMAP 收信、SMTP 发信、Flutter 自适应 UI 和 HTTP 接入层。Gmail/Outlook 当前通过 IMAP/SMTP + 应用专用密码接入；后续可再替换为官方 OAuth API connector。

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
cp .env.example .env
# 修改 .env 中的域名、密钥、密码
docker compose up -d --build
```

默认会把 Go 后端直接暴露在 `http://服务器IP:8080`，客户端登录页填写这个服务地址即可。

## 添加真实邮箱

客户端点左侧“添加邮箱”：

- Gmail：邮箱类型选择 `Gmail`，用户名填完整 Gmail 地址，密码填 Google 应用专用密码。服务器默认 `imap.gmail.com:993`、`smtp.gmail.com:587`。
- Outlook：邮箱类型选择 `Outlook`，用户名填完整 Outlook 地址，密码填应用专用密码或允许 SMTP/IMAP 的账号密码。服务器默认 `outlook.office365.com:993`、`smtp.office365.com:587`。
- 其他邮箱：邮箱类型选择 `IMAP/SMTP`，填写邮箱服务商提供的 IMAP/SMTP 服务器和端口。

添加后后端会立即执行一次 INBOX 初始同步，之后可以点客户端同步按钮再次拉取最近邮件。发信走后端 `/api/v1/send`，客户端不会直连 SMTP。

## 默认开发账号

开发环境默认：

- 邮箱：`owner@example.com`
- 密码：`change-me-now`

生产环境必须设置 `MASTER_KEY_BASE64`，并修改 owner 密码。
