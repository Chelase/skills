# Chelase Skills

Chelase 的 Agent 技能合集。每个技能独立仓库，通过技能安装器按需安装。

## 技能列表

### 工程基建

- [**project-rule-chain-init**](https://github.com/Chelase/project-rule-chain-init) — 为任意软件项目初始化 Agent 规则链路（`.agent-rules/` 四层目录 + 桥接入口）
  ```
  npx skills install gh:Chelase/project-rule-chain-init
  ```

### 开发工具

- [**mysql-check**](https://github.com/Chelase/mysql-check) — MySQL/MariaDB 连接检测 + 任意 SQL 执行（bundled .NET 驱动、多 profile、SSH 隧道、默认拒绝写操作）
  ```
  npx skills install gh:Chelase/mysql-check
  ```

### 内容创作

- [**image-craft**](https://github.com/Chelase/image-craft) — AI 图片生成与编辑（GPT Image / OpenAI / Azure / MiniMax 等多后端）
  ```
  npx skills install gh:Chelase/image-craft
  ```

## 安装方式

所有技能通过 [`npx skills`](https://ohmyopenccode.com/docs/guides/skills) 安装：

```bash
# 安装单个技能
npx skills install gh:Chelase/<repo-name>

# 查看已安装技能
npx skills list

# 更新技能
npx skills update <skill-name>
```

## 贡献技能

如果你有 Idea 想做成技能，欢迎开 Issue 讨论。

> 仓库仅作索引，不包含技能本体代码。
