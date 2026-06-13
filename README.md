# 自托管跨平台邮箱客户端

这个仓库是一个从零开始的 monorepo：

- `backend/`：Go 后端，部署到 VPS，统一连接 Gmail、Outlook、IMAP/SMTP，并向客户端暴露 HTTP API。
- `client/`：Flutter 客户端，面向 Android、iOS、Windows、macOS、Linux、Web 的自适应邮箱界面。
- `docker-compose.yml`：Go API 与 PostgreSQL 的 VPS 部署配置。
- `docs/`：OpenAPI、架构说明和部署手册。

当前实现是第一版可运行产品骨架：已经包含认证、账户/文件夹/邮件/草稿/发件/规则/设置 API、SSE 事件、加密 blob 存储、mock connector、Gmail/Outlook/IMAP connector 接口骨架、Flutter 自适应 UI 和 HTTP 接入层。真实 Gmail/Outlook/IMAP 凭证接入后，只需要在 connector 层补齐供应商 API 调用。

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

## 默认开发账号

开发环境默认：

- 邮箱：`owner@example.com`
- 密码：`change-me-now`

生产环境必须设置 `MASTER_KEY_BASE64`，并修改 owner 密码。
