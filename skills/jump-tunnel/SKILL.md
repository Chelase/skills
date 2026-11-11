---
name: jump-tunnel
description: "跳板机 SSH 隧道工具（PowerShell）：通过外网跳板机（bastion）SSH 隧道连接内网服务——内网 SSH 服务器、内网 MySQL/PostgreSQL 数据库、以及任意内网 TCP 服务。触发词：跳板机、隧道、bastion、SSH 转发、端口转发、外网连内网、连内网数据库、连内网服务器、jump tunnel。"
version: 1.2.0
---

# Jump Tunnel（跳板机隧道连接内网）

> **TL;DR** - 通过外网可达的跳板机（bastion）建立 SSH 隧道，把本机端口转发到内网任意服务（SSH 服务器 / MySQL / 任意 TCP）。多隧道由一份 JSON 配置驱动，`start / stop / test / status` 四命令管理。
>
> **用它的场景：**
> - "外网连不上内网数据库，帮我搭个隧道" → 配好跳板机 + 目标库，`start` 后即可用 `127.0.0.1:<本地端口>` 连库
> - "通过跳板机连内网某台服务器的 SSH" → 加一条隧道转发到 `22` 端口
> - "连内网某个 web / 任意 TCP 服务" → 加一条隧道转发到对应端口

## 快速开始

```powershell
# 1. 复制配置模板并填写真实凭据（真实配置文件不入库）
Copy-Item config\jump-tunnel.config.example.json config\jump-tunnel.config.json
#   编辑 config\jump-tunnel.config.json：
#   - bastions.<名字>.password = 跳板机密码（可定义多台跳板机）
#   - 顶层 "bastion" 指定默认跳板机
#   - tunnels 改为目标内网服务（支持多条，可用 "bastion" 指定走哪台跳板机）

# 2. 启动隧道（后台运行）
pwsh -File .\scripts\Jump-Tunnel.ps1 start

# 3. 查看状态 / 测试端口
pwsh -File .\scripts\Jump-Tunnel.ps1 status
pwsh -File .\scripts\Jump-Tunnel.ps1 test

# 4. 连库验证（配合 mysql-check 技能）
pwsh -File ..\mysql-check\scripts\Test-MysqlConnection.ps1 `
  -Server 127.0.0.1 -Port <本地端口> -User <db_user> -Password '<db_pass>' -Database <db_name>

# 5. 收尾
pwsh -File .\scripts\Jump-Tunnel.ps1 stop
```

## 依赖

- **PowerShell 7.2+**（`pwsh`）
- **Windows 自带 OpenSSH**（`C:\Windows\System32\OpenSSH\ssh.exe`，Win10/11 默认具备；脚本自动探测：`SSH_PATH` 环境变量 → 系统自带位置 → PATH）
- 不需要 plink/PuTTY（已踩坑：本机 plink 认证异常，OpenSSH 稳定）

## 工作原理

```
本机 127.0.0.1:<本地端口>  --SSH隧道(-L)-->  跳板机(bastion:host:22 user)  -->  内网 <remote_host>:<remote_port>
```

- 每条隧道一个独立 `ssh -N -L` 进程，后台运行（`-WindowStyle Hidden`）。
- 密码经 **SSH_ASKPASS** 机制非交互传递：生成临时 askpass 脚本 → 设置 `SSH_ASKPASS` / `SSH_ASKPASS_REQUIRE=force` / `DISPLAY` 环境变量 → 启动 ssh；askpass 文件在 stop 或进程退出时清理。
- 进程 PID 记录在 `%USERPROFILE%\.jump-tunnel-runtime\`，便于 stop/status 管理。

## 命令一览

| 命令 | 说明 |
|------|------|
| `start` | 启动全部（或 `-Tunnel <name>` 指定）隧道，自动等待 2s 后检测端口 |
| `stop`  | 停止全部（或指定）隧道，清理 askpass/pid 文件 |
| `test`  | TCP 握手探测各隧道本地端口是否可连（`-Tunnel` 可指定单条） |
| `status`| 展示各隧道：进程是否存活 + 本地端口状态 |
| `help`  | 帮助（`Get-Help`） |

可选参数：
- `-Config <path>`（默认 `..\config\jump-tunnel.config.json`）
- `-Tunnel <name>`（按 `tunnels[].name` 匹配，作用于 start/stop/test/status）。**支持逗号分隔多选**（`-Tunnel db-main,inner-ssh`），一条命令即可只启指定的子集；不传则作用于全部隧道。

> 多选时如果某个名字在配置里不存在，会直接报错 `tunnel not found: xxx`，避免手误后静默只开了一部分。

## 配置格式

支持**多跳板机**：在 `bastions` 里定义多台，每条隧道可用 `bastion` 指定用哪台（省略则用默认）。

```json
{
  "bastion": "primary",
  "bastions": {
    "primary": {
      "host": "bastion.example.com",
      "port": 22,
      "user": "your-user",
      "password": "PASTE_BASTION_PASSWORD_HERE"
    },
    "backup": {
      "host": "backup-bastion.example.com",
      "port": 22,
      "user": "your-user",
      "password": "PASTE_BACKUP_BASTION_PASSWORD_HERE"
    }
  },
  "tunnels": [
    {
      "name": "db-main",
      "bastion": "primary",
      "local":  { "host": "127.0.0.1", "port": 13306 },
      "remote": { "host": "10.0.0.10", "port": 3306 }
    },
    {
      "name": "db-standby",
      "bastion": "backup",
      "local":  { "host": "127.0.0.1", "port": 13307 },
      "remote": { "host": "10.0.0.11", "port": 3306 }
    },
    {
      "name": "inner-ssh",
      "local":  { "host": "127.0.0.1", "port": 2222 },
      "remote": { "host": "10.0.0.20", "port": 22 }
    }
  ]
}
```

**跳板机切换规则：**
- `bastion`（顶层字符串）= **默认跳板机名**，必须能在 `bastions` 里找到。
- 隧道条目里的 `"bastion": "<名字>"` = 该条隧道**单独指定**跳板机；省略则用默认。
- 切换默认跳板机：改顶层 `"bastion": "backup"`；只切某条隧道：改该隧道的 `"bastion"`。
- reverse 隧道若配了 `server.host`（自动 bridge），bridge 走**该隧道指定的**跳板机；用 `via` 复用已有 forward 时，跳板机由那条 forward 决定。

**兼容性：** 旧的单跳板机写法（顶层 `"bastion": { host, port, user, password }`）仍可用，会被当作名为 `default` 的唯一跳板机。

### 连公网服务器（不经过公司跳板机）

公网服务器本身可以**当成跳板机**来用——跳板机只是"SSH 的落点"，不要求它在内网：

```json
{
  "bastions": {
    "pub": { "host": "1.2.3.4", "port": 22, "user": "root", "password": "..." }
  },
  "tunnels": [
    {
      "name": "pub-ssh",
      "bastion": "pub",
      "local":  { "host": "127.0.0.1", "port": 2222 },
      "remote": { "host": "1.2.3.4", "port": 22 }
    }
  ]
}
```

三种常见情形：

| 情形 | 配置方式 | 说明 |
|------|----------|------|
| 目标就是那台公网机 | `bastion` 和 `remote` 都填它 | 链路 `本机 → 公网机 → 公网机`，等价于直连，只是多绕一跳 |
| 公网机要再转发到别处 | `bastion` = 公网机，`remote` = 另一台 | 链路 `本机 → 公网机 → 目标` |
| 公司跳板机要连公网机 | `bastion` = 公司跳板机，`remote` = 公网机 | **前提：跳板机自己访问得到那台公网机** |

注意：
- 本地端口别用 22，避免和你正常 SSH 混淆，用高位端口（2222 / 20022 等）。
- 公网场景只用 `mode: "forward"`；`reverse` 是"内网机反向连本机"，在这里用不上。

- 跳板机默认推荐填你们自己的跳板机地址（模板用 `bastion.example.com` 占位），可任意替换或新增多台。
- 真实配置（含密码）在 `config/jump-tunnel.config.json`，已被 `.gitignore` 排除，**不入库**；仓库只保留 `.example.json` 模板。
- 一条隧道一个目标服务；要通多个内网服务就配多条隧道，一次 `start` 全部建立。

## 实测记录

- 已实测（脱敏前的内部环境）：跳板机 → 内网数据库端口连通（MySQL 8.0.39）；通过 `mysql-check` 验证 `CONNECTED OK`。
- 经验：某些环境的 MySQL 端口并非默认 3306，先用 TCP 探测确认目标端口。

## 常见问题

- **test FAIL**：`status` 看进程是否存活；本地端口 3306/3308 被占用可换其他数字；确认跳板机密码已填。
- **TCP 通但 MySQL 握手失败**：可能目标端口不是 3306（某些环境用 **3800**），改为实际 MySQL 端口。
- **配了多条隧道只启动一条**：检查 `-Tunnel` 参数名称是否与 `tunnels[].name` 完全一致。
- **只想开一部分**：`start -Tunnel 名字1,名字2`（逗号分隔），不传 `-Tunnel` 会开全部。
- **换跳板机**：改顶层 `"bastion"` 切换默认，或给单条隧道加 `"bastion": "<名字>"`；`status` 输出的 bastion 列可确认当前每条隧道实际走的跳板机。
- **reverse 显示 RUNNING 但内网连不上**：远端 sshd 会话掉线时，PC 侧 ssh 进程可能仍存活，此时远端根本没有监听端口（客户端 `ServerAliveInterval=15/CountMax=3`，最多约 45s 才发现）。判断 reverse 是否可用必须用 `test`（会从内网侧实测探端口），`status` 也已改为对 reverse 做远端探测，不再只看进程。脚本对 reverse 加了 `-o ExitOnForwardFailure=yes`：远端端口绑不上会直接报错退出，而不是静默挂着。
- **隧道通了但服务端静默断连（curl: (52) Empty reply from server）**：目标边缘（nginx 类）会对 `Host` 头里的**非标准端口**敏感。经隧道访问时 URL 端口是本地监听端口（如 15002），`Host` 会变成 `intranet-app.example.com:15002` 而被直接 close。客户端必须显式指定不带端口的 Host：`curl -k -H "Host: intranet-app.example.com" --resolve intranet-app.example.com:15002:127.0.0.1 https://intranet-app.example.com:15002/<path>`。
- **reverse 访问命令的协议**：默认按 `https` 生成（内网应用在 50000 上也常是 TLS，靠端口猜不可靠）；如需 `http` 在隧道上写 `"scheme": "http"`。

## reverse 反向共享（本机 VPN → 任意内网机）

本机已连 VPN、能访问内网应用地址，但内网某台机器（不限具体 IP，任意 `server.host`）访问不到时，用 **reverse** 隧道：

```
内网机 127.0.0.1:<listen.port>  --SSH -R-->  本机(VPN)  -->  <target.host>:<target.port>
```

### 配置方式（二选一）

**A. 任意内网机（自动经跳板建 SSH bridge）**

```json
{
  "name": "share-intranet-app-to-X",
  "mode": "reverse",
  "server": {
    "host": "10.0.0.30",
    "port": 22,
    "user": "your-user",
    "password": "内网机SSH密码",
    "bridgePort": 22050
  },
  "listen": { "host": "127.0.0.1", "port": 15000 },
  "target": { "host": "intranet-app.example.com", "port": 50000 }
}
```

**B. 复用已有 forward（via）**

先有一条 forward 把内网机 22 转到本机，再：

```json
{
  "name": "intranet-app-via-forward",
  "mode": "reverse",
  "via": "inner-ssh",
  "server": { "user": "your-user", "password": "内网机SSH密码" },
  "listen": { "host": "127.0.0.1", "port": 15000 },
  "target": { "host": "intranet-app.example.com", "port": 50000 }
}
```

### 命令

```powershell
pwsh -File .\scripts\Jump-Tunnel.ps1 start -Tunnel intranet-app-via-forward
pwsh -File .\scripts\Jump-Tunnel.ps1 test -Tunnel intranet-app-via-forward
pwsh -File .\scripts\Jump-Tunnel.ps1 status
pwsh -File .\scripts\Jump-Tunnel.ps1 stop -Tunnel intranet-app-via-forward
```

### 在内网机上调用

```bash
curl -k --resolve intranet-app.example.com:15000:127.0.0.1 \
  https://intranet-app.example.com:15000/api/getUserId \
  -H "Authorization: <api-key>" -F workcode=12345678
```

> forward 条目可显式写 `"mode": "forward"`；省略时默认为 forward，兼容旧配置。
