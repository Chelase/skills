# Jump Tunnel 设计文档

> 状态：已实现（v1.2.0，PowerShell）。本文记录关键设计决策与实现要点。

## 一、定位

通过外网跳板机（bastion）建立 SSH 隧道，把本机端口转发到内网任意服务（SSH 服务器 / MySQL / 任意 TCP）。与限定数据库的 php 版 `tunnel.php`（项目内单隧道方案）不同，本技能是**通用、多隧道、可复用**的工具。

## 二、设计决策（已确定）

| # | 决策 | 说明 |
|---|------|------|
| 1 | 跳板机可配置 | host/port/user/认证方式全部走 JSON 配置，不写死；支持在 `bastions` 里定义**多台**跳板机，顶层 `"bastion"` 指定默认，隧道条目用 `"bastion"` 单独指定 |
| 2 | 多隧道支持 | 一个配置可建立多条 `-L` 固定端口转发；每条隧道一个独立 ssh 进程 |
| 3 | 后端选 Windows 自带 OpenSSH | `ssh.exe`（Win10/11 自带，零安装）；**不依赖 plink/PuTTY**（已踩坑：plink 本机认证异常） |
| 4 | 密码非交互传递 | `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE=force` + `DISPLAY`；临时 .cmd 脚本，用完即删 |
| 5 | 凭据不入库 | 真实配置 `config/jump-tunnel.config.json` 被 `.gitignore` 排除；仓库只保留 `*.example.json` |
| 6 | 实现语言 PowerShell | 依赖 pwsh 7.2+；与仓库内 `mysql-check` 技能同栈，可串联使用（本技能建隧道 → mysql-check 连库验证） |
| 7 | 进程/端口管理 | PID 与 askpass 记录在 `%USERPROFILE%\.jump-tunnel-runtime\`；start/stop/test/status 四命令 |

## 三、实现要点

- **启动**：`Start-Process ssh -N -L <local>:<remote> user@bastion -p <port>`，`-WindowStyle Hidden -PassThru` 后台运行；记录 `$proc.Id`。
- **askpass**：`@echo off` + `echo <密码>` 写入临时 .cmd；密码中 `%` 转义为 `%%`（防止 cmd 展开）。
- **环境变量**：`DISPLAY=localhost:0`、`SSH_ASKPASS=<askfile>`、`SSH_ASKPASS_REQUIRE=force`，使 ssh 在无终端时也可读密码。
- **检测**：`System.Net.Sockets.TcpClient.ConnectAsync(host, port)` 3s 超时 TCP 握手。
- **多隧道**：逐条 `-L` 同属一个 ssh 进程会产生互相影响，故**每条隧道独立进程**，stop/status 按名称定位 PID 文件。

## 四、与 mysql-check 的协作

```powershell
# 1. 建隧道
pwsh .\jump-tunnel\scripts\Jump-Tunnel.ps1 start
# 2. 通过隧道连库（mysql-check 技能）
pwsh .\mysql-check\scripts\Test-MysqlConnection.ps1 -Server 127.0.0.1 -Port 13306 -User root -Password '***' -Database your_db
```

## 五、实测记录

- 已实测（脱敏前的内部环境）：跳板机 → 内网数据库端口连通（MySQL 8.0.39）；mysql-check 验证 `CONNECTED OK`。
- 经验：某些环境的 MySQL 端口并非默认 3306（如 3800），先用 TCP 探测确认目标端口。

## 六、未来扩展（待定）

- [ ] 动态转发 `-D`（SOCKS5）支持
- [ ] SSH key 认证（免密码）
- [ ] 配置校验（端口冲突预检）
- [ ] 跨平台（Linux/macOS 走 sshpass 或 ControlMaster）