# 逐层验证与常见误判

> SKILL.md 的补充参考。配置后按本文件逐层验证，最后验业务内容。

## 一、逐层验证

### L3（最内层）— 从服务器反打 L3 的 WAN 口

```bash
ssh <server-alias> "timeout 8 bash -c '</dev/tcp/<L3_WAN_IP>/<外部端口>'" && echo OK || echo FAIL
```

### L2 — 从服务器反打 L2 的 WAN 口

```bash
ssh <server-alias> "timeout 8 bash -c '</dev/tcp/<L2_WAN_IP>/<外部端口>'" && echo OK || echo FAIL
```

> **注意**：服务器与某层 WAN 口可能**不同网段**（多层路由的 LAN 段会重叠），此时从服务器打上一层的 WAN 地址天然不可达，测出来是超时，但规则本身没问题。遇到这种"测不通但外网能通"不要误判，先用公网侧验证。

### 公网侧（Windows）

```powershell
foreach ($p in 10080,18081,18083,18084) {
  $r = Test-NetConnection -ComputerName <公网IP> -Port $p -InformationLevel Quiet -WarningAction SilentlyContinue
  Write-Output "  $p = $r"
}
```

## 二、业务内容验证（必做）

端口通 ≠ 服务对。必须看真实响应。

```powershell
# HTTP
curl.exe -s -m 12 http://<公网IP>:<端口>/ | Select-String -Pattern "<title>[^<]*</title>"

# HTTPS（自签或高端口）
curl.exe -sk -m 12 https://<域名>:<端口>/ | Select-String -Pattern "<title>[^<]*</title>"

# 只看状态码与体积
curl.exe -sk -o NUL -w "HTTP=%{http_code} SIZE=%{size_download}`n" https://<域名>:<端口>/

# 接口也要单独验（首页 200 不代表接口 200）
curl.exe -sk -o NUL -w "API=%{http_code}`n" https://<域名>:<端口>/<健康检查路径>
```

服务端同步看日志，确认请求真的落到后端：

```bash
ssh <server-alias> "tail -20 /www/wwwlogs/<站点>.log"
```

## 三、误判对照

### "外网 502" —— 是谁的 502？

| 判据 | 结论 |
|---|---|
| 服务器 `error.log` **有** `connect() failed (111: Connection refused)` | 你自己的 nginx 返的 → 后端挂了/重启中 → 查后端进程 |
| 服务器 `error.log` **无任何记录** | **不是**你的服务器返的 → 中间网关 / 运营商 WAF 返的 → 核对端口可达性 |
| 响应头 `Server: nginx/1.x` 但服务器无日志 | 前面还有一层代理/网关 |

后端重启期的瞬时 502 特征：`connect() failed (111: Connection refused) while connecting to upstream`。

### "外网超时" vs "连接被拒绝"

| 现象 | 含义 |
|---|---|
| **超时**（无响应） | 包被丢弃：某层缺规则，或运营商封了该端口号 |
| **连接被拒绝 RST** | 包到了但目标端口没进程 → 服务没起 |

### "80 不通但 10080 通"

不是矛盾。运营商封的是**目的端口号 80**（BRAS 层丢弃），换成任何高位端口都不在封禁列表。同理 443。

### "HTTP 突然打不开"

三个常见原因：

1. **开启了「强制 HTTPS」** → 301 到默认 443 → 443 被封 → 死循环。
2. **配了 `error_page 497 https://$host$request_uri;`** → 497 表示明文打到 SSL 端口，该行 301 到不带端口的 443。
3. **同端口同时配了 `listen <port>;` 和 `listen <port> ssl;`** → nginx 报错或行为不确定。

修法：关掉「强制 HTTPS」；删掉 `error_page 497`；同端口只保留 `ssl` 那一条。

### "HTTPS 握手失败 ERR_SSL_PROTOCOL_ERROR"

该端口的 nginx 没开 `ssl`。纯 `listen <port>;` 只能接受明文，浏览器发 TLS 握手会被当明文解析失败。

### "首页能开但接口 404"

站点 vhost 的 `#REWRITE-START` 段 include 被注释掉了，或路径写错。检查：

```bash
grep -n 'rewrite/' /www/server/panel/vhost/nginx/<站点>.conf
ls /www/server/panel/vhost/rewrite/
```

正确路径是 `/www/server/panel/vhost/rewrite/<站点>.conf`（**没有中间的 `nginx/`**）。

### "提交规则后表格出现 `--` 空行"

下拉框（生效接口 / 协议）只改了隐藏 input 的 value。必须真实点选选项，并以校验错误提示消失为通过判据。

### "证书申请一直失败"

入站 80 不可达时，HTTP-01（文件验证）必然失败。改用 DNS-01 验证：

- 面板选 DNS 验证 + 填 DNS 服务商 API 凭据（自动）；
- 或选手动解析，在 DNS 服务商加 `_acme-challenge.<子域>` 的 TXT 记录。

通配符证书（如 `*.example.com`）**只能用 DNS-01**。

### "续期后配置被改回"

面板重新部署证书会重写 vhost：`listen <port> ssl;` 被改回明文、`error_page 497` 被重新插入。改后需复核，必要时 `chattr +i` 锁定。

## 四、外部视角验证（可选）

从真正的外网验证，排除"我自己在内网"的自欺：

```bash
# check-host.net 的 TCP 探测
curl -s -H "Accept: application/json" "https://check-host.net/check-tcp?host=<公网IP>:<端口>&max_nodes=3"
```

⚠️ 某些公共代理服务本身会 522（服务挂了），必须先用一个**已知正常的对照目标**（如 `example.com`）验证代理可用，再采信它的结论。
