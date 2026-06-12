# Windows 客户端打包与连接

## 打包

```bash
cd client
flutter build windows --release
```

输出目录：

```text
client/build/windows/x64/runner/Release
```

运行时需要保留整个 `Release` 目录，不能只拷贝 `inbox_client.exe`，因为 Flutter Windows 应用还需要同目录下的 `flutter_windows.dll`、`data/` 和 native assets。

## 连接远程 Go 服务

在登录页的“服务地址”填写 Go 后端的 origin：

```text
https://mail.example.com
```

或者临时测试：

```text
http://你的VPS_IP:8080
```

不要填写 `/api/v1`，客户端会自动请求：

```text
https://mail.example.com/api/v1/auth/login
https://mail.example.com/api/v1/snapshot
```

生产环境推荐通过 Caddy 暴露 HTTPS，并在 `.env` 中设置 `PUBLIC_URL` 与 `CORS_ALLOWED_ORIGINS`。
