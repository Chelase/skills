# Image Craft FAQ

> Frequently asked questions about **Image Craft** — the universal AI Agent skill for image generation through OpenAI-compatible APIs (`gpt-image-2-5-flare`, OpenAI, Azure OpenAI, Right Codes).
>
> **Last updated:** 2026-05-26 · **Version:** 1.0.0 · **Repository:** <https://github.com/Chelase/image-craft> · **Chinese version:** [faq_CN.md](./faq_CN.md)

## Contents

**Getting Started**
- [1. What is Image Craft and what can it do?](#1-what-is-image-craft-and-what-can-it-do)
- [2. Who is Image Craft for? What scenarios does it fit?](#2-who-is-image-craft-for-what-scenarios-does-it-fit)

**Installation & Configuration**
- [3. How do I install Image Craft for Claude Code, OpenCode, or other agents?](#3-how-do-i-install-image-craft-for-claude-code-opencode-or-other-agents)
- [4. How do I configure the API key and base URL? Which method takes priority?](#4-how-do-i-configure-the-api-key-and-base-url-which-method-takes-priority)
- [5. Which OpenAI-compatible APIs does Image Craft support?](#5-which-openai-compatible-apis-does-image-craft-support)
- [6. Can I use Image Craft without an API key? Which features work offline?](#6-can-i-use-image-craft-without-an-api-key-which-features-work-offline)

**Core Features**
- [7. How do I generate a cyberpunk-style image with Image Craft?](#7-how-do-i-generate-a-cyberpunk-style-image-with-image-craft)
- [8. How do I use a reference image to guide generation (local file or remote URL)?](#8-how-do-i-use-a-reference-image-to-guide-generation-local-file-or-remote-url)
- [9. How do I batch-generate multi-style variants from one prompt (A/B testing)?](#9-how-do-i-batch-generate-multi-style-variants-from-one-prompt-ab-testing)
- [10. What is brief mode and when should I use it?](#10-what-is-brief-mode-and-when-should-i-use-it)

**Data Library**
- [11. What are the 54 built-in art styles? How do I browse and pick one?](#11-what-are-the-54-built-in-art-styles-how-do-i-browse-and-pick-one)
- [12. How do I use the 119 prompt templates with variable filling?](#12-how-do-i-use-the-119-prompt-templates-with-variable-filling)
- [13. How do I apply the 50 color palettes to generated images?](#13-how-do-i-apply-the-50-color-palettes-to-generated-images)

**Troubleshooting & Advanced**
- [14. What can I do if the generated image quality is poor?](#14-what-can-i-do-if-the-generated-image-quality-is-poor)
- [15. How do I handle API call failures or timeouts?](#15-how-do-i-handle-api-call-failures-or-timeouts)
- [16. How do I customize the request body for supplier-specific fields?](#16-how-do-i-customize-the-request-body-for-supplier-specific-fields)

---

## Getting Started

### 1. What is Image Craft and what can it do?

**Image Craft** is an open-source AI Agent skill that turns text prompts into images by calling OpenAI-compatible image generation APIs. It ships as a Python CLI (with a PowerShell mirror) bundled with three local libraries: **54 art styles**, **119 prompt templates**, and **50 color palettes**.

The skill exposes six subcommands:

```bash
python scripts/image_craft.py generate    # text → image
python scripts/image_craft.py transform   # image + text → new image
python scripts/image_craft.py batch       # one prompt → N style variants
python scripts/image_craft.py brief       # structured design brief → prompt
python scripts/image_craft.py suggest     # style/prompt/color recommendations
python scripts/image_craft.py prompt      # preview enhanced prompt (no API call)
```

It is OpenAI-compatible: works with `gpt-image-2-5-flare`, OpenAI's official image API, Azure OpenAI, and Right Codes (`https://right.codes/draw` is the default endpoint). See [SKILL.md](../SKILL.md) for the full capability surface.

### 2. Who is Image Craft for? What scenarios does it fit?

Image Craft is designed for **AI agents and CLI users** who need image generation without writing API payload code by hand. Typical scenarios:

- **Claude Code / OpenCode users**: drop the skill into `~/.agents/skills/image-craft` and the agent picks it up automatically when the user says "draw me X" or "生成一张图".
- **CLI and script workflows**: integrate `python scripts/image_craft.py generate` into shell scripts, cron jobs, or build pipelines.
- **Content creators**: use brief mode and the 119 prompt templates to produce consistent images for blogs, social media, or product photography.
- **Developers prototyping with `gpt-image-2-5-flare`**: explore styles and prompts locally with the offline `suggest` and `prompt` subcommands before committing to a payload shape.

It is **not** a desktop GUI or web app. For those, see Midjourney, DALL-E, or ComfyUI.

## Installation & Configuration

### 3. How do I install Image Craft for Claude Code, OpenCode, or other agents?

Clone the repository into your agent's skills directory:

```bash
git clone https://github.com/Chelase/image-craft.git ~/.agents/skills/image-craft
```

**For Claude Code**: place under `~/.claude/skills/image-craft/` or any path Claude Code scans. The skill is auto-discovered through `SKILL.md`'s frontmatter trigger description.

**For OpenCode**: the clone path `~/.agents/skills/image-craft` works out of the box.

**For other AI agents**: copy the `SKILL.md` content into your agent's skill system and ensure the `scripts/` directory is accessible to the agent's tool runner. The skill is self-contained — no external Python packages beyond the standard library and `requests`.

Then configure the API (see [Q4](#4-how-do-i-configure-the-api-key-and-base-url-which-method-takes-priority)).

### 4. How do I configure the API key and base URL? Which method takes priority?

Image Craft reads configuration from **three sources** with the following priority:

```
CLI flags  >  IMAGE_CRAFT_* env vars  >  private_config.json  >  built-in defaults
```

**Method 1 — `private_config.json`** (recommended for stable local setups):

```json
{
  "api_key": "YOUR_API_KEY_HERE",
  "base_url": "https://right.codes/draw"
}
```

Place this at the skill root. The file is gitignored — never commit it.

**Method 2 — environment variables** (recommended for CI/CD):

```bash
export IMAGE_CRAFT_API_KEY="sk-..."
export IMAGE_CRAFT_BASE_URL="https://right.codes/draw"
```

**Method 3 — CLI flags** (overrides everything; useful for one-off testing):

```bash
python scripts/image_craft.py generate \
  --prompt "..." \
  --output out.png \
  --api-key sk-... \
  --base-url https://right.codes/draw
```

Defaults: `base_url = https://right.codes/draw`, `model = gpt-image-2-5-flare`.

### 5. Which OpenAI-compatible APIs does Image Craft support?

Any API that conforms to the **OpenAI image generation or chat completions schema** works. Verified compatible:

- **Right Codes** (`https://right.codes/draw`) — default endpoint, supports `gpt-image-2-5-flare` and `gpt-image-2-5-sunburst`
- **OpenAI official** (`https://api.openai.com/v1`) — DALL-E 2/3, `gpt-image-1`
- **Azure OpenAI** — set `base_url` to your Azure deployment URL
- **Other providers** — anything implementing `POST /v1/images/generations` or `POST /v1/chat/completions` with image-capable models

Image Craft uses **5 request body profiles** to handle minor payload differences between providers:

| Profile | Endpoint | Use case |
|---|---|---|
| `images-generations` | `/v1/images/generations` | Text-to-image, no reference |
| `images-generations-reference` | `/v1/images/generations` | Text-to-image with reference image |
| `chat-completions-vision` | `/v1/chat/completions` | Image analysis / vision tasks |
| `chat-completions-transform` | `/v1/chat/completions` | Edit / transform existing image |
| `custom` | (user-specified) | Fully custom payload |

The profile is auto-detected from your inputs; use `--profile` to override or `--payload-merge` to inject supplier-specific fields. See [Q16](#16-how-do-i-customize-the-request-body-for-supplier-specific-fields).

### 6. Can I use Image Craft without an API key? Which features work offline?

Yes — several Image Craft features work **fully offline** without an API key:

- `suggest` — recommend styles, prompts, and colors from local CSV libraries
- `prompt` — preview the enhanced prompt that *would* be sent to the API
- `brief` (without the API-calling flow) — generate a structured design brief locally

```bash
# Browse style recommendations for "cyberpunk Tokyo street" — no API call
python scripts/image_craft.py suggest "cyberpunk Tokyo street" --domain style

# Preview the enhanced prompt before spending API credits
python scripts/image_craft.py prompt --prompt "cat" --style-name cyberpunk --negative

# Generate a JSON brief offline
python scripts/image_craft.py brief \
  --template product-photography \
  --field 主题="球鞋"
```

Only `generate`, `transform`, and `batch` actually call the image API. The other three subcommands are pure local computation against the bundled CSV libraries.

## Core Features

### 7. How do I generate a cyberpunk-style image with Image Craft?

Use `--style-name cyberpunk` (or `--style-id cyberpunk`) to apply the preset cyberpunk style:

```bash
python scripts/image_craft.py generate \
  --prompt "Tokyo street at night" \
  --style-name cyberpunk \
  --negative \
  --scene cyberpunk \
  --output outputs/tokyo.png
```

Image Craft automatically:

1. Injects cyberpunk-specific **prompt template** keywords (neon, futuristic, holographic, etc.)
2. Adds **quality enhancement terms** (`masterpiece, intricate detail, 4K`)
3. Builds a **negative prompt** combining cyberpunk-scene avoidance (oversaturated neon, chromatic aberration overuse) with general quality avoidance

Cyberpunk is one of **54 built-in styles** across 8 categories. To preview the enhanced prompt without spending API credits:

```bash
python scripts/image_craft.py prompt \
  --prompt "Tokyo street" \
  --style-name cyberpunk \
  --negative
```

You can also blend styles with weights:

```bash
--style-mix "cyberpunk:0.7,blender-render:0.3"
```

### 8. How do I use a reference image to guide generation (local file or remote URL)?

Use `--image` for local files and `--image-url` for remote URLs. Both flags are repeatable for multi-reference setups:

```bash
# Local reference image (auto-converted to base64)
python scripts/image_craft.py generate \
  --prompt "same composition but in watercolor style" \
  --image ./refs/photo.jpg \
  --output outputs/watercolor.png

# Remote URL reference
python scripts/image_craft.py generate \
  --prompt "same subject in cyberpunk style" \
  --image-url "https://example.com/photo.jpg" \
  --output outputs/cyberpunk.png

# Multiple references with explicit purpose
python scripts/image_craft.py generate \
  --prompt "..." \
  --image "./style.jpg::style" \
  --image "./composition.jpg::composition" \
  --output outputs/result.png
```

When you provide a reference image, Image Craft automatically selects the `images-generations-reference` profile and builds the payload accordingly. Supported purposes: `style`, `composition`, `subject`, `palette` (declarative — the underlying API decides how to interpret each reference).

### 9. How do I batch-generate multi-style variants from one prompt (A/B testing)?

Use the `batch` subcommand with either explicit `--styles` or auto-recommended `--explore`:

```bash
# Explicit styles — 3 variants from the same prompt
python scripts/image_craft.py batch \
  --prompt "桂花乌龙茶 中式庭院" \
  --styles "watercolor,cyberpunk,blender-render" \
  --output-dir outputs/tea-experiment/

# Auto-explore: Image Craft picks 3 styles via local search
python scripts/image_craft.py batch \
  --prompt "桂花乌龙茶 中式庭院" \
  --explore --limit 3 \
  --output-dir outputs/tea-experiment/

# Dry-run to see the plan without spending API credits
python scripts/image_craft.py batch \
  --prompt "..." \
  --styles "cyberpunk,watercolor" \
  --output-dir outputs/test/ \
  --dry-run

# A/B labels for downstream comparison
python scripts/image_craft.py batch \
  --prompt "..." \
  --styles "v1,v2" \
  --ab-label control \
  --ab-label experiment \
  --output-dir outputs/ab-test/
```

The `--variants N` flag generates N images per style (default 1). Combined with `--styles "a,b,c" --variants 2`, you get 6 images. Use `--dry-run` first to validate the plan.

### 10. What is brief mode and when should I use it?

**Brief mode** turns a structured design specification (subject, scene, lighting, composition, lens, color palette, ratio, bans) into a professional image prompt. Use it when **consistency matters more than improvisation** — product photography, UI design, video storyboards, portrait or landscape series.

```bash
# Generate a JSON brief — no API call yet
python scripts/image_craft.py brief \
  --brief-type photo \
  --field 主题="一杯桂花乌龙茶" \
  --field 场景="中式庭院，秋天午后" \
  --field 光影="侧逆光，金色暖光" \
  --field 镜头="85mm, f/2.0" \
  --field 画面比例="3:4" \
  --field 禁止="人物出现, 过度饱和"

# Convert brief → enhanced prompt → preview (still no API call)
python scripts/image_craft.py brief \
  --template product-photography \
  --field 主题="球鞋" \
  --field 背景="大理石桌面" \
  --to-prompt \
  --style-name product-photography \
  --negative \
  -f markdown
```

5 built-in brief templates ship in `data/briefs.csv`:

| Template | Required fields |
|---|---|
| `product-photography` | 主题, 背景 |
| `ui-interface` | 应用类型, 设计风格 |
| `video-storyboard` | 场景描述, 运镜 |
| `portrait` | 主题 |
| `landscape` | 场景 |

The `禁止` (ban) field automatically flows into the negative prompt instead of being appended to the positive prompt.

## Data Library

### 11. What are the 54 built-in art styles? How do I browse and pick one?

The 54 styles span **8 categories**:

| Category | Count | Examples |
|---|---|---|
| Traditional art | 5 | oil-painting, watercolor, chinese-painting, sketch, woodblock |
| Digital art | 4 | cyberpunk, vaporwave, pixel-art, glitch |
| Photography | 5 | film, polaroid, black-white, long-exposure, macro |
| Illustration | 5 | flat-design, isometric, japanese-anime, american-comic, children |
| 3D rendering | 4 | low-poly, voxel, c4d-render, blender-render |
| Special effects | 4 | double-exposure, light-painting, infrared, tilt-shift |
| General / cross-category | 27 | (varied — query to discover) |

Browse styles by query, category, or randomly:

```bash
# Keyword search
python scripts/image_craft.py suggest "watercolor" --domain style --limit 20

# Category filter (in batch explore mode)
python scripts/image_craft.py batch \
  --prompt "..." --explore --category digital --output-dir outputs/

# Random recommendation
python scripts/image_craft.py suggest "" --domain style --random --limit 5

# Full design system: style + prompt + color
python scripts/image_craft.py suggest "cyberpunk future city" --design-system
```

Each style row in `data/styles.csv` has 11 fields: `id`, `name_en`, `name_cn`, `category`, `description`, `keywords`, `prompt_template`, `negative_prompt`, `example_prompt`, `use_cases`, `difficulty`. Search ranks by all of them with CJK tokenization and fuzzy matching.

### 12. How do I use the 119 prompt templates with variable filling?

Prompt templates live in `data/prompts.csv` with placeholders like `{subject}`, `{lighting}`, `{mood}`. Apply one with `--template <id|name|query>` and fill placeholders with repeated `--var key=value` flags:

```bash
# Cinematic portrait template
python scripts/image_craft.py generate \
  --template portrait-cinematic \
  --var subject="商务女性" \
  --var lighting="侧光" \
  --var mood="沉思" \
  --output outputs/portrait.png

# Search a template by query, then fill
python scripts/image_craft.py suggest "电影感人像" --domain prompt
python scripts/image_craft.py generate \
  --template "电影感人像" \
  --var subject="..." \
  --output outputs/result.png

# Preview rendered template without API call
python scripts/image_craft.py prompt \
  --prompt "..." \
  --template portrait-cinematic \
  --var subject="..." \
  --var lighting="..."
```

Templates are searchable across `name`, `category`, `tags`, and `template` body. Each has a `quality` score (1-5) to help you pick high-quality patterns. The `prompt` subcommand previews the rendered template without calling the API.

### 13. How do I apply the 50 color palettes to generated images?

Use `--color <name|query>` to append a palette's prompt description to your image prompt:

```bash
# By palette name (English or Chinese)
python scripts/image_craft.py generate \
  --prompt "Tokyo night scene" \
  --color "neon-cyberpunk" \
  --output outputs/tokyo.png

# By Chinese query
python scripts/image_craft.py generate \
  --prompt "宁静的湖面" \
  --color "莫兰迪" \
  --output outputs/lake.png

# Combined with style
python scripts/image_craft.py generate \
  --prompt "古风少女" \
  --style-name chinese-painting \
  --color "敦煌" \
  --output outputs/girl.png
```

Each palette in `data/colors.csv` has primary/secondary/accent colors plus a `prompt_description` field (e.g., "muted earth tones, soft gradients, low saturation, vintage feel"). Browse them:

```bash
python scripts/image_craft.py suggest "复古" --domain color --limit 5
python scripts/image_craft.py suggest "" --domain color --random
```

## Troubleshooting & Advanced

### 14. What can I do if the generated image quality is poor?

Image quality issues usually fall into three buckets. Apply them in order:

**1. Enhance the prompt** — let Image Craft inject quality terms and a negative prompt:

```bash
python scripts/image_craft.py generate \
  --prompt "..." \
  --negative \                       # add quality-related negative prompt
  --scene product-photography \      # add scene-specific negative terms
  --output out.png
```

**2. Add a style or template** — sparse prompts produce sparse images:

```bash
# Style adds visual identity + curated negative terms
--style-name product-photography

# Template adds structural keywords
--template "电影感人像" --var subject="..." --var lighting="..."
```

**3. Custom bans for known defects** — append your own negative terms:

```bash
--ban "extra fingers, lowres, watermark, text artifacts"
```

If quality is still poor, the model itself may be the bottleneck. Try `gpt-image-2-5-sunburst` instead of `gpt-image-2-5-flare` via `--model gpt-image-2-5-sunburst`, or switch suppliers (see [Q5](#5-which-openai-compatible-apis-does-image-craft-support)). The `data/negatives.csv` file ships 8 scene-specific negative prompt presets (product, UI, video, xiaohongshu, portrait, landscape, cyberpunk, watercolor) — `--scene <name>` activates them.

### 15. How do I handle API call failures or timeouts?

Common failure modes and fixes:

**HTTP 401 / 403 — Authentication failure**
- Verify `private_config.json` has the correct `api_key`
- Check the key against the supplier's dashboard
- If using env vars, confirm `echo $IMAGE_CRAFT_API_KEY` returns the expected value

**HTTP 429 — Rate limited**
- Most suppliers limit requests per minute; wait and retry
- For batch generation, reduce `--variants` or split into smaller batches
- Use `--dry-run` first to verify the plan without burning quota

**HTTP 5xx / timeout — Server or network issue**
- Verify `base_url` is reachable: `curl -I https://right.codes/draw`
- Try a smaller image size (`--size 512x512`) to rule out payload-size limits
- Switch to a different supplier temporarily

**HTTP 400 — Payload shape error**
- The supplier may expect a non-standard field. Use `--payload-merge '{"field":"value"}'` to add custom fields, or `--profile custom` with `--payload-json '<complete-json>'`. See [Q16](#16-how-do-i-customize-the-request-body-for-supplier-specific-fields).

For debugging, run with `--profile <explicit-profile>` to remove auto-detection from the equation and isolate the issue.

### 16. How do I customize the request body for supplier-specific fields?

Image Craft offers **two levels** of payload customization:

**Level 1 — merge into the auto-built payload** (recommended for adding 1-2 supplier fields):

```bash
python scripts/image_craft.py generate \
  --prompt "..." \
  --output out.png \
  --payload-merge '{"quality":"hd","style":"vivid","user":"my-app-id"}'
```

The merge is deep — nested keys are combined, not replaced.

**Level 2 — replace the entire payload** (for fully custom shapes):

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

**Profile selection cheat sheet:**

| User intent | Profile | Endpoint |
|---|---|---|
| Text-to-image, no reference | `images-generations` | `/v1/images/generations` |
| Text-to-image with reference | `images-generations-reference` | `/v1/images/generations` |
| Image analysis / vision | `chat-completions-vision` | `/v1/chat/completions` |
| Edit / transform existing image | `chat-completions-transform` | `/v1/chat/completions` |
| Fully custom | `custom` | (user-specified via `--payload-json`) |

When the supplier documentation does not specify a payload shape, an agent should ask the user which profile to use. See `scripts/payload_builder.py` for the canonical profile definitions.

---

## See Also

- [SKILL.md](../SKILL.md) — Full skill metadata and capability surface
- [README.md](../README.md) — Project overview and installation
- [ROADMAP.md](./ROADMAP.md) — Development roadmap
- [GEO.md](./GEO.md) — Generative Engine Optimization strategy
- [data/styles.csv](../data/styles.csv) — Style library (54 entries)
- [data/prompts.csv](../data/prompts.csv) — Prompt template library (119 entries)
- [data/colors.csv](../data/colors.csv) — Color palette library (50 entries)
- [data/briefs.csv](../data/briefs.csv) — Brief template library (5 entries)
- [data/negatives.csv](../data/negatives.csv) — Scene negative prompt library (8 entries)

---

*Found an error or missing scenario? [Open an issue](https://github.com/Chelase/image-craft/issues).*
