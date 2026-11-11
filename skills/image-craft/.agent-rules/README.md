# image-generation Agent Rules

## 1. 目的

`.agent-rules/` 是本仓库所有项目级 agent 规则的唯一真来源。

以下文件都应视为桥接入口，而不是各自维护一套独立规则：

- `CLAUDE.md`
- `AGENTS.md`（如存在）

如果这些桥接文件与本目录内容不一致，应以 `.agent-rules/` 为准，并在合适时机修正桥接文件，避免规则漂移。

## 2. 规则读取链路

任何 agent 在本仓库执行分析、编辑、测试、提交准备之前，应按以下链路读取规则：

1. `CLAUDE.md`（通用准则 + 入口指向）
2. `.agent-rules/` 下实际存在的规则文件（全部）
3. 根据任务再读取相关项目文档：
   - 功能与使用背景：`README.md` / `README_CN.md`
   - 技能元数据：`SKILL.md`
   - 功能进度真来源：`project-docs/ROADMAP.md`
   - GEO 工作真来源：`project-docs/GEO.md`
   - 数据 schema：`data/*.csv` 头行
   - 技能规范：`.agent-rules/skill-standards.md`

每次开启新 Phase 或新任务前，应快速扫描 `.agent-rules/agent-pre-read.md` 确认关键检查点。

## 3. 规则优先级

规则冲突时，按以下优先级处理：

1. 系统或宿主工具指令
2. 用户当前明确提出的要求
3. `.agent-rules/` 下的规则
4. 桥接文件（`CLAUDE.md` / `AGENTS.md`）中的摘要说明
5. 单一事实来源文档（`project-docs/ROADMAP.md` / `project-docs/GEO.md` / `SKILL.md`）
6. 其他项目文档中的补充描述

如果其他项目文档与 `.agent-rules/` 或当前代码实现不一致，不要继续扩散不一致描述；应优先遵守当前有效规则与代码实现，并在任务允许时同步修正文档。

## 4. 当前项目状态

本仓库是开源 AI Agent 图像生成技能（产品名 **Image Craft**），通过 OpenAI 兼容图片 API 实现文生图与图编辑。

阶段状态（详见 `project-docs/ROADMAP.md`）：

- Phase 1-3 已完成：数据层（CSV）、搜索引擎、CLI 集成
- Phase 4 进行中：4.1 提示词优化器 ✓、4.2 风格混合器 ✓、4.3 批量生成 ✓、4.4 结构化 Brief ✓、4.5 场景化负面提示词 ✓、4.6 请求体 Profile 与参考图 ✓（批次1 完成，批次2 待做）
- Phase 5 GEO 启动：详见 `project-docs/GEO.md`

在新增功能或重构前：

- 先确认是否在 `project-docs/ROADMAP.md` 范围内；超范围必须先与用户讨论
- 不要臆造模块结构；当前架构以 `scripts/` + `data/` + `tests/` 为准
- 不要破坏 `data/*.csv` 已有 schema（见 §5.4）

## 5. 必须遵守的工作底线

### 5.1 单一事实来源（SSoT）

不同信息应只在一处维护，其他位置仅链接或摘要：

| 内容类型 | 真来源 | 桥接位置 |
|---------|--------|---------|
| 项目级 agent 规则 | `.agent-rules/` | `CLAUDE.md` |
| 功能开发进度 | `project-docs/ROADMAP.md` | — |
| GEO 工作执行 | `project-docs/GEO.md` | `project-docs/ROADMAP.md` §Phase 5 摘要 |
| 技能能力描述 | `SKILL.md` | `README.md` / `README_CN.md` 摘要 |
| 风格/模板/配色数据 | `data/*.csv` | — |
| CLI 参数与示例 | `scripts/image_craft.py` 的 `build_parser` | `README*.md` + `SKILL.md` 示例段 |
| 技能结构与触发规范 | `.agent-rules/skill-standards.md` | `SKILL.md` |

发现以上之外的文件描述这些内容时，应消除重复或回链真来源。

### 5.2 中英双语文档同步

`README.md`（英文）与 `README_CN.md`（中文）必须保持内容同步：

- 修改其中一个时必须同步另一个
- 新增章节、示例、参数说明三者必须同时出现
- 翻译可使用 `searchfit-seo:content-translation` 或 `baoyu-translate` 技能辅助

### 5.3 Python ↔ PowerShell 平行实现

`scripts/image_craft.py`（Python，规范实现）与 `scripts/image_craft.ps1`（PowerShell 镜像）必须保持命令行接口平行：

- 新增 / 删除子命令必须双端同步
- 新增 / 删除参数必须双端同步
- 实际提示词增强逻辑由 Python 单点负责（`scripts/prompts_enhancer.py`），PowerShell 通过 shell out 调用，避免双端逻辑漂移
- 修改时优先改 Python，再镜像到 PowerShell

### 5.4 数据 CSV schema 不破坏

修改 `data/styles.csv` / `data/prompts.csv` / `data/colors.csv` 时：

- 不删除已有列
- 新增列必须可选（旧行允许空值，代码不应假设新列存在）
- schema 变更必须同步 `scripts/search.py`（搜索字段权重）和 `scripts/prompts_enhancer.py`（加载逻辑）
- 添加新数据条目（新风格 / 新模板 / 新配色）不算 schema 变更，无需同步代码

### 5.5 测试必须通过

修改 `scripts/prompts_enhancer.py` 或 `scripts/image_craft.py` 时：

- 改动前先运行 `python -m unittest discover tests` 建立基线
- 改动后必须保证已有测试通过
- 行为变更必须新增 / 更新对应测试

### 5.6 配置不入库

`private_config.json`（含 API key 与 base_url）已在 `.gitignore` 中。**禁止以任何方式提交**，包括：

- 不在示例中放入真实 key
- 不在日志、文档、回复中打印 key
- 修改 `.gitignore` 时不删除 `private_config.json` 条目

### 5.7 改动范围手术式

围绕用户请求，不顺手优化无关代码，不引入未要求的灵活性。检验标准：每一行改动可直接追溯到用户的请求。

## 6. 维护

- `.agent-rules/` 内容变化时，不要扩散到 `CLAUDE.md` / `README*.md` 详细描述
- 新增技能集或工作流变化时，更新 [`skills-workflow.md`](./skills-workflow.md)
- 修改技能结构、触发描述或包装方式时，遵守 [`skill-standards.md`](./skill-standards.md)
- agent 预读指项目状态和底线变化时，更新 [`agent-pre-read.md`](./agent-pre-read.md)
- 项目阶段变化时（如完成 Phase 4 或 5），更新本文件 §4
- 项目背景变化时（如换远端、改许可证），更新 [`repo-context.md`](./repo-context.md)
