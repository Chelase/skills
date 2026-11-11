---
name: windows-c-drive-cleaner
description: "Windows C 盘扫描 + 分级清理（开发缓存重点：JetBrains/npm/pip/uv/gradle/.m2/cargo/Go/Playwright/VS/Codex/Cursor/AVD/nvm）。先只读扫描产出 T1 零风险 / T2 可再生 / T3 需判断 三级清单，逐层批准后执行清理：回收站优先、T3 可逆暂存、LocalHistory 等硬保护不可覆盖、实测释放量收尾。当用户说'扫一下 C 盘''磁盘满了/空间不够''清理空间/清理磁盘''清一下开发缓存''JetBrains/npm/VS 占了多少''哪些目录占地方'，或想对 Windows 磁盘做任何删除性清理时必须使用本技能。区别于 storage-analyzer（通用只读 HTML 报告）：本技能包含带审批的执行环节和开发缓存的专用判定。"
version: "2.0.0"
---

# Windows C 盘分级清理

> **TL;DR** — 只读扫描 → 三级呈报 → 逐层批准 → 执行（DryRun 默认）→ 实测复核。
    10|> 删除性操作永远先 DryRun；回收站优先；LocalHistory 类保护目录硬拒绝。

## 什么时候用它 / 什么时候不用

- **用它**：C 盘（或其他盘）空间紧张，重点是开发缓存；用户已经或即将授权删除。
- **不用**：用户只想要一份漂亮的全盘只读报告（用 storage-analyzer）；macOS/Linux；系统盘重装类需求。

## 工作流（六步，顺序不可换）

### 1. 读陷阱清单
    20|删任何东西前先读 [`references/traps.md`](references/traps.md)。本次流程里最贵的教训都在里面
（VS Installer 后台下载、Package Cache 误判孤儿、junction 双计、LocalHistory）。

### 2. 只读扫描
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Scan-CDrive.ps1 -Drive C:\ -OutFile scan-report.md -Json scan-plan.json
```
- 脚本是 runspace 并行 + junction 跳过的，**不要**用 Git Bash `du` 替代（在 AppData 必超时）。
- `-Quick` 跳过盘根全量汇总（Windows\WinSxS 很慢），只要目标清单时用。
- 产出：`scan-report.md`（人读）+ `scan-plan.json`（给清理脚本当输入）。
    30|
### 3. 分级呈报（先一句话结论，再给表）
- **T1 零风险**：临时文件、包管理器缓存本体。可以整层打包等一个"执行"。
- **T2 可再生**：IDE/构建缓存。执行前把 Guard 列的内容念出来（关 IDE、查版本 pin）。
- **T3 需判断**：工具数据、Package Cache、WSL/Docker、pagefile。逐项问，不许整层打包。
- 每项必须有：路径、大小、判定依据。扫描超时的项标"≥此值"。

### 4. 逐层批准
- T1：一轮点头即可执行整层。
- T2：Guard 无冲突才可整层；有冲突的项单独拎出来问。
    40|- T3：逐项点头，且脚本要求 `-AllowT3` 才肯跑。
- 用户没点头的项，最后如实列出（带大小和原因），不许悄悄漏掉也不许悄悄替用户决定。

### 5. 执行（DryRun 默认）
```powershell
# 先看会动什么（不删）
powershell ... -File scripts/Clean-CDriveTier.ps1 -PlanFile scan-plan.json -Tier T1
# 批准后真执行：回收站优先
powershell ... -File scripts/Clean-CDriveTier.ps1 -PlanFile scan-plan.json -Tier T1 -Mode Recycle
# 不可逆风险大时用暂存（可手工移回，manifest 在暂存目录里）
    50|powershell ... -File scripts/Clean-CDriveTier.ps1 -Ids package-cache -Mode Staging -AllowT3
```
- 内置硬保护（参数覆盖不了）：`LocalHistory` 目录永不触碰；目标必须在白名单根之下；T3 必须显式 `-AllowT3`。
- 占用中的文件逐项失败并记录，不会让整目录操作报废。

### 6. 实测复核
- 汇报**脚本实测的 freed 量**（前后 free space 差），不是估算。
- 失败/跳过项带原因列出；"哪些没清成"比"清了多少"更重要。
- 做错的当场认账（比如误删了还在用的东西），给出恢复动作。

    60|## 脚本与文件

| 文件 | 作用 |
|---|---|
| `scripts/Scan-CDrive.ps1` | 只读扫描：盘根汇总 + 60+ 个开发缓存/系统目标，按 T0-T3 分级，出 MD 报告 + JSON 计划 |
| `scripts/Clean-CDriveTier.ps1` | 分级执行器：DryRun/Recycle/Staging/Delete，硬保护，实测释放量 |
| `references/traps.md` | 踩坑清单：删前必查项，每条带"为什么 + 怎么查" |

## 边界

    70|- 脚本输出是 ASCII；最终给用户的中文报告由你（agent）来写，别往 `.ps1` 里塞中文。
- 回收站会占 C 盘空间：`-Mode Recycle` 清完若还要立刻回收空间，需用户确认后再清空回收站。
- 这套技能不碰：正在运行的数据库/容器数据、任何点过"保留"的目录、pagefile/hiberfil（除非用户明确要关休眠）。
