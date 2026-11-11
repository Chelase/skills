# Image Craft 开发计划

> 参考 ui-ux-pro-max 技能架构，为 image-craft 添加风格系统和提示词库

## 📋 项目愿景

将 image-craft 从简单的 API 调用工具升级为**智能图像生成助手**，内置：
- 预定义艺术风格库
- 提示词模板库
- 色彩方案参考
- 智能推荐系统

---

## 🎯 开发阶段

### Phase 1: 基础数据层 ✅

#### 1.1 创建风格数据库
- [x] 设计 CSV/JSON 数据结构
- [x] 收集并整理艺术风格数据（目标：50+ 种风格）
- [x] 每种风格包含：
  - 风格名称（中英文）
  - 风格描述
  - 关键词标签
  - 示例提示词
  - 适用场景
  - 推荐参数

**风格分类：**
| 类别 | 示例风格 |
|------|----------|
| 传统艺术 | 油画、水彩、素描、版画、国画 |
| 数字艺术 | 像素风、赛博朋克、蒸汽波、故障艺术 |
| 摄影风格 | 胶片、宝丽来、黑白、长曝光、微距 |
| 插画风格 | 扁平、等距、日系、美漫、儿童插画 |
| 3D 渲染 | 低多边形、体素、C4D 风格、Blender 风格 |
| 特殊效果 | 双重曝光、光绘、红外摄影、移轴摄影 |

#### 1.2 创建提示词模板库
- [x] 设计模板数据结构
- [x] 收集常用提示词模式（目标：100+ 模板）
- [x] 模板分类：
  - 场景模板（风景、人物、产品、抽象）
  - 风格修饰词
  - 光影描述词
  - 构图指令
  - 质量增强词

**模板结构示例：**
```json
{
  "id": "portrait-cinematic",
  "name": "电影感人像",
  "category": "portrait",
  "template": "A cinematic portrait of {subject}, {lighting}, {mood}, shot on 35mm film, shallow depth of field, dramatic lighting",
  "variables": ["subject", "lighting", "mood"],
  "examples": [...],
  "tags": ["portrait", "cinematic", "film"]
}
```

#### 1.3 创建色彩方案库
- [x] 设计色彩数据结构
- [x] 收集经典配色方案（目标：30+ 方案）
- [x] 包含内容：
  - 方案名称
  - 主色调/辅助色/强调色
  - 适用场景
  - 情感联想
  - 提示词描述

---

### Phase 2: 搜索引擎 ✅

#### 2.1 Python 搜索脚本
- [x] 创建 `scripts/search.py`
- [x] 实现功能：
  - [x] 按关键词搜索风格
  - [x] 按类别筛选
  - [x] 模糊匹配
  - [x] 随机推荐
  - [x] 组合查询

**命令行接口设计：**
```bash
# 搜索风格
python scripts/search.py "水彩" --domain style

# 搜索提示词模板
python scripts/search.py "人像 电影感" --domain prompt

# 获取随机推荐
python scripts/search.py --random --domain style

# 获取完整设计系统
python scripts/search.py "赛博朋克 未来城市" --design-system
```

#### 2.2 智能推荐
- [x] 基于用户输入推荐风格
- [x] 风格组合建议
- [x] 参数优化建议

---

### Phase 3: 集成与增强 ✅

#### 3.1 更新主脚本
- [x] 在 `image_craft.py` 中集成搜索功能
- [x] 添加 `--style` 参数
- [x] 添加 `--template` 参数
- [x] 添加 `--suggest` 参数

**增强后的命令行：**
```bash
# 使用预定义风格
python scripts/image_craft.py generate --style "赛博朋克" --subject "东京街头"

# 使用提示词模板
python scripts/image_craft.py generate --template "portrait-cinematic" --var subject="女孩" --var lighting="侧光"

# 获取建议
python scripts/image_craft.py suggest "我想画一个未来城市"
```

#### 3.2 更新 SKILL.md
- [x] 添加风格系统文档
- [x] 添加使用示例
- [x] 更新工作流程

#### 3.3 更新 README
- [x] 添加风格库介绍
- [x] 添加提示词库介绍
- [x] 添加搜索功能说明

---

### Phase 4: 高级功能 ⏳

#### 4.1 提示词优化器
- [x] 自动增强简单提示词
- [x] 质量关键词注入
- [x] 负面提示词生成

#### 4.2 风格混合器
- [x] 支持多风格组合
- [x] 风格权重控制
- [x] 风格迁移

#### 4.3 批量生成
- [x] 同一提示词多风格变体
- [x] 风格探索模式
- [x] A/B 测试支持

#### 4.4 结构化 Brief 生成器

> 借鉴结构化提示词方法，把自然语言需求升级为可复用的设计 brief，再转换为专业生图提示词。

- [x] 新增 `brief` 命令，支持只生成结构化 brief，不调用图片 API
- [x] 支持图片 / 产品摄影 / UI 界面 / 视频分镜等 brief 类型（通过 `--brief-type`）
- [x] 支持中文字段输入，如主题、场景、光影、构图、镜头、色调、风格参考、画面比例、禁止项（通过 `--field key=value`）
- [x] 支持 brief 输出为 JSON / Markdown
- [x] 支持 brief → prompt 转换，复用现有风格、模板、配色和提示词增强管线
- [x] 添加结构化 brief 模板库，支持用户按字段填空（`data/briefs.csv`，含 5 个预设模板：产品摄影、UI 界面、视频分镜、人像摄影、风光摄影）

**Brief 示例：**
```yaml
主题: 一杯桂花乌龙茶放在石桌上
场景: 中式庭院，秋天午后
光影: 侧逆光，金色暖光，有光斑穿过树叶
构图: 居中偏下，浅景深，前景落叶虚化
镜头: 85mm, f/2.0
色调: 低饱和暖色，胶片质感
画面比例: 3:4
禁止:
  - 人物出现
  - 过度饱和
  - 任何文字或 logo
```

#### 4.5 场景化负面提示词

> 将"禁止项"从固定质量负面词升级为按场景、风格、用户意图组合的 negative prompt 系统。

- [x] 新增场景级 negative prompt 模板库（`data/negatives.csv`，含 8 个预设：产品摄影、UI 界面、视频分镜、小红书封面、人像摄影、风光摄影、赛博朋克、水彩）
- [x] 支持 `--ban` 参数，由用户追加自定义禁止项（已接入 generate/transform/batch/prompt/brief）
- [x] 合并质量负面词、风格负面词、场景负面词和用户禁止项（`generate_negative_prompt` 统一合并）
- [x] 对 negative prompt 做稳定去重和顺序控制（已有 `unique_terms` 保障）
- [x] 支持 brief 中的"禁止"字段自动进入 negative prompt（`brief_to_prompt` 已修复，原先是追加到 prompt 中错误）
- [x] 增加产品摄影 / UI 界面 / 小红书封面 / 视频分镜等场景负面词预设（`data/negatives.csv`）

#### 4.6 Agent 可读请求体 Profile 与参考图输入

> 不把 API 请求体写死在某个供应商形态上，而是提供 Agent 可读的默认请求体模板、决策规则和可控覆盖机制。

- [x] 在 `SKILL.md` 新增 Request Body Strategy，明确 Agent 默认如何选择请求体 profile
- [x] 定义默认请求体 profiles：`images-generations`、`images-generations-reference`、`chat-completions-vision`、`chat-completions-transform`、`custom`
- [x] 新增 `scripts/payload_builder.py`，负责根据 profile 构造请求体并支持 deep merge override
- [x] 支持 `--profile` 参数，由 Agent 或用户选择请求体模板
- [x] 支持本地参考图 `--image`，自动转 base64 / data URL 后进入默认 profile
- [x] 支持远程参考图 `--image-url`，直接作为 URL 进入默认 profile
- [x] 支持多参考图输入，并保留用途声明：style / composition / subject / palette
- [x] 支持 `--size` 和 `--response-format`，默认适配 Right Codes `/v1/images/generations`
- [x] 支持 `--payload-json` 和 `--payload-merge`，允许 Agent 根据供应商文档合并自定义字段
- [x] 修复 Python 端 `data[0].url` 响应下载能力，与 PowerShell 端保持一致
- [x] 更新 README / README_CN，区分“参考图输入 / 图文输入”和传统 multipart 文件上传

**Agent 默认决策：**
| 用户意图 | 默认 profile | 说明 |
|---|---|---|
| 纯文生图 | `images-generations` | 默认 `/v1/images/generations` |
| 参考图生成 | `images-generations-reference` | 将本地图转 base64 或使用远程 URL 放入 `image` 字段 |
| 图片分析 / 图文理解 | `chat-completions-vision` | 使用 `messages[].content[]` 的 `image_url` URL 结构 |
| 图片转换 / 改图 | `chat-completions-transform` 或供应商文档指定 profile | 文档不明确时由 Agent 告知用户选择 |
| 供应商特殊字段 | `custom` + `--payload-merge` | Agent 根据 API 文档合并自定义字段 |

**Right Codes 默认请求体示例：**
```json
{
  "model": "{model}",
  "prompt": "{enhanced_prompt}",
  "image": "{reference_images}",
  "size": "{size}",
  "response_format": "url",
  "negative_prompt": "{negative_prompt}"
}
```

**Agent 询问用户的边界：**
- API 文档没有说明参考图字段名
- 同一任务存在多个有效请求体形态
- 本地图片必须先转为公网 URL 才能被目标接口接受
- 请求失败且错误明显指向 payload shape
- 用户要求供应商特定高级参数或额外成本操作

#### 4.7 版本与更新检查

> 让 Agent 和用户知道当前技能版本，并在不打断图片生成主流程的前提下提示可用更新。

- [x] 以 `SKILL.md` frontmatter 中的 `version` 字段作为技能版本单一事实来源
- [x] 创建 `project-docs/CHANGELOG.md`，记录版本号、发布日期、关键变更和升级注意事项
- [x] 新增 `scripts/check_update.py`，读取本地版本并查询 GitHub tags / Releases 获取最新版本
- [x] 在 `generate` / `transform` 成功完成后触发更新检查；图片生成任务优先，检查失败不影响主任务退出码
- [x] 只有检测到远端存在新版本时才提示用户；无更新时保持安静输出
- [x] 对更新检查做低频缓存，例如 24 小时内最多检查一次，避免每次生成图片都访问网络
- [x] 默认只提示更新命令，不自动执行 `git pull` 或覆盖本地文件
- [x] 支持关闭更新检查：环境变量 `IMAGE_CRAFT_DISABLE_UPDATE_CHECK=1`，并考虑 CLI 参数 `--no-update-check`
- [ ] PowerShell 端通过 shell out 调用 Python 更新检查脚本，避免双端逻辑漂移
- [ ] 未来发布 CLI 包时，同步规划 `pyproject.toml` / PyPI / `uvx` / `uv tool install`；npm / `npx` 仅作为跨 Node 生态分发选项

**提示原则：**
- 成功生成或编辑图片后再检查更新
- 无新版本不提示，避免干扰用户
- 网络错误、GitHub API 限流或版本解析失败时不报错退出
- 提示中不打印 API key、本地配置内容或用户 prompt 全文

**提示示例：**
```text
Image Craft update available: 1.0.0 -> 1.1.0
Run: git -C ~/.agents/skills/image-craft pull
```

---

### Phase 5: GEO 推广优化 ⏳

> GEO (Generative Engine Optimization) - 针对 AI 搜索引擎的优化策略

#### 5.1 内容结构优化
- [ ] 优化 SKILL.md 为 AI 友好格式
- [ ] 添加清晰的层级结构（H1/H2/H3）
- [ ] 使用语义化标签和列表
- [ ] 添加 FAQ 部分（常见问题解答）
- [ ] 创建知识图谱友好的内容

#### 5.2 关键词策略
- [ ] 研究 AI 搜索热门查询
- [ ] 优化长尾关键词覆盖
- [ ] 添加同义词和变体词
- [ ] 中英文双语关键词优化

**目标关键词：**
| 类型 | 关键词示例 |
|------|-----------|
| 核心词 | AI image generation, image craft, 图片生成 |
| 长尾词 | how to generate cyberpunk images, 赛博朋克图片生成 |
| 问题词 | how to, what is, best way to |
| 比较词 | vs, alternative, best |

#### 5.3 结构化数据
- [ ] 添加 JSON-LD 结构化数据
- [ ] 实现 Schema.org 标记
- [ ] 创建 OpenGraph 元数据
- [ ] 添加 Twitter Card 支持

**结构化数据类型：**
```json
{
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "name": "Image Craft",
  "description": "AI Agent image generation skill",
  "applicationCategory": "DesignApplication",
  "operatingSystem": "Cross-platform"
}
```

#### 5.4 AI 引擎可见性
- [ ] 优化被 ChatGPT/Claude/Gemini 引用的概率
- [ ] 创建权威性内容（教程、指南）
- [ ] 添加引用来源和参考资料
- [ ] 建立知识库链接网络

**优化策略：**
| 策略 | 说明 |
|------|------|
| 权威内容 | 创建详细的技术文档和教程 |
| 引用优化 | 添加来源链接，增加可信度 |
| 问答格式 | 使用 Q&A 结构，匹配 AI 查询 |
| 示例丰富 | 提供大量实际使用示例 |

#### 5.5 社区与分发
- [ ] 创建 GitHub Topics 优化
- [ ] 添加 Awesome List 提交
- [ ] 撰写技术博客文章
- [ ] 社交媒体推广计划

**分发渠道：**
| 渠道 | 内容类型 |
|------|----------|
| GitHub | 代码、文档、示例 |
| Dev.to / Medium | 教程、使用案例 |
| Twitter/X | 技术分享、更新公告 |
| Reddit | 社区讨论、反馈收集 |
| 知乎 / 掘金 | 中文技术文章 |

#### 5.6 监控与分析
- [ ] 设置 AI 搜索监控
- [ ] 跟踪引用来源
- [ ] 分析用户查询模式
- [ ] 优化迭代策略

---

## 📁 目录结构规划

```
image-craft/
├── SKILL.md
├── README.md
├── README_CN.md
├── CLAUDE.md                       # Agent 桥接入口
├── private_config.json.example
├── .gitignore
├── .agent-rules/                   # 项目级 agent 规则真来源
│   ├── README.md
│   ├── skills-workflow.md
│   └── repo-context.md
├── data/                           # 数据库目录
│   ├── styles.csv                  # 风格数据库
│   ├── prompts.csv                 # 提示词模板库
│   ├── colors.csv                  # 色彩方案库
│   ├── briefs.csv                  # 结构化 brief 模板库
│   ├── negatives.csv               # 场景化负面提示词库
│   └── tags.csv                    # 标签索引
├── scripts/
│   ├── image_craft.py              # 主脚本
│   ├── image_craft.ps1             # PowerShell 脚本
│   ├── payload_builder.py          # Agent 可读请求体 profile 构造器
│   ├── check_update.py             # 版本检查与更新提示脚本
│   └── search.py                   # 搜索引擎
├── project-docs/                       # 内部开发规划文档
│   ├── ROADMAP.md                  # 开发计划（本文件）
│   ├── GEO.md                      # GEO 执行手册
│   └── CHANGELOG.md                # 更新日志
├── docs/                               # 公开文档（服务 GEO，被爬虫抓取）
│   ├── faq.md                      # 常见问题（英文）
│   ├── faq_CN.md                   # 常见问题（中文）
│   ├── getting-started.md          # 快速入门
│   ├── styles-guide.md             # 风格指南
│   └── prompt-engineering.md       # 提示词工程
└── examples/                       # 示例目录
    ├── styles/                     # 风格示例图
    └── prompts/                    # 提示词示例
```

---

## 🎨 风格数据库字段设计

| 字段 | 类型 | 说明 |
|------|------|------|
| id | string | 唯一标识符 |
| name_en | string | 英文名称 |
| name_cn | string | 中文名称 |
| category | string | 分类 |
| description | string | 描述 |
| keywords | array | 关键词标签 |
| prompt_template | string | 提示词模板 |
| negative_prompt | string | 负面提示词 |
| example_prompt | string | 示例提示词 |
| recommended_params | object | 推荐参数 |
| use_cases | array | 适用场景 |
| difficulty | string | 难度等级 |
| preview_url | string | 预览图链接 |

---

## 📝 提示词模板字段设计

| 字段 | 类型 | 说明 |
|------|------|------|
| id | string | 唯一标识符 |
| name | string | 模板名称 |
| category | string | 分类 |
| template | string | 模板内容（含变量） |
| variables | array | 变量列表 |
| examples | array | 使用示例 |
| tags | array | 标签 |
| quality_score | int | 质量评分 (1-5) |

---

## 🚀 里程碑

| 阶段 | 目标 | 状态 |
|------|------|------|
| Phase 1 | 基础数据层 | ✅ |
| Phase 2 | 搜索引擎 | ✅ |
| Phase 3 | 集成与增强 | ✅ |
| Phase 4 | 高级功能 | 4.1~4.7 ✅（PowerShell 侧更新检查待做） |
| Phase 5 | GEO 推广优化 | ❌ |

---

## 💡 灵感来源

- [ui-ux-pro-max](https://github.com/...) - 设计系统数据库架构
- Midjourney - 风格和参数系统
- Stable Diffusion WebUI - 提示词和负面提示词
- DALL-E - 提示词最佳实践

---

## 📌 待讨论

1. 风格数据库用 CSV 还是 JSON？
2. 是否需要支持用户自定义风格？
3. 是否需要风格预览图？
4. 搜索结果排序策略？
5. 是否需要支持多语言提示词生成？
