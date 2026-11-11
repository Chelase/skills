---
name: mysql-check
description: "MySQL/MariaDB connection check + ad-hoc SQL runner. Use when user asks to 'check MySQL', 'test MySQL connection', 'run SQL against MySQL', 'execute query', 'MySQL 状态检查', 'MySQL 连接测试', '跑这条 SQL 看看', '数据库增删改查', or provides MySQL credentials and wants to verify connection or run a query. Requires PowerShell 7.2+. Loads bundled MySqlConnector.dll (no mysql.exe needed), supports named profiles, optional SSH tunnel for bastion databases, and refuses write-like statements unless -AllowWrite is given."
version: 2.0.0
---

# MySQL Check

> **TL;DR** - One-shot MySQL/MariaDB connectivity check + ad-hoc SQL runner. Bundled .NET driver, named profiles, optional SSH tunnel, write-protected by default.
>
> **Use it when:**
> - "Test if I can connect to this MySQL" → `-Profile prod`
> - "Run this SQL on prod and show me the result" → `-Profile prod -Query "SELECT ..."`
> - "There's a DB behind a bastion, can you check it?" → profile with `ssh` block
>
> **One command:**
> ```powershell
> pwsh -File scripts/Test-MysqlConnection.ps1 -Profile prod
> pwsh -File scripts/Test-MysqlConnection.ps1 -Profile prod -Query "SELECT COUNT(*) FROM users"
> ```

## What it does

1. **Detects local Windows MySQL services** (`MySQL80`, `MySQL57`, `MariaDB*`) — informational, doesn't block.
2. **Loads bundled `MySqlConnector.dll`** (no `mysql.exe`, no PSGallery module — zero install beyond PS 7.2+).
3. **Resolves named profile** (if `-Profile` given) from `%USERPROFILE%\.mysql-check\config.json`.
4. **Opens SSH tunnel** (if profile has `ssh` block) via `ssh.exe` / `plink.exe` / `sshpass` / `Posh-SSH`.
5. **Authenticates** with the target MySQL via .NET driver.
6. **Reports** server version, current time, connected user, hostname, charset, table count.
7. **Executes user query** (if `-Query` / `-QueryFile` given) with write-protection.
8. **Cleans up** connection + SSH tunnel.

## Quick start

```powershell
# 0) FIRST TIME on a new machine: -Init wizard walks you through profile creation
pwsh -File scripts/Test-MysqlConnection.ps1 -Init

# 1) Direct (no config needed)
pwsh -File scripts/Test-MysqlConnection.ps1 `
  -Server 192.168.1.100 -Port 3306 `
  -User db_user -Password 'YOUR_PASSWORD_HERE' `
  -Database my_database

# 2) Save as named profile
pwsh -File scripts/Test-MysqlConnection.ps1 `
  -Server 192.168.1.100 -User db_user -Password 'YOUR_PASSWORD_HERE' `
  -Database my_database -SaveProfile my_database

# 3) From then on, just use the profile
pwsh -File scripts/Test-MysqlConnection.ps1 -Profile my_database

# 4) Run a query (read-only)
pwsh -File scripts/Test-MysqlConnection.ps1 -Profile prod -Query "SELECT COUNT(*) FROM users"

# 5) Run a write (must opt in)
pwsh -File scripts/Test-MysqlConnection.ps1 -Profile prod `
  -Query "DELETE FROM logs WHERE created < NOW() - INTERVAL 30 DAY" `
  -AllowWrite

# 6) Run a script from a .sql file
pwsh -File scripts/Test-MysqlConnection.ps1 -Profile prod -QueryFile C:\scripts\daily.sql

# 7) SSH-tunneled database (profile has 'ssh' block)
pwsh -File scripts/Test-MysqlConnection.ps1 -Profile wkbox2

# 8) Local-only probe (no remote auth)
pwsh -File scripts/Test-MysqlConnection.ps1 -LocalOnly
```

## 零接触启动（zero-touch onboarding）

技能会**自动检测并安装它能装的**，让你少做手动操作：

| 依赖 | 自动检测/安装方式 |
|---|---|
| **PowerShell 7.2+** | 脚本开头检测；缺时打 `pwsh -File ... -InstallPowerShell` 一行装（用 winget/choco） |
| **`MySqlConnector.dll`** | bundled 在 `lib/`，`Add-Type` 加载，**0 步** |
| **`.NET` 运行时** | PS 7 自带，**0 步** |
| **配置文件** | 不存在时 `-Init` 向导自动创建 + 写入 profile |
| **plink.exe** | profile 用 SSH 密码 + 没装 plink 时，自动 `winget install PuTTY.PuTTY` |
| **SSH keypair** | profile 配了 `ssh.key` 路径但文件不存在时，提示生成 ed25519 keypair，**你只需把公钥推给跳板机** |
| **MySQL host/user/password** | ❌ **不能自动**——这些是基础设施信息，你必须告诉脚本（用 `-Init` 向导或 CLI） |
| **跳板机 SSH 凭据** | ❌ **不能自动**——同上 |
| **跳板机 host key 指纹** | ❌ **不能自动**——必须先连一次确认（脚本提供 `ssh-keyscan` 风格的手动提取方式） |

### `-Init` 向导流程

```
> pwsh -File scripts/Test-MysqlConnection.ps1 -Init

=== mysql-check first-time setup ===

This wizard walks you through creating your first MySQL connection profile.
...
Profile name (e.g. prod, dev, my-wkbox): my_db
MySQL host (e.g. 192.168.1.100, db.example.com): 10.0.0.5
MySQL port [3306]: 3306
MySQL user: app_user
MySQL password: ********
MySQL database (optional, Enter to skip): app
Is the MySQL behind an SSH bastion? (y/N): y

  --- SSH bastion config ---
  SSH host (e.g. bastion.example.com): 10.0.0.1
  SSH port [22]: 22
  SSH user: ops
  Use SSH key auth? (y/N, default = password): y
  SSH key path [~/.ssh/id_ed25519]: C:\Users\me\.ssh\id_ed25519
    SSH key not found at: C:\Users\me\.ssh\id_ed25519
    Generate a new ed25519 keypair? (y/N): y
    OK: keypair generated

    ┌────────────────────────────────────────────────────────────────┐
    │  YOU STILL NEED TO PUSH THE PUBLIC KEY TO THE BASTION:         │
    │  Add the line below to ~/.ssh/authorized_keys on the SSH host  │
    └────────────────────────────────────────────────────────────────┘

    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxxxx...

    Press Enter after you've added the public key to the server (or 's' to skip)

  --- Test connection before saving ---
  ✓ Connection OK

  ✓ Profile 'my_db' saved to C:\Users\me\.mysql-check\config.json

  Next:
    pwsh -File "..." -Profile my_db
    pwsh -File "..." -Profile my_db -Query "SELECT 1"
```

## 依赖与注意事项（必读）

### 硬性依赖（缺了脚本直接 FAIL）

| 依赖 | 必需 | 缺了的表现 | 怎么补 |
|---|---|---|---|
| **PowerShell 7.2+ (`pwsh`)** | ✅ 必需 | 报 PS 版本错误并 exit 2 | `pwsh -File ... -InstallPowerShell` 自动装；或 `winget install Microsoft.PowerShell` |
| **Windows 10/11** | ✅ 必需 | `Get-Service` / `Test-NetConnection` 在 macOS/Linux 不存在 | 不要拿这脚本去 Linux 跑 |
| **`lib/MySqlConnector.dll` + 4 个 deps** | ✅ 必需（skill 自带） | `mysql-driver FAIL` | 重装 skill 即可，~1.2 MB，shipped |

### 容易被误解的"非必需"

| 项目 | 是否必需 | 说明 |
|---|---|---|
| **本地 MySQL 服务在跑** | ❌ 非必需 | local probe 只 WARN，不影响远端测试 |
| **本地 3306 通** | ❌ 非必需 | 同上，remote 测试与本机端口无关 |
| **`mysql.exe` 客户端** | ❌ **非必需** | 脚本自带 .NET 驱动，**完全不需要** |
| **PSGallery 模块（`rhubarb-geek-nz.MySqlConnection`）** | ❌ **非必需** | 之前是，后来改成 bundled DLL，零外部依赖 |
| **本机装了 MySQL Server** | ❌ 非必需 | 装 client 都不必，**只要 skill 自带的 lib/** |
| **`.my.cnf` / `my.ini`** | ❌ 非必需 | 所有参数走 CLI / profile，不读配置文件 |

### PowerShell 5.1 兼容说明

| 情况 | 行为 |
|---|---|
| 你只有 PS 5.1（Windows 默认） | 脚本自动 exit 2，提示 `pwsh -File ... -InstallPowerShell` 一行装 PS 7 |
| 你装了 PS 7 但 PATH 没指过去 | 同上，提示装/修 PATH |
| 你想绕过检查（不推荐） | 加 `-SkipPowerShellCheck` 强行跑，可能 `.dll` 加载失败 |

**理由：**
- `MySqlConnector.dll` 2.x 是 .NET 6+ 库，**只在 PS 7.2+ 的 .NET 运行时里能跑**
- PS 5.1 的 .NET Framework 4.x 装不了这个库，要塞一堆旧版依赖（System.Memory 4.0.1、System.Threading.Tasks.Extensions 4.1.0）还要写 binding redirect，**代价不值得**
- 装 PS 7.2+ 只需 `winget install Microsoft.PowerShell` 一行

### 安全 / 行为上的注意

- ⚠️ **密码以明文出现在命令行**。其他用户在本机能 `Get-Process` 看到，进程列表里也会留痕。脚本的 `mysql -p...` 不再出现（用 .NET 内部传密码），**不弹 MySQL 那个 insecure warning**——但密码仍在进程命令行里。
- ⚠️ **配置文件以明文存储密码**。`%USERPROFILE%\.mysql-check\config.json` 任何能读这文件的进程/用户都能拿到。脚本保存后会检查 ACL，文件对 `Everyone` 可读会打 `WARN` 并打印收紧命令。
- ⚠️ **写操作默认拒绝**。`-Query` / `-QueryFile` 里检测到 `INSERT/UPDATE/DELETE/CREATE/DROP/ALTER/TRUNCATE/RENAME/REPLACE/GRANT/REVOKE/SET/CALL/LOAD DATA/LOCK/UNLOCK/FLUSH/KILL/SHUTDOWN` 直接 FAIL exit 1。必须显式加 `-AllowWrite`。
- ⚠️ **不持久 SSH tunnel**。每次跑 fresh 起 + 拆。如果想复用，自己加 `-KeepTunnel` 开关。
- ⚠️ **不做 SSL/TLS 探测**。连字符串里设了 `SslMode=None`，如果你要 SSL/TLS 改脚本里的 connection string。
- ⚠️ **不做性能/并发/连接池**。体检+查询，不是压测工具。

### 已知边界

- 跳板机要二次跳（bastion → 跳板机 → MySQL）：当前脚本只支持一跳。多跳请用 `~/.ssh/config` 的 `ProxyJump` 配合 ssh key 路径。
- 写操作检测是**正则匹配关键字**，不是 SQL 解析器。`INSERT INTO ... SELECT` 这种用 `-- write me ` 注释掉 INSERT 关键字就能绕过。**只防误操作，不防恶意**。真要安全，上 MySQL 端用 `READ ONLY` 事务或单独建 `readonly` 用户。
- 多语句分隔符是 `;`。如果 SQL 字符串里有 `;`，脚本的引号解析会处理，但极复杂场景（嵌套 escape）可能误切。
- 查询结果集如果很大（>10MB），会一次性加载到内存。想流式自己改 `Write-ResultSet`。

## 架构

```
D:\code\skills\mysql-check\              ← 源（你工作的地方）
├── SKILL.md                              ← 本文档
├── config.example.json                   ← 配置模板（可入仓）
├── lib\                                  ← 必备（不要删）
│   ├── MySqlConnector.dll                 ← 805 KB, MySQL 驱动
│   ├── Microsoft.Extensions.Logging.Abstractions.dll  63 KB
│   ├── System.Diagnostics.DiagnosticSource.dll       147 KB
│   ├── System.Memory.dll                  141 KB
│   └── System.Threading.Tasks.Extensions.dll   33 KB
│                                         ← 总 ~1.2 MB，shipped with skill
└── scripts\
    └── Test-MysqlConnection.ps1          ← 唯一入口（~600 行）

C:\Users\g2911\.agents\skills\mysql-check ← 符号链接（reparse-point）
   指向 D:\code\skills\mysql-check  ← Windows agent 在这里发现技能

%USERPROFILE%\.mysql-check\config.json   ← 用户私有配置（不进 git）
   包含 1+ 个 named profile
```

**单文件 = 单入口 = 单职责**：所有"我能不能连上这个 MySQL / 在这个 MySQL 上跑 SQL"的问题都走这一个脚本。

## SSH 隧道（bastion / 跳板机场景）

profile 加 `ssh` 块，脚本自动起 `-L` 端口转发。

### 流程

```
你本机                       跳板机                    MySQL
┌──────────────┐            ┌──────────────┐         ┌──────────────┐
│ MySqlConnector│  ──ssh -L─▶│ sshd :7022   │  ─────▶ │ 127.0.0.1    │
│ (in-process)  │ 127.0.0.1: │              │  3800    │ :3800        │
│ :13306 ──────│─:13306───▶│              │ ───────▶ │              │
└──────────────┘            └──────────────┘         └──────────────┘
```

### Profile 写法

```json
{
  "my_bastion_db": {
    "server": "127.0.0.1",
    "port":   3306,
    "user":   "db_user",
    "password": "YOUR_DB_PASSWORD",
    "database": "my_database",
    "ssh": {
      "host":   "bastion.example.com",
      "port":   22,
      "user":   "ssh_user",
      "password": "YOUR_SSH_PASSWORD",
      "hostkey": "SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    }
  }
}
```

- `server:port` 是 MySQL 端点，**从跳板机视角看**（通常是 `127.0.0.1:3306/3800`）。
- `ssh.host/port/user` 跳板机登录信息。
- `ssh.key` **推荐**：SSH 公私钥。
- `ssh.password` 备选：需要额外工具（见下表）。
- `ssh.hostkey` 可选：服务器 host key 的 SHA256 指纹（`SHA256:xxx`）。**强烈建议给 plink 用**——plink 首次连会卡在 host key 交互提示。

### 4 种 SSH 认证方法（脚本自动按优先级选）

| 优先级 | 触发条件 | 工具 | 适用 |
|---|---|---|---|
| 1 | `ssh.key` 有值 | `ssh.exe`（Windows 10+ 自带） | **推荐**，无密码、CI 友好 |
| 2 | `ssh.password` + PATH | `plink.exe`（PuTTY） | 不想配 key 的人；**首次连必须配 `ssh.hostkey`** 否则 plink 会卡 host key 提示 |
| 3 | `ssh.password` + PATH | `sshpass.exe` | 第三方 |
| 4 | `ssh.password` + 模块 | `Posh-SSH` | 纯 PowerShell 派 |

> 不满足时脚本报错并打印一键指引。最实际的两条路：
> 1. **配 SSH key**：`ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\id_ed25519" -N ''` + 把 `id_ed25519.pub` 给跳板机管理员
> 2. **装 plink**：[https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html](https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html)

## 多配置切换（Named Profiles）

存到 JSON 配置里，调用时只传 `-Profile <name>`。CLI 参数仍能覆盖配置。

### 配置文件位置（按优先级）

1. `-Config <path>` 显式指定
2. `$env:MYSQL_CHECK_CONFIG` 环境变量
3. 默认：`%USERPROFILE%\.mysql-check\config.json`

### 配置文件格式

```json
{
  "profiles": {
    "<name>": {
      "server":   "192.168.1.100",
      "port":     3306,
      "user":     "db_user",
      "password": "YOUR_PASSWORD_HERE",
      "database": "my_database"
    }
  }
}
```

`port` 和 `database` 可省略（默认 3306 / 切换到 `mysql` 系统库）。`password` 留空表示走 `-Password` 流程。

### 典型操作

```powershell
# 列出所有 profile（密码 mask 成 ****）
pwsh -File scripts/Test-MysqlConnection.ps1 -ListProfiles

# 切换到 prod
pwsh -File scripts/Test-MysqlConnection.ps1 -Profile prod

# 用 profile 基础，但临时覆盖 query
pwsh -File scripts/Test-MysqlConnection.ps1 -Profile prod -Query "SELECT NOW()"

# 第一次保存
pwsh -File scripts/Test-MysqlConnection.ps1 `
  -Server 10.0.0.5 -User app -Password 'secret' -Database app_prod `
  -SaveProfile prod
```

> ⚠️ `-SaveProfile` **不保存 SSH 块和 mysql key**（只保存 server/port/user/password/database）。SSH 字段要手工编辑 `config.json`。

### 参数解析顺序

```
1. -ListProfiles                          → 列出并退出（不连接）
2. 默认配置路径 / -Config / $env:...      → 加载 JSON
3. -Profile <name>                        → 用配置填充未指定的字段
4. -Server/-User/-Password/-Database      → 覆盖配置里的同名字段
5. 缺的字段就 FAIL
```

## 跑任意 SQL（-Query / -QueryFile）

### 参数

| 参数 | 必需 | 默认 | 说明 |
|---|---|---|---|
| `-Query <sql>` | * | — | 单条或多条 SQL（`;` 分隔）。**默认拒绝写** |
| `-QueryFile <path>` | * | — | 从 `.sql` 文件读，跟 `-Query` 互斥 |
| `-AllowWrite` | 否 | off | 显式 opt-in 才允许 INSERT/UPDATE/DELETE/DDL/... |
| `-ResultFormat` | 否 | `Table` | `Table` / `Json` / `Csv` / `Raw` |
| `-QueryTimeoutSec` | 否 | 30 | 单条 query 超时秒数 |

\* = `-Query` 和 `-QueryFile` 二选一。

### 写操作保护（默认开启）

```
$ pwsh -File ... -Query "DELETE FROM logs WHERE 1=1"
FAIL safety: query contains write-like statement; refusing. Pass -AllowWrite to opt in.
  Detected: INSERT/UPDATE/DELETE/REPLACE/CREATE/DROP/ALTER/TRUNCATE/RENAME
            /GRANT/REVOKE/SET/CALL/LOAD DATA/LOCK/UNLOCK/FLUSH/KILL/SHUTDOWN
exit: 1
```

**正则匹配**，不是 SQL 解析器。能防：
- `DROP DATABASE prod` 误敲
- `rm -rf *` 复制粘贴
- agent 自己脑抽跑 DELETE

**防不住：**
- 注释里写 INSERT 关键字
- 用存储过程包装

真要安全：**上 MySQL 端用 `READ ONLY` 事务或单独建 `readonly` 用户**。

### 输出格式

- **Table**（默认）：左对齐 ASCII 表格
- **Json**：`ConvertTo-Json -Depth 5`
- **Csv**：`ConvertTo-Csv -NoTypeInformation`
- **Raw**：返回 `DataTable` 对象（pipeline 友好）

### 多语句

```powershell
pwsh -File ... -Query @'
SELECT COUNT(*) AS total FROM users WHERE active = 1;
SELECT COUNT(*) AS total FROM users WHERE active = 0;
'@
```

按 `;` 切（不在字符串/注释里的）。每条独立执行，write 类的会触发安全检查。

## 参数清单

| Param | 必需 | 默认 | 说明 |
|---|---|---|---|
| `-Server` | * | — | hostname / IP；`-Profile` 模式可省略 |
| `-Port` | 否 | `3306` | 覆盖 profile 里的 port |
| `-User` | * | — | 覆盖 profile 里的 user |
| `-Password` | * | — | 单引号包，**不**要在双引号里有 `$` |
| `-Database` | 否 | — | 覆盖 profile 里的 database |
| `-LocalOnly` | 否 | off | 只查本地服务+TCP+driver load，不连远端 |
| `-Config <path>` | 否 | `~/.mysql-check/config.json` | 自定义配置路径 |
| `-Profile <name>` | 否 | — | 选配置里的某个 profile；CLI 参数可覆盖其字段 |
| `-ListProfiles` | 否 | off | 列出所有 profile（密码 mask），列出后退出 |
| `-SaveProfile <name>` | 否 | — | 把当前参数（含 profile 合并结果）保存为新 profile（不含 ssh 块） |
| `-SshTunnelPort` | 否 | `13306` | profile 有 `ssh` 块时，本地转发端口；冲突会 FAIL |
| `-SshWaitSeconds` | 否 | `8` | 等 SSH 隧道 ready 的秒数 |
| `-Query <sql>` | 否 | — | 跑 SQL（默认拒绝写） |
| `-QueryFile <path>` | 否 | — | 从文件读 SQL |
| `-AllowWrite` | 否 | off | opt-in 允许写操作 |
| `-ResultFormat` | 否 | `Table` | `Table` / `Json` / `Csv` / `Raw` |
| `-QueryTimeoutSec` | 否 | `30` | query 超时 |
| `-InstallPowerShell` | 否 | off | 缺 PS 7.2+ 时自动装 |
| `-Init` | 否 | off | 首次配置向导：交互式创建 profile（自动装 plink / 自动生成 SSH key）|
| `-ForceProfile` | 否 | off | `-Init` 时覆盖同名 profile |
| `-SkipPowerShellCheck` | 否 | off | 强行绕过 PS 版本检查（不推荐） |

\* = `-LocalOnly` 或 `-Profile <name>` 至少满足一个时，该字段可省略。

## 行为契约

- **Auth 失败原样上报**：`Access denied (using password: YES)` 直接报，**不重试**。
- **写操作默认拒绝**：检测到关键字立刻 FAIL exit 1。
- **不写盘 / 不改状态**：除了 .NET 驱动内部的网络 I/O，对本地和远端 MySQL 都**只读**（除非你 `-AllowWrite`）。
- **密码不回显**：成功路径里只打印 `User@Server:Port`，密码始终不出现。
- **退出码**：`0` = 连接成功；`1` = 任一 FAIL 阶段；`2` = PS 版本不达标。

## 给你这个场景的总结

你有 5 个 wkbox 环境（数谷云盒、智企云盒demo、lcbox测试、wkbox-dev、wkbox2）：
- 4 个在 LAN（直连）
- 1 个在公网后跳板机（SSH 隧道）

把这 5 个都做成 profile 后，日常用：
```powershell
pwsh -File "...\Test-MysqlConnection.ps1" -Profile 数谷云盒
pwsh -File "...\Test-MysqlConnection.ps1" -Profile wkbox2 -Query "SELECT 1+1"
```

**0 安装步骤**（除 PS 7.2+ 一次）。`lib/` 里的 .NET 驱动 ship 好了，符号链接一做就能用。

---

**TL;DR**: 体检+任意 SQL 客户端，**bundled .NET 驱动 + 多 profile + SSH 隧道 + 写保护**。要监控、要压测、要 ORM —— 它不是答案。
