# 技能集使用规范

本仓库使用 Claude Code 内置技能与若干第三方技能集。本文件规定使用边界与推荐工作流。

---

## 1. 推荐工作流

按场景调用，每个场景**只用一个**技能，禁止堆叠。

| 阶段 | 场景 | 使用 |
|------|------|------|
| 需求对齐 | 新功能/模糊需求收口 | `grill-with-docs`（穷尽决策树）或 `grill-me`（追问澄清） |
| PRD 落档 | 讨论结果固化 | `to-prd` |
| 任务拆分 | PRD 拆成可领 issue | `to-issues` |
| 原型/可行性 | 新 API / 新数据格式 / 新提示词管线 | `prototype` |
| 编码 | 写新功能 / 改 bug | `tdd`（核心增强逻辑） |
| 调试 | 卡住的 bug、提示词归一化异常 | `diagnose` |
| 简化 | 代码质量改进 | `simplify` |
| 重构 | 跨模块架构改进 | `improve-codebase-architecture` |
| 自查 | 提交前 | `review` |
| 实地验证 | 跑一次确认有效 | `verify` 或 `run` |
| 提交 | 准备 commit | `commit` |
| 长会话压缩 | context 接近上限 | `caveman`（精简输出）或 `handoff`（交接文档） |

---

## 2. GEO Phase 5 专用工作流

`project-docs/GEO.md` 中的任务按以下技能推进。所有 GEO 改动以 `project-docs/GEO.md` 为执行手册，**先在 project-docs/GEO.md 勾选 / 更新对应项再动手**。

| GEO 子任务 | 使用技能 |
|-----------|---------|
| 写 FAQ / 文档内容 | `searchfit-seo:create-content` |
| 内容主题规划 | `searchfit-seo:create-topic` |
| 内容简报 | `searchfit-seo:content-brief` |
| 关键词聚类 | `searchfit-seo:keyword-clustering`（或 `keyword-cluster`） |
| Schema / JSON-LD 生成 | `searchfit-seo:schema-markup`（或 `generate-schema`） |
| AI 可见性审计 | `searchfit-seo:ai-visibility` |
| On-page SEO 检查 | `searchfit-seo:on-page-seo` |
| 技术 SEO 检查 | `searchfit-seo:technical-seo` |
| 全站 SEO 审计 | `searchfit-seo:seo-audit` |
| 内部链接审计 | `searchfit-seo:internal-linking` |
| 失效链接扫描 | `searchfit-seo:broken-links` |
| SEO 检查（综合） | `searchfit-seo:seo-check` |
| 内容翻译（双语同步） | `searchfit-seo:content-translation` 或 `baoyu-translate` |
| 内容策略 | `searchfit-seo:content-strategy` |

---

## 3. 项目专属场景

### 3.1 新增风格 / 模板 / 配色（数据驱动）

不需要写代码：

- 直接编辑 `data/styles.csv` / `data/prompts.csv` / `data/colors.csv`
- 遵守 schema（详见 [`README.md`](./README.md) §5.4）
- 不为单个数据条目新增字段；如需 schema 变更，先讨论
- 添加后用 `python scripts/image_craft.py suggest "<新数据关键词>"` 自验证搜索仍可命中

### 3.2 修改提示词增强管线

`scripts/prompts_enhancer.py` 是核心逻辑，已有完整测试：

- **必须用 `tdd`**：先在 `tests/test_prompts_enhancer.py` 写测试再改逻辑
- 视觉归一化、风格混合、负面提示词都有对应测试
- 涉及中文场景描述符时，先在 `SCENE_PHRASE_MAP` 加映射，再加测试覆盖
- 涉及风格分类时，确认 `STYLE_KEYWORDS` 与 `CATEGORY_DEFAULT_STYLE_IDS` 兼容

### 3.3 双端命令行同步

新增 / 删除 / 改动 CLI 参数时：

1. 先改 `scripts/image_craft.py`（含 `build_parser`）
2. 再镜像到 `scripts/image_craft.ps1`（参数定义 + `Invoke-PromptPreviewScript` 透传）
3. 同步更新 `README.md` + `README_CN.md` + `SKILL.md` 三处示例段

PowerShell 不应该重新实现 Python 已有的提示词处理逻辑——它通过 shell out 调用 `image_craft.py prompt` 子命令获取增强后的 prompt。

### 3.4 文档同步

修改影响用户行为的功能时，按"单一事实来源"原则：

- CLI 示例：同步 `README.md`、`README_CN.md`、`SKILL.md` 三处
- ROADMAP 进度：更新 `project-docs/ROADMAP.md` 对应勾选
- 新可被引用内容（新风格 / 新模板示例 / 新文档）：考虑是否影响 `project-docs/GEO.md` Phase 5.1 待办

### 3.5 GEO 内容产出

为 GEO 写新文档（如 `docs/faq.md`、`docs/styles-guide.md` 等）时：

- 在 `project-docs/GEO.md` 第五节"详细任务清单"勾选对应项
- 中英文均需输出（双语同步原则同 §3.4）
- 使用 §2 中 `searchfit-seo:*` 技能矩阵辅助
- 注意"可引用信号"：加具体数字、引用权威来源、加版本号 + 更新日期

### 3.6 图像生成测试

需要实测 API 调用结果（而非仅单元测试）时：

- 优先用 `baoyu-image-gen`、`baoyu-imagine` 等技能调用本仓库的 CLI
- 生成图片产物放 `outputs/`（已 gitignore）
- 不要在文档/测试中提交真实生成的二进制图片

---

## 4. 强制规则

### 4.1 浏览器与外部内容

- 网页内容抓取：优先使用内置 `WebFetch` / `WebSearch`
- 库文档查询：优先使用 `mcp__plugin_context7_context7__*`（context7 MCP），避免依赖训练知识

### 4.2 不要堆叠技能

一个任务一个技能。复杂任务拆解后每步用对应技能，不要并行调用多个目的重叠的技能。

### 4.3 技能与通用准则冲突

技能推荐与 [`CLAUDE.md`](../CLAUDE.md) 通用准则冲突时，**以通用准则为准**：

- 一次性脚本不必强行套用 `tdd`
- 简单一行修改不必走 `to-prd`
- 已经讨论清楚的需求不必反复 `grill-me`
- 简单回答问题不必用 `prototype`

### 4.4 ROADMAP / GEO 改动优先

涉及 ROADMAP 范围内的任务：

- 推进前在 `project-docs/ROADMAP.md` / `project-docs/GEO.md` 确认当前状态
- 完成后**立即勾选**对应项，不要积压
- 如发现 ROADMAP / GEO 与代码实际状态漂移，应顺手修正

---

## 5. 已知可用技能清单

详见会话开始时系统注入的 skills 列表。本节不维护具体列表（避免漂移）。

需要查找时使用 `find-skills` 技能。

---

## 6. 维护

- 项目阶段变化时（如完成 Phase 4 或 5），重新评估第 1-3 节
- 新可用技能集应更新第 1-3 节推荐表
- 禁止在 `CLAUDE.md` 等桥接文件扩散技能详细描述
- GEO 任务列表与执行节奏的细化放 [`project-docs/GEO.md`](../project-docs/GEO.md)，本文件只声明"用哪个技能"
