# VPS 部署

1. 安装 Docker 和 Docker Compose。
2. 如果使用域名，把域名解析到 VPS；也可以先直接用 VPS IP 测试。
3. 复制配置：

```bash
cp .env.example .env
```

4. 修改 `.env`：

- `PUBLIC_URL` 改为你的服务地址，例如 `http://你的VPS_IP:8080`。
- `MASTER_KEY_BASE64` 设置为 32 字节 base64 密钥。
- `OWNER_EMAIL`、`OWNER_PASSWORD` 改为自己的登录信息。
- `POSTGRES_PASSWORD` 改为强密码。
- Gmail/Outlook 账号当前在客户端用 IMAP/SMTP 与应用专用密码添加，不需要在 `.env` 填 OAuth 配置。

默认启动为 Go 后端直接提供 HTTP：

```env
HTTP_ADDR=:8080
API_HTTP_PORT=8080
```

5. 启动：

```bash
docker compose up -d --build
```

6. 健康检查：

```bash
curl http://你的VPS_IP:8080/healthz
```

7. 备份：

```bash
BACKUP_DIR=./backups scripts/backup.sh
```

客户端登录页的“服务地址”填写 `PUBLIC_URL` 对应的地址，不要加 `/api/v1`。

当前版本后端使用内存仓库保存账号和邮件缓存；PostgreSQL 表和部署服务已准备好，生产持久化接入应优先实现 `store.Postgres`。

## 重新部署

项目不保留旧部署兼容。服务结构变化后，直接清理旧容器、孤儿服务和旧 volume，再重新启动：

```bash
docker compose down --remove-orphans -v
docker compose up -d --build
```
