# Image Craft 常见问题

> 关于 **Image Craft** 的常见问题解答 —— 一个通过 OpenAI 兼容图片 API（`gpt-image-2-5-flare`、OpenAI、Azure OpenAI、Right Codes）调用图像生成的通用 AI Agent 技能。
>
> **最后更新：** 2026-05-26 · **版本：** 1.0.0 · **仓库：** <https://github.com/Chelase/skills> · **English version:** [faq.md](./faq.md)

## 目录

**入门**
- [1. Image Craft 是什么？能做什么？](#1-image-craft-是什么能做什么)
- [2. Image Craft 适合谁用？什么场景？](#2-image-craft-适合谁用什么场景)

**安装与配置**
- [3. 如何安装 Image Craft（Claude Code / OpenCode / 其他 Agent）？](#3-如何安装-image-craftclaude-code--opencode--其他-agent)
- [4. 如何配置 API key 和 base URL？三种方式哪个优先？](#4-如何配置-api-key-和-base-url三种方式哪个优先)
- [5. Image Craft 支持哪些 OpenAI 兼容 API？](#5-image-craft-支持哪些-openai-兼容-api)
- [6. 没有 API key 也能用吗？哪些功能能离线运行？](#6-没有-api-key-也能用吗哪些功能能离线运行)

**核心功能**
- [7. 如何用 Image Craft 生成赛博朋克风格的图片？](#7-如何用-image-craft-生成赛博朋克风格的图片)
- [8. 如何用参考图引导生成（本地图 / 远程 URL）？](#8-如何用参考图引导生成本地图--远程-url)
- [9. 如何用一个 prompt 批量生成多风格变体（A/B 测试）？](#9-如何用一个-prompt-批量生成多风格变体ab-测试)
- [10. 什么是 brief 模式？什么时候用？](#10-什么是-brief-模式什么时候用)

**数据库**
- [11. 内置的 54 种风格有哪些？如何浏览和挑选？](#11-内置的-54-种风格有哪些如何浏览和挑选)
- [12. 119 个提示词模板怎么用？如何带变量填空？](#12-119-个提示词模板怎么用如何带变量填空)
- [13. 50 种配色方案如何套用到生成的图片？](#13-50-种配色方案如何套用到生成的图片)

**故障排查与进阶**
- [14. 生成的图片质量不好怎么办？](#14-生成的图片质量不好怎么办)
- [15. API 调用失败 / 超时如何处理？](#15-api-调用失败--超时如何处理)
- [16. 如何自定义请求体（供应商特殊字段 / 高级参数）？](#16-如何自定义请求体供应商特殊字段--高级参数)

---

## 入门

### 1. Image Craft 是什么？能做什么？

**Image Craft** 是一个开源的 AI Agent 技能，通过调用 OpenAI 兼容的图片生成 API 把文本提示词变成图片。它以 Python CLI（带 PowerShell 镜像）形式发布，内置三个本地数据库：**54 种艺术风格**、**119 个提示词模板**、**50 种配色方案**。

技能提供六个子命令：

```bash
python scripts/image_craft.py generate    # 文生图
python scripts/image_craft.py transform   # 图片 + 文本 → 新图
python scripts/image_craft.py batch       # 一个 prompt → N 个风格变体
python scripts/image_craft.py brief       # 结构化设计简报 → 提示词
python scripts/image_craft.py suggest     # 风格 / 提示词 / 配色推荐
python scripts/image_craft.py prompt      # 预览增强后的提示词（不调用 API）
```

兼容 OpenAI 协议：支持 `gpt-image-2-5-flare`、OpenAI 官方图片 API、Azure OpenAI、Right Codes（默认端点 `https://right.codes/draw`）。完整能力请见 [SKILL.md](../SKILL.md)。

### 2. Image Craft 适合谁用？什么场景？

Image Craft 面向 **AI Agent 和 CLI 用户**，无需手写 API 请求体即可生图。典型场景：

- **Claude Code / OpenCode 用户**：把技能放进 `~/.agents/skills/image-craft`，Agent 自动识别"画一张 X"或"生成一张图"等触发语。
- **CLI 与脚本工作流**：在 shell 脚本、cron 任务、构建管线中集成 `python scripts/image_craft.py generate`。
- **内容创作者**：用 brief 模式和 119 个提示词模板生成博客封面、社交媒体配图、产品摄影等需要一致性的图。
- **基于 `gpt-image-2-5-flare` 做原型的开发者**：先用离线的 `suggest` 和 `prompt` 子命令探索风格和提示词，再花 API 额度。

它**不是**桌面 GUI 或网页应用。要那种的话请用 Midjourney、DALL-E 或 ComfyUI。

## 安装与配置

### 3. 如何安装 Image Craft（Claude Code / OpenCode / 其他 Agent）？

把仓库克隆到 Agent 的 skills 目录：

```bash
git clone https://github.com/Chelase/skills.git ~/.agents/skills/skills
```

**Claude Code**：放在 `~/.claude/skills/image-craft/` 或任何 Claude Code 会扫描的路径。技能通过 `SKILL.md` 的 frontmatter 触发描述被自动识别。

**OpenCode**：克隆到 `~/.agents/skills/image-craft` 即可开箱可用。

**其他 AI Agent**：把 `SKILL.md` 内容拷进 Agent 的技能系统，并确保 `scripts/` 目录对 Agent 的工具执行器可见。技能是自包含的 —— 除标准库和 `requests` 外不依赖外部 Python 包。

然后配置 API（见 [Q4](#4-如何配置-api-key-和-base-url三种方式哪个优先)）。

### 4. 如何配置 API key 和 base URL？三种方式哪个优先？

Image Craft 从**三个来源**读取配置，优先级如下：

```
CLI 参数  >  IMAGE_CRAFT_* 环境变量  >  private_config.json  >  内置默认值
```

**方式 1 — `private_config.json`**（推荐用于稳定的本地配置）：

```json
{
  "api_key": "YOUR_API_KEY_HERE",
  "base_url": "https://right.codes/draw"
}
```

放在技能根目录。文件已被 gitignore —— **绝不要提交到 git**。

**方式 2 — 环境变量**（推荐用于 CI/CD）：

```bash
export IMAGE_CRAFT_API_KEY="sk-..."
export IMAGE_CRAFT_BASE_URL="https://right.codes/draw"
```

**方式 3 — CLI 参数**（覆盖一切；适合临时测试）：

```bash
python scripts/image_craft.py generate \
  --prompt "..." \
  --output out.png \
  --api-key sk-... \
  --base-url https://right.codes/draw
```

默认值：`base_url = https://right.codes/draw`、`model = gpt-image-2-5-flare`。

### 5. Image Craft 支持哪些 OpenAI 兼容 API？

任何符合 **OpenAI 图片生成或 chat completions 协议**的 API 都能用。已验证兼容：

- **Right Codes**（`https://right.codes/draw`）—— 默认端点，支持 `gpt-image-2-5-flare` 和 `gpt-image-2-5-sunburst`
- **OpenAI 官方**（`https://api.openai.com/v1`）—— DALL-E 2/3、`gpt-image-1`
- **Azure OpenAI** —— 把 `base_url` 设为你的 Azure 部署 URL
- **其他供应商** —— 任何实现 `POST /v1/images/generations` 或 `POST /v1/chat/completions` 的端点

Image Craft 用 **5 个请求体 profile** 处理供应商之间的细微差异：

| Profile | 端点 | 用途 |
|---|---|---|
| `images-generations` | `/v1/images/generations` | 纯文生图，无参考图 |
| `images-generations-reference` | `/v1/images/generations` | 文生图 + 参考图 |
| `chat-completions-vision` | `/v1/chat/completions` | 图片分析 / 视觉理解 |
| `chat-completions-transform` | `/v1/chat/completions` | 编辑 / 改图 |
| `custom` | （用户指定） | 完全自定义请求体 |

Profile 由输入参数自动识别；用 `--profile` 显式覆盖，或用 `--payload-merge` 注入供应商特殊字段。详见 [Q16](#16-如何自定义请求体供应商特殊字段--高级参数)。

### 6. 没有 API key 也能用吗？哪些功能能离线运行？

可以 —— Image Craft 有几个功能**完全离线**就能用：

- `suggest` —— 基于本地 CSV 库推荐风格、提示词、配色
- `prompt` —— 预览**即将**发给 API 的增强后提示词
- `brief` —— 本地生成结构化设计简报

```bash
# 浏览"赛博朋克东京街头"的风格推荐 —— 不调用 API
python scripts/image_craft.py suggest "赛博朋克东京街头" --domain style

# 花 API 额度前先预览增强后的提示词
python scripts/image_craft.py prompt --prompt "cat" --style-name cyberpunk --negative

# 离线生成 JSON 简报
python scripts/image_craft.py brief \
  --template product-photography \
  --field 主题="球鞋"
```

只有 `generate`、`transform`、`batch` 真的会调用图片 API，其余三个子命令是对本地 CSV 库的纯本地计算。

## 核心功能

### 7. 如何用 Image Craft 生成赛博朋克风格的图片？

用 `--style-name cyberpunk`（或 `--style-id cyberpunk`）应用预设的赛博朋克风格：

```bash
python scripts/image_craft.py generate \
  --prompt "东京街头夜景" \
  --style-name cyberpunk \
  --negative \
  --scene cyberpunk \
  --output outputs/tokyo.png
```

Image Craft 会自动：

1. 注入赛博朋克专属的**提示词模板**关键词（neon、futuristic、holographic 等）
2. 加入**质量增强词**（`masterpiece, intricate detail, 4K`）
3. 构建**负面提示词**，合并赛博朋克场景级避免项（过度饱和霓虹、滥用色差）和通用质量避免项

赛博朋克是 **54 种内置风格**之一，分布在 8 大类别。要在不花 API 额度的情况下预览增强后的提示词：

```bash
python scripts/image_craft.py prompt \
  --prompt "东京街头" \
  --style-name cyberpunk \
  --negative
```

也可以做带权重的风格混合：

```bash
--style-mix "cyberpunk:0.7,blender-render:0.3"
```

### 8. 如何用参考图引导生成（本地图 / 远程 URL）？

用 `--image` 传本地文件，`--image-url` 传远程 URL。两个参数都可重复传入实现多图参考：

```bash
# 本地参考图（自动转 base64）
python scripts/image_craft.py generate \
  --prompt "保持构图但改成水彩风格" \
  --image ./refs/photo.jpg \
  --output outputs/watercolor.png

# 远程 URL 参考图
python scripts/image_craft.py generate \
  --prompt "同一主体改成赛博朋克风格" \
  --image-url "https://example.com/photo.jpg" \
  --output outputs/cyberpunk.png

# 多参考图带用途声明
python scripts/image_craft.py generate \
  --prompt "..." \
  --image "./style.jpg::style" \
  --image "./composition.jpg::composition" \
  --output outputs/result.png
```

提供参考图时，Image Craft 会自动选择 `images-generations-reference` profile 并按规则构造请求体。支持的用途：`style`、`composition`、`subject`、`palette`（声明性 —— 具体如何解释参考图由底层 API 决定）。

### 9. 如何用一个 prompt 批量生成多风格变体（A/B 测试）？

用 `batch` 子命令，可选显式 `--styles` 或自动推荐 `--explore`：

```bash
# 显式风格 —— 同一 prompt 出 3 个变体
python scripts/image_craft.py batch \
  --prompt "桂花乌龙茶 中式庭院" \
  --styles "watercolor,cyberpunk,blender-render" \
  --output-dir outputs/tea-experiment/

# 自动探索：Image Craft 用本地搜索挑 3 个风格
python scripts/image_craft.py batch \
  --prompt "桂花乌龙茶 中式庭院" \
  --explore --limit 3 \
  --output-dir outputs/tea-experiment/

# 预演（不花 API 额度）
python scripts/image_craft.py batch \
  --prompt "..." \
  --styles "cyberpunk,watercolor" \
  --output-dir outputs/test/ \
  --dry-run

# A/B 标签便于后续对比
python scripts/image_craft.py batch \
  --prompt "..." \
  --styles "v1,v2" \
  --ab-label control \
  --ab-label experiment \
  --output-dir outputs/ab-test/
```

`--variants N` 参数控制每个风格生成 N 张（默认 1）。配合 `--styles "a,b,c" --variants 2` 就是 6 张图。先用 `--dry-run` 验证计划再正式调 API。

### 10. 什么是 brief 模式？什么时候用？

**Brief（设计简报）模式**把结构化的设计规格（主题、场景、光影、构图、镜头、色调、画面比例、禁止项）转成专业图片提示词。**当一致性比即兴更重要时使用** —— 比如产品摄影、UI 设计、视频分镜、人像或风光系列。

```bash
# 离线生成 JSON 简报
python scripts/image_craft.py brief \
  --brief-type photo \
  --field 主题="一杯桂花乌龙茶" \
  --field 场景="中式庭院，秋天午后" \
  --field 光影="侧逆光，金色暖光" \
  --field 镜头="85mm, f/2.0" \
  --field 画面比例="3:4" \
  --field 禁止="人物出现, 过度饱和"

# 简报 → 增强提示词 → 预览（仍不调 API）
python scripts/image_craft.py brief \
  --template product-photography \
  --field 主题="球鞋" \
  --field 背景="大理石桌面" \
  --to-prompt \
  --style-name product-photography \
  --negative \
  -f markdown
```

`data/briefs.csv` 内置 5 套简报模板：

| 模板 | 必填字段 |
|---|---|
| `product-photography`（产品摄影） | 主题, 背景 |
| `ui-interface`（UI 界面） | 应用类型, 设计风格 |
| `video-storyboard`（视频分镜） | 场景描述, 运镜 |
| `portrait`（人像摄影） | 主题 |
| `landscape`（风光摄影） | 场景 |

简报里的 `禁止` 字段会自动并入负面提示词，而不是被错误地追加到正面提示词中。

## 数据库

### 11. 内置的 54 种风格有哪些？如何浏览和挑选？

54 种风格分布在 **8 大类别**：

| 类别 | 数量 | 示例 |
|---|---|---|
| 传统艺术 | 5 | oil-painting、watercolor、chinese-painting、sketch、woodblock |
| 数字艺术 | 4 | cyberpunk、vaporwave、pixel-art、glitch |
| 摄影 | 5 | film、polaroid、black-white、long-exposure、macro |
| 插画 | 5 | flat-design、isometric、japanese-anime、american-comic、children |
| 3D 渲染 | 4 | low-poly、voxel、c4d-render、blender-render |
| 特殊效果 | 4 | double-exposure、light-painting、infrared、tilt-shift |
| 通用 / 跨类别 | 27 | （多样 —— 用搜索发现） |

按关键词、类别、或随机浏览：

```bash
# 关键词搜索
python scripts/image_craft.py suggest "水彩" --domain style --limit 20

# 类别过滤（在 batch explore 模式下）
python scripts/image_craft.py batch \
  --prompt "..." --explore --category digital --output-dir outputs/

# 随机推荐
python scripts/image_craft.py suggest "" --domain style --random --limit 5

# 完整设计系统：风格 + 提示词 + 配色
python scripts/image_craft.py suggest "赛博朋克 未来城市" --design-system
```

`data/styles.csv` 中每行风格有 11 个字段：`id`、`name_en`、`name_cn`、`category`、`description`、`keywords`、`prompt_template`、`negative_prompt`、`example_prompt`、`use_cases`、`difficulty`。搜索会按全部字段加权排序，支持中文 CJK 分词和模糊匹配。

### 12. 119 个提示词模板怎么用？如何带变量填空？

提示词模板存在 `data/prompts.csv`，含 `{subject}`、`{lighting}`、`{mood}` 等占位符。用 `--template <id|name|query>` 应用模板，用可重复的 `--var key=value` 填值：

```bash
# 电影感人像模板
python scripts/image_craft.py generate \
  --template portrait-cinematic \
  --var subject="商务女性" \
  --var lighting="侧光" \
  --var mood="沉思" \
  --output outputs/portrait.png

# 按关键词搜索模板再填值
python scripts/image_craft.py suggest "电影感人像" --domain prompt
python scripts/image_craft.py generate \
  --template "电影感人像" \
  --var subject="..." \
  --output outputs/result.png

# 预览渲染后的模板（不调 API）
python scripts/image_craft.py prompt \
  --prompt "..." \
  --template portrait-cinematic \
  --var subject="..." \
  --var lighting="..."
```

模板搜索覆盖 `name`、`category`、`tags`、`template` 正文。每个模板有 `quality` 评分（1-5），帮你挑高质量的。`prompt` 子命令可预览渲染后的模板而不调 API。

### 13. 50 种配色方案如何套用到生成的图片？

用 `--color <name|query>` 把配色的提示词描述附加到主提示词上：

```bash
# 按配色名（中英文都行）
python scripts/image_craft.py generate \
  --prompt "东京夜景" \
  --color "neon-cyberpunk" \
  --output outputs/tokyo.png

# 按中文关键词
python scripts/image_craft.py generate \
  --prompt "宁静的湖面" \
  --color "莫兰迪" \
  --output outputs/lake.png

# 配色 + 风格组合
python scripts/image_craft.py generate \
  --prompt "古风少女" \
  --style-name chinese-painting \
  --color "敦煌" \
  --output outputs/girl.png
```

`data/colors.csv` 中每个配色有主色 / 辅色 / 强调色，以及一个 `prompt_description` 字段（如 "muted earth tones, soft gradients, low saturation, vintage feel"）。浏览：

```bash
python scripts/image_craft.py suggest "复古" --domain color --limit 5
python scripts/image_craft.py suggest "" --domain color --random
```

## 故障排查与进阶

### 14. 生成的图片质量不好怎么办？

图片质量问题通常分三类。按顺序排查：

**1. 增强提示词** —— 让 Image Craft 注入质量词和负面提示词：

```bash
python scripts/image_craft.py generate \
  --prompt "..." \
  --negative \                       # 加入质量相关的负面提示词
  --scene product-photography \      # 加入场景级负面词
  --output out.png
```

**2. 加风格或模板** —— 稀疏的提示词产生稀疏的图：

```bash
# 风格给视觉身份 + 精选的负面词
--style-name product-photography

# 模板给结构化关键词
--template "电影感人像" --var subject="..." --var lighting="..."
```

**3. 针对已知缺陷加自定义禁止项**：

```bash
--ban "extra fingers, lowres, watermark, text artifacts"
```

如果质量还是差，可能模型本身是瓶颈。试试用 `--model gpt-image-2-5-sunburst` 替换 `gpt-image-2-5-flare`，或者换供应商（见 [Q5](#5-image-craft-支持哪些-openai-兼容-api)）。`data/negatives.csv` 内置 8 套场景级负面提示词（product、UI、video、xiaohongshu、portrait、landscape、cyberpunk、watercolor）—— 用 `--scene <name>` 激活。

### 15. API 调用失败 / 超时如何处理？

常见失败模式与处理方式：

**HTTP 401 / 403 —— 认证失败**
- 确认 `private_config.json` 中 `api_key` 正确
- 在供应商的控制台核对 key 是否有效
- 用环境变量的话执行 `echo $IMAGE_CRAFT_API_KEY` 验证值

**HTTP 429 —— 限流**
- 多数供应商限制每分钟请求次数；等一会儿再重试
- 批量生成时降低 `--variants` 或拆成小批
- 先用 `--dry-run` 验证计划再消耗额度

**HTTP 5xx / 超时 —— 服务端或网络问题**
- 验证 `base_url` 是否可达：`curl -I https://right.codes/draw`
- 试更小的图片尺寸（`--size 512x512`）排除请求体过大问题
- 临时切换到另一个供应商

**HTTP 400 —— 请求体形态错误**
- 供应商可能要求非标准字段。用 `--payload-merge '{"field":"value"}'` 加自定义字段，或用 `--profile custom` 配合 `--payload-json '<完整 JSON>'`。详见 [Q16](#16-如何自定义请求体供应商特殊字段--高级参数)。

调试时可加 `--profile <显式 profile>` 把自动识别从问题链路中排除，定位具体故障点。

### 16. 如何自定义请求体（供应商特殊字段 / 高级参数）？

Image Craft 提供**两个层级**的请求体自定义：

**层级 1 —— 合并到自动构造的请求体**（推荐用于加 1-2 个供应商字段）：

```bash
python scripts/image_craft.py generate \
  --prompt "..." \
  --output out.png \
  --payload-merge '{"quality":"hd","style":"vivid","user":"my-app-id"}'
```

合并是深度合并 —— 嵌套字段会被合并而非替换。

**层级 2 —— 完全替换请求体**（用于完全自定义的形态）：

```bash
python scripts/image_craft.py generate \
  --prompt "..." \
  --output out.png \
  --profile custom \
  --payload-json '{
    "model": "gpt-image-2-5-flare",
    "prompt": "Tokyo street",
    "size": "1024x1024",
    "supplier_param": "value",
    "response_format": "url"
  }'
```

**Profile 选择速查：**

| 用户意图 | Profile | 端点 |
|---|---|---|
| 纯文生图，无参考图 | `images-generations` | `/v1/images/generations` |
| 文生图 + 参考图 | `images-generations-reference` | `/v1/images/generations` |
| 图片分析 / 视觉理解 | `chat-completions-vision` | `/v1/chat/completions` |
| 编辑 / 改图 | `chat-completions-transform` | `/v1/chat/completions` |
| 完全自定义 | `custom` | （用户通过 `--payload-json` 指定） |

供应商文档未明确说明请求体形态时，Agent 应询问用户选哪个 profile。Profile 的标准定义见 `scripts/payload_builder.py`。

---

## 延伸阅读

- [SKILL.md](../SKILL.md) —— 完整技能元数据与能力描述
- [README.md](../README.md) / [README_CN.md](../README_CN.md) —— 项目概览与安装
- [ROADMAP.md](./ROADMAP.md) —— 开发路线图
- [GEO.md](./GEO.md) —— 生成式引擎优化策略
- [data/styles.csv](../data/styles.csv) —— 风格库（54 条）
- [data/prompts.csv](../data/prompts.csv) —— 提示词模板库（119 条）
- [data/colors.csv](../data/colors.csv) —— 配色方案库（50 条）
- [data/briefs.csv](../data/briefs.csv) —— 设计简报模板库（5 条）
- [data/negatives.csv](../data/negatives.csv) —— 场景负面提示词库（8 条）

---

*发现错误或缺失场景？[提交 Issue](https://github.com/Chelase/skills/issues)。*
