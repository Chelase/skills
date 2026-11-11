# Chelase Skills

Chelase 的 Agent 技能合集。所有技能以标准 Agent Skills 格式（`SKILL.md`）存放在本仓库 `skills/` 目录下，Claude Code / Codex / Cursor 等支持该格式的 agent 通用。

## 30 秒上手

把这句话发给你的 AI agent：

> 读 <https://github.com/Chelase/skills> 的 README 和 skills.json，帮我安装（某个技能 / 按我的需求推荐）

自己动手：

```bash
# 安装全部
npx skills add gh:Chelase/skills

# 只安装某一个
npx skills add gh:Chelase/skills --skill mysql-check

# 注册为 Plugin Marketplace（Cursor / Claude Code）
/plugin marketplace add Chelase/skills
```

## 按需求找技能

| 你想做的事 | 用这个 |
| --- | --- |
| 给项目搭建一套 AI 看得懂的规则链路 | [project-rule-chain-init](skills/project-rule-chain-init) |
| 测一下能不能连上 MySQL，或跑一条 SQL | [mysql-check](skills/mysql-check) |
| 生成或编辑图片 | [image-craft](skills/image-craft) |

机器可读版目录在 [skills.json](skills.json)，AI agent 优先读它。

## 技能列表

### 工程基建

- [**project-rule-chain-init**](skills/project-rule-chain-init) — 为任意软件项目初始化 Agent 规则链路（`.agent-rules/` 四层目录 + 桥接入口）
  ```
  npx skills install gh:Chelase/skills --skill project-rule-chain-init
  ```

### 开发工具

- [**mysql-check**](skills/mysql-check) — MySQL/MariaDB 连接检测 + 任意 SQL 执行（bundled .NET 驱动、多 profile、SSH 隧道、默认拒绝写操作）
  ```
  npx skills install gh:Chelase/skills --skill mysql-check
  ```

### 内容创作

- [**image-craft**](skills/image-craft) — AI 图片生成与编辑（GPT Image / OpenAI / Azure / MiniMax 等多后端）
  ```
  npx skills install gh:Chelase/skills --skill image-craft
  ```

## 仓库结构

```
Chelase/skills/
├── .claude-plugin/marketplace.json   ← Plugin Marketplace 定义
├── skills/                           ← 各技能本体
│   ├── image-craft/
│   ├── mysql-check/
│   └── project-rule-chain-init/
├── skills.json                       ← 机器可读目录
└── README.md
```

## 安装方式

所有技能通过 [`npx skills`](https://skills.sh/) 安装：

```bash
# 安装单个技能
npx skills install gh:Chelase/skills --skill <skill-name>

# 查看已安装技能
npx skills list

# 更新技能
npx skills update <skill-name>
```

也可以直接克隆仓库后手动复制 `skills/<name>` 目录：

```bash
git clone https://github.com/Chelase/skills.git
cp -r skills/skills/<name> ~/.agents/skills/
```

## 贡献技能

如果你有 Idea 想做成技能，欢迎开 Issue 讨论。

技能本体统一放在 `skills/<技能名>/` 下，每个技能需包含 `SKILL.md`（带 `name` / `description` frontmatter）。新增后在 `skills.json` 和本 README 的技能列表里各登记一条。

> 仓库仅收录技能本体与索引，不含各技能的历史仓库。
