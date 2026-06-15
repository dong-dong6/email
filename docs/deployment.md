# VPS 部署

1. 安装 Docker 和 Docker Compose。
2. 如果使用域名，把域名解析到 VPS；也可以先直接用 VPS IP 测试。
3. 启动：

```bash
docker compose up -d --build
```

4. 可选配置 `.env`：

- `API_HTTP_PORT` 改为你要暴露的端口，默认 `8080`。
- `CORS_ALLOWED_ORIGINS` 只在 Web 客户端跨域访问时需要调整。

默认启动为 Go 后端直接提供 HTTP：

```env
API_HTTP_PORT=8080
```

5. 健康检查：

```bash
curl http://你的VPS_IP:8080/healthz
```

6. 备份：

```bash
BACKUP_DIR=./backups scripts/backup.sh
```

客户端登录页的“服务地址”填写 Go 后端地址，不要加 `/api/v1`。OAuth 回调地址会基于这个服务地址生成，例如 `http://你的VPS_IP:8080/api/v1/oauth/gmail/callback`。

首次连接全新服务时，客户端会自动进入创建管理员账户流程。服务端会在数据卷中自动生成 `master.key` 作为加密主密钥；这个文件随 `mail-data` volume 保存，不要删除旧 volume 后继续期望读取旧加密数据。

## 重新部署

项目不保留旧部署兼容。服务结构变化后，直接清理旧容器、孤儿服务和旧 volume，再重新启动：

```bash
docker compose down --remove-orphans -v
docker compose up -d --build
```
