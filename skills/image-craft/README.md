# Image Craft

> English | [中文](README_CN.md)

> **TL;DR** - Image Craft is a universal AI Agent skill for generating and editing images through OpenAI-compatible APIs such as `gpt-image-2-5-flare` / `gpt-image-2-5-sunburst`, Azure-compatible endpoints, and Right Codes. It bundles 54 art styles, 119 prompt templates, and 50 color palettes with local search and prompt enhancement.
>
> **Use it when:** You need image generation or image editing from an Agent CLI without writing API payload code.
> **Install:** `npx skills add gh:Chelase/skills --skill image-craft`（或 `git clone https://github.com/Chelase/skills.git` 后取 `skills/image-craft/`）
> **One command:** `python scripts/image_craft.py generate --prompt "cyberpunk Tokyo street" --style-name cyberpunk --output outputs/tokyo.png`

A universal skill for AI agents to generate and edit images using OpenAI-compatible GPT image APIs.

## Features

- **Text-to-image generation**: Create images from text prompts
- **Image transformation**: Edit existing images with text instructions
- **Multiple interfaces**: Both PowerShell and Python scripts included
- **OpenAI-compatible API**: Works with Right Codes, OpenAI, Azure, and other compatible endpoints

## Prerequisites

**Before using this skill, you MUST configure:**

1. **API Key** - Required for authentication
2. **Base URL** - Required API endpoint URL

Without these configurations, the skill will not work.

## Installation

### For OpenCode Agents

1. Clone this repository to your skills directory:
   ```bash
   git clone https://github.com/Chelase/skills.git ~/.agents/skills/skills
   ```

2. Configure your API (see [Configuration](#configuration))

3. The skill will be automatically available when you ask to generate images

### For Other AI Agents

Copy the `SKILL.md` file content to your agent's skill system, and ensure the scripts are accessible.

## Configuration

### Required Settings

Create a `private_config.json` file in the skill root directory:

```json
{
  "api_key": "YOUR_API_KEY_HERE",
  "base_url": "https://your-api-endpoint.com"
}
```

Or set environment variables:

```bash
export IMAGE_CRAFT_API_KEY="your-api-key"
export IMAGE_CRAFT_BASE_URL="https://your-api-endpoint.com"
```

### Optional Settings

```json
{
  "api_key": "YOUR_API_KEY_HERE",
  "base_url": "https://your-api-endpoint.com",
  "model": "gpt-image-2-5-flare"
}
```

```bash
export IMAGE_CRAFT_MODEL="gpt-image-2-5-flare"  # Optional, defaults to gpt-image-2-5-flare
```

**Priority order:**
1. Script parameters (`-Model`, `-BaseUrl`)
2. Environment variables (`IMAGE_CRAFT_MODEL`, `IMAGE_CRAFT_BASE_URL`, `IMAGE_CRAFT_API_KEY`)
3. `private_config.json`
4. Default values (only `model` has default: `gpt-image-2-5-flare`)

## Usage

### PowerShell

```powershell
# Generate an image
pwsh -File scripts/image_craft.ps1 -Command generate -Prompt "一只可爱的猫咪" -Output outputs/cat.png

# Transform an image
pwsh -File scripts/image_craft.ps1 -Command transform -Prompt "改成水彩画风" -InputImage input.png -Output outputs/watercolor.png

# Migrate an image toward a target style with partial strength
pwsh -File scripts/image_craft.ps1 -Command transform -Prompt "保留人物构图" -InputImage input.png -StyleName "watercolor" -StyleStrength 0.65 -Output outputs/watercolor-migration.png

# Generate with a style (by name)
pwsh -File scripts/image_craft.ps1 -Command generate -Prompt "东京街头" -StyleName "赛博朋克" -Output outputs/cyberpunk.png

# Get style suggestions
pwsh -File scripts/image_craft.ps1 -Command suggest -Prompt "赛博朋克城市"

# Get machine-readable style suggestions
pwsh -File scripts/image_craft.ps1 -Command suggest -Prompt "cyberpunk" -Limit 1 -Format json

# Preview the final enhanced prompt without calling the image API
pwsh -File scripts/image_craft.ps1 -Command prompt -Prompt "3d风格未来科幻城市，16:9，城市高空俯瞰" -StyleId 3d -Negative -Format json

# Preview with template variables and a color palette
pwsh -File scripts/image_craft.ps1 -Command prompt -Prompt "东京街头" -Template "urban landscape" -Var city=Tokyo,time_of_day=night -Color "midnight blue" -StyleName cyberpunk -Format json

# Blend multiple styles with weights
pwsh -File scripts/image_craft.ps1 -Command prompt -Prompt "未来城市" -StyleMix "cyberpunk:0.7,blender-render:0.3" -Negative -Format json

# Preview a batch plan for multiple style variants without calling the image API
pwsh -File scripts/image_craft.ps1 -Command batch -Prompt "未来城市" -Styles "cyberpunk,watercolor,blender-render" -OutputDir outputs/batch -AbLabel A,B,C -DryRun -Format json
```

### Python

```bash
# Generate an image
python scripts/image_craft.py generate --prompt "一只可爱的猫咪" --output outputs/cat.png

# Transform an image
python scripts/image_craft.py transform --prompt "改成水彩画风" --input input.png --output outputs/watercolor.png

# Migrate an image toward a target style with partial strength
python scripts/image_craft.py transform --prompt "preserve the portrait composition" --input input.png --style-name "watercolor" --style-strength 0.65 --output outputs/watercolor-migration.png

# Generate with a style (by name or ID)
python scripts/image_craft.py generate --prompt "东京街头" --style-name "赛博朋克" --output outputs/cyberpunk.png

# Include negative prompts (avoids common defects)
python scripts/image_craft.py generate --prompt "东京街头" --style-name "赛博朋克" --negative --output outputs/cyberpunk.png

# Get style suggestions for a prompt
python scripts/image_craft.py suggest "赛博朋克城市"

# Search all local libraries as JSON
python scripts/image_craft.py suggest "赛博朋克未来城市" --domain all --format json

# Preview the final enhanced prompt without generating an image
python scripts/image_craft.py prompt --prompt "3d风格未来科幻城市，16:9，城市高空俯瞰" --style-id 3d --negative --format json

# Blend multiple styles with weights
python scripts/image_craft.py prompt --prompt "未来城市" --style-mix "cyberpunk:0.7,blender-render:0.3" --negative --format json

# Generate a structured design brief and convert to an enhanced prompt
python scripts/image_craft.py brief --field "主题=一杯桂花乌龙茶放在石桌上" --field "场景=中式庭院，秋天午后" --field "光影=侧逆光，金色暖光" --field "构图=居中偏下，浅景深，前景落叶虚化" --field "镜头=85mm, f/2.0" --field "色调=低饱和暖色，胶片质感" --field "画面比例=3:4" --field "禁止=人物出现,过度饱和,文字" --brief-type product-photography --format markdown

# Use a brief template with auto-filled defaults
python scripts/image_craft.py brief --template "产品摄影" --field "主题=一杯桂花乌龙茶" --field "背景=大理石桌面" --to-prompt --style-name photography --format json

# Preview a batch plan for multiple style variants without calling the image API
python scripts/image_craft.py batch --prompt "future city" --styles "cyberpunk,watercolor,blender-render" --output-dir outputs/batch --ab-label A --ab-label B --ab-label C --dry-run --format json

# Explore recommended styles for a prompt and generate a dry-run batch plan
python scripts/image_craft.py batch --prompt "cyberpunk city" --explore --limit 3 --output-dir outputs/explore --dry-run --format json

# Generate with a prompt template and color palette
python scripts/image_craft.py generate --prompt "东京街头" --template "urban landscape" --var city="Tokyo" --var "time of day=night" --color "midnight blue" --style-name "cyberpunk" --output outputs/tokyo.png

# Generate with a reference image (local file)
python scripts/image_craft.py generate --prompt "a cat like this one" --image reference_cat.png --style-name "watercolor" --output outputs/cat_ref.png

# Generate with a reference image (remote URL)
python scripts/image_craft.py generate --prompt "a cat like this one" --image-url "https://example.com/cat.jpg" --output outputs/cat_url.png

# Generate with explicit size and response format
python scripts/image_craft.py generate --prompt "a landscape" --size 1024x1024 --response-format b64_json --output outputs/landscape.png

# Use a specific request body profile
python scripts/image_craft.py generate --prompt "a landscape" --profile images-generations-reference --image-url "https://example.com/ref.jpg" --output outputs/landscape_ref.png
```

## Style System

The skill includes 54 art styles across 8 categories (traditional, digital, illustration, photography, 3d, special). Styles are auto-enhanced with per-style prompt templates; negative prompts are opt-in via `--negative`.

Use `--style-name` or `--style-id` to apply a style. Category aliases such as `--style-id 3d` resolve to a practical default style (`blender-render`) for professional 3D rendering. Use `suggest` command to explore styles, prompt templates, and color palettes from the local `data/*.csv` libraries.

The unified search backend supports:

- `--domain style|prompt|color|all`
- `--design-system` for combined style + template + palette recommendations
- `--random` for random recommendations
- `--format json` for machine-readable output

Use `batch` to create multiple variants from one prompt. Pass explicit styles with `--styles "cyberpunk,watercolor"`, or use `--explore --limit 3` to select recommended styles from the local search backend. `--dry-run` prints a JSON batch plan with enhanced prompts, output paths, and A/B labels without calling the image API.

## Prompt Enhancement

All generation-oriented commands automatically normalize common visual descriptors such as `16:9` into professional composition phrases and apply style templates. Pass `--negative` to include negative prompts that avoid common artifacts (`lowres, bad anatomy, blurry, etc.`). Legacy SD-style quality terms (`masterpiece, best quality, ...`) are off by default; opt in with `--quality` only for Stable-Diffusion-style backends. Use `prompt` to preview the final enhanced prompt without calling the image API.

Use `--style-mix` to combine multiple weighted styles, for example `cyberpunk:0.7,blender-render:0.3`. The highest-weight style provides the primary template, while all styles contribute weighted influence descriptors and negative prompt terms.

If `--style-mix` is provided together with `--style-id` or `--style-name`, the style mix takes precedence.

For image-to-image transformations, use `--style-strength` with `--style-id` or `--style-name` to migrate the source image toward a target style while preserving source structure and subject identity. For example, `--style-name watercolor --style-strength 0.65` applies a 65% watercolor migration and preserves 35% of the source image structure.

## Request Body Profiles

The skill uses request body profiles to construct the correct API payload for different usage patterns. By default, the profile is auto-detected based on your command and arguments:

| User Intent | Default Profile | Endpoint |
|---|---|---|
| Text-to-image | `images-generations` | `/v1/images/generations` |
| Text-to-image with reference | `images-generations-reference` | `/v1/images/generations` |
| Image analysis / vision | `chat-completions-vision` | `/v1/chat/completions` |
| Image transformation | `chat-completions-transform` | `/v1/chat/completions` |
| Custom supplier fields | `custom` | (user-specified) |

Use `--profile` to override auto-detection. Reference images are provided via `--image` (local files, repeatable) or `--image-url` (remote URLs, repeatable).

**Additional options:**
- `--size` — image dimensions (e.g. `1024x1024`, `1792x1024`)
- `--response-format` — `url` or `b64_json` (controls how the API returns the generated image)
- `--payload-json` — complete request body as a JSON string (replaces the profile-built payload entirely)
- `--payload-merge` — JSON to deep-merge into the profile-built payload (for supplier-specific fields)

**Reference image purposes:**
Append `::purpose` to `--image` or `--image-url` values to declare the role of each reference image:
- `::style` — style reference (default when omitted)
- `::composition` — layout/structure reference
- `::subject` — subject/character reference
- `::palette` — color palette reference

```bash
# Two reference images with different purposes
python scripts/image_craft.py generate --prompt "a cat" --image-url "https://a.com/style.png::style" --image-url "https://b.com/comp.png::composition" --output out.png

# Deep-merge a custom field into the payload
python scripts/image_craft.py generate --prompt "a cat" --payload-merge '{"seed": 42}' --output out.png
```

## Models

| Model | Description |
|-------|-------------|
| `gpt-image-2-5-flare` | Default model. Fast, good quality for most generation and straightforward edits |
| `gpt-image-2-5-sunburst` | Precision tier: fine local edits, exact text rendering, multi-subject compositions, multi-round editing |

## API Endpoints

### Text-to-Image

```
POST /v1/images/generations
```

Request body:
```json
{
  "model": "gpt-image-2-5-flare",
  "prompt": "your prompt here"
}
```

### Image Transformation

```
POST /v1/chat/completions
```

Request body:
```json
{
  "model": "gpt-image-2-5-flare",
  "messages": [
    {
      "role": "user",
      "content": [
        {"type": "text", "text": "your instruction"},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,..."}}
      ]
    }
  ]
}
```

## Troubleshooting

- **Missing API key or base URL**: Verify `private_config.json` or environment variables are set correctly.
- **Authentication fails**: Check if `IMAGE_CRAFT_API_KEY` is correct and not expired.
- **Connection fails**: Verify `IMAGE_CRAFT_BASE_URL` is correct and accessible.

## Security

- Never commit your `private_config.json` file
- The `.gitignore` is configured to exclude this file
- Use environment variables in production environments

## License

MIT

## Support

For issues or questions, please open an issue on GitHub.
