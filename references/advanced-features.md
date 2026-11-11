# Advanced Features (Runtime Reference)

Runtime reference for Image Craft 1.1.x. Read this only when the core workflow in [SKILL.md](../SKILL.md) is not enough: non-standard API payload shapes, style/template/palette libraries, structured briefs, batch variants, or prompt-enhancement flags.

All commands run from the skill root. `scripts/image_craft.py` is the canonical CLI; `scripts/image_craft.ps1` is a PowerShell mirror of the same arguments.

## Request Body Profiles

The script builds the API payload automatically. Auto-detection by default; override with `--profile`.

| User Intent | Default Profile | Endpoint |
|---|---|---|
| Text-to-image (no reference) | `images-generations` | `/v1/images/generations` |
| Text-to-image with reference image | `images-generations-reference` | `/v1/images/generations` |
| Image analysis / vision | `chat-completions-vision` | `/v1/chat/completions` |
| Image transformation | `chat-completions-transform` | `/v1/chat/completions` |
| Custom supplier fields | `custom` | (user-specified) |

Agent decision rules:

- Reference image + text prompt → `images-generations-reference` (or `chat-completions-vision` for analysis tasks).
- Modify/edit an existing image → `chat-completions-transform`.
- If the API documentation does not specify the correct payload shape for a supplier → ask the user which profile to use.
- Ask the user when: the reference image field name is undocumented, multiple valid payload shapes exist, or supplier-specific advanced parameters are requested.

Payload overrides:

- `--payload-json '<json>'` — replace the profile-built payload entirely. Use when you know the exact API shape.
- `--payload-merge '<json>'` — deep-merge a fragment into the profile-built payload. Use for supplier fields like `seed` or `n`.

## Reference Image Purposes

Append `::purpose` to `--image` or `--image-url` values (repeat the flag for multiple images):

- `::style` — style reference (default)
- `::composition` — layout/structure reference
- `::subject` — subject/character reference
- `::palette` — color palette reference

## Style System

54 styles across 6 categories (`traditional`, `digital`, `illustration`, `photography`, `3d`, `special`) live in `data/styles.csv`; searches run locally through `scripts/search.py`. Category aliases resolve to practical defaults, e.g. `--style-id 3d` → `blender-render`.

```bash
# Generate with a style by name or ID
python scripts/image_craft.py generate --prompt "东京街头" --style-name "赛博朋克" --output outputs/cyberpunk.png
python scripts/image_craft.py generate --prompt "东京街头" --style-id "cyberpunk" --output outputs/cyberpunk.png

# Blend weighted styles (highest weight becomes the primary template)
python scripts/image_craft.py prompt --prompt "未来城市" --style-mix "cyberpunk:0.7,blender-render:0.3" --negative --format json

# Style suggestions without generating
python scripts/image_craft.py suggest "赛博朋克未来城市"
python scripts/image_craft.py suggest "赛博朋克未来城市" --domain all --format json
python scripts/image_craft.py suggest "赛博朋克未来城市" --design-system

# Preview the final enhanced prompt without calling the API
python scripts/image_craft.py prompt --prompt "3d风格未来科幻城市，16:9，城市高空俯瞰" --style-id 3d --negative --format json

# Preview a style-migration prompt for image-to-image
python scripts/image_craft.py prompt --prompt "preserve the portrait composition" --style-name "watercolor" --style-strength 0.65 --format json

# Batch style exploration and A/B comparison
python scripts/image_craft.py batch --prompt "future city" --styles "cyberpunk,watercolor,blender-render" --output-dir outputs/batch --ab-label A --ab-label B --ab-label C --dry-run --format json
python scripts/image_craft.py batch --prompt "cyberpunk city" --explore --limit 3 --output-dir outputs/explore --dry-run --format json
```

PowerShell equivalents use the same parameter names in PascalCase, e.g. `pwsh -File .\scripts\image_craft.ps1 -Command suggest -Prompt "cyberpunk" -Limit 1 -Format json`.

## Prompt Templates and Color Palettes

Templates live in `data/prompts.csv`, palettes in `data/colors.csv`.

```bash
python scripts/image_craft.py generate --prompt "东京街头" --template "urban landscape" --var city="Tokyo" --var "time of day=night" --color "midnight blue" --style-name "cyberpunk" --output outputs/tokyo.png
```

## Structured Brief

```bash
# Preview the brief as Markdown
python scripts/image_craft.py brief --field "主题=一杯桂花乌龙茶放在石桌上" --field "场景=中式庭院，秋天午后" --brief-type product-photography --format markdown

# Use a brief template with auto-filled defaults
python scripts/image_craft.py brief --template "产品摄影" --field "主题=一杯桂花乌龙茶" --field "背景=大理石桌面" --to-prompt --style-name photography --format json

# Convert to an enhanced prompt with style
python scripts/image_craft.py brief --field "主题=a cup of osmanthus oolong tea" --field "场景=Chinese garden, autumn afternoon" --to-prompt --style-name "photography" --format json
```

## Prompt Enhancement Pipeline

All `generate` and `transform` calls automatically:

1. **Visual phrase normalization** — common Chinese scene descriptors and aspect ratios such as `16:9` are normalized into compact English image-prompt phrases.
2. **Style enhancement** — a selected style's `prompt_template` is merged with the user's prompt (`{subject}` placeholder replaced).
3. **Style mixing** — `--style-mix "cyberpunk:0.7,blender-render:0.3"` uses the highest-weight style as primary template and merges weighted descriptors and negatives. Takes precedence over `--style-id`/`--style-name`.
4. **Style migration** — for `transform`, `--style-strength 0.0..1.0` migrates the source image toward the target style while preserving structure and identity.
5. **Template rendering** — `--template` renders variables from repeated `--var key=value`.
6. **Color palette injection** — `--color` appends the palette's prompt description.
7. **Negative prompt** — per-style negatives plus general quality negatives (`lowres, bad anatomy, blurry, ...`), only with `--negative`.
8. **Quality terms** — SD-era tags (`masterpiece, best quality, trending on artstation, ...`). **Off by default**; enable with `--quality` only if the target endpoint is a Stable-Diffusion-style backend that demonstrably benefits from them. Modern GPT image models do not need them.

Override flags:

| Flag | Effect |
|------|--------|
| `--quality` | Append legacy quality terms (default: off) |
| `--negative` | Include negative prompts |
| `--style-id` / `--style-name` | Apply a style and its enhancement |
| `--style-mix style:weight,...` | Blend multiple styles with weight control |
| `--style-strength 0.0..1.0` | Style-migration strength for `transform` |
| `batch --styles ...` | Multiple explicit style variants |
| `batch --explore --limit N` | Auto-selected style exploration batch |
| `--ab-label LABEL` | A/B labels for batch variants; repeat as needed |
| `brief --field key=value` | Structured design brief from field pairs |
| `brief --template ID` | Brief template from `data/briefs.csv` |
| `brief --to-prompt` | Convert the brief into an enhanced prompt |
| `--template` / `--var` / `--color` | Template rendering and palette injection |
| `prompt` | Preview the final prompt without calling the API |
| `suggest --domain style\|prompt\|color\|all` | Search local catalogs without generating |
| `suggest --design-system` | Combined style + prompt + color recommendations |

## API Endpoints

Text-to-image:

```http
POST /v1/images/generations
Content-Type: application/json
Authorization: Bearer <api-key>
```

```json
{
  "model": "gpt-image-2-5-flare",
  "prompt": "..."
}
```

OpenAI-compatible image transformation / vision:

```http
POST /v1/chat/completions
Content-Type: application/json
Authorization: Bearer <api-key>
```

```json
{
  "model": "gpt-image-2-5-flare",
  "messages": [
    {
      "role": "user",
      "content": [
        {"type": "text", "text": "改成水彩画风"},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,..."}}
      ]
    }
  ]
}
```

The script accepts `data[0].b64_json`, `data.url`, direct data URLs, and markdown image links such as `![image](data:image/png;base64,...)` or `![image](https://...)`.
