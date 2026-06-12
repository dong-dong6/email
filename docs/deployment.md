# VPS 部署

1. 准备域名解析到 VPS。
2. 安装 Docker 和 Docker Compose。
3. 复制配置：

```bash
cp .env.example .env
```

4. 修改 `.env`：

- `PUBLIC_URL` 改为你的 HTTPS 域名。
- `MASTER_KEY_BASE64` 设置为 32 字节 base64 密钥。
- `OWNER_EMAIL`、`OWNER_PASSWORD` 改为自己的登录信息。
- `POSTGRES_PASSWORD` 改为强密码。
- 按需填写 Gmail、Microsoft OAuth 配置。

5. 启动：

```bash
docker compose up -d --build
```

6. 健康检查：

```bash
curl https://你的域名/healthz
```

7. 备份：

```bash
BACKUP_DIR=./backups scripts/backup.sh
```

当前版本后端默认使用内存仓库演示数据；PostgreSQL 表和部署服务已准备好，生产持久化接入应优先实现 `store.Postgres`。
