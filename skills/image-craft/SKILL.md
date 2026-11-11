---
name: image-craft
description: "Generate or edit images through the user's configured GPT image API (gpt-image-2-5-flare, gpt-image-2-5-sunburst, legacy gpt-image-2). Use this skill whenever the user asks an agent to create an image, make a picture, generate artwork, produce a base64/image file from a prompt, transform an existing image, or explicitly mentions gpt-image-2-5, gpt-image-2, 文生图, 图片生成, 图片编辑, 改图, 生图, or 画一张图. Supports OpenAI-compatible APIs including Right Codes, OpenAI, Azure, and other compatible endpoints."
version: 1.1.0
metadata:
  openclaw:
    homepage: https://github.com/Chelase/skills
---

# Image Craft

> **TL;DR** - Image Craft is a universal AI Agent skill for generating and editing images through OpenAI-compatible APIs (`gpt-image-2-5-flare` / `gpt-image-2-5-sunburst`, Azure-compatible endpoints, Right Codes).
> **Install:** `npx skills add gh:Chelase/skills --skill image-craft`（或 `git clone https://github.com/Chelase/skills.git` 后取 `skills/image-craft/`）
> **One command:** `python scripts/image_craft.py generate --prompt "cyberpunk Tokyo street" --output outputs/tokyo.png`

## Configuration

Required — create `private_config.json` in this skill directory:

```json
{
  "api_key": "YOUR_API_KEY_HERE",
  "base_url": "https://your-api-endpoint.com"
}
```

Or set `IMAGE_CRAFT_API_KEY` / `IMAGE_CRAFT_BASE_URL` / `IMAGE_CRAFT_MODEL` environment variables.
Priority: script flags > environment variables > `private_config.json`.
Security: keep `private_config.json` local. Never print the API key in responses.

## Model Selection

| Model | Use for |
|---|---|
| `gpt-image-2-5-flare` | **Default.** Fast, good quality for most generation and straightforward edits |
| `gpt-image-2-5-sunburst` | Precision tier: fine local edits, dense or exact text rendering, multi-subject compositions, high-fidelity commercial output, reference-image consistency, multi-round editing |

- Start with `flare`; switch to `sunburst` when the request involves fine detail, exact on-image text, or iterative editing.
- If the user names a model, honor it.
- Override per call with `--model` / `-Model`.

## Workflow

1. Check configuration (`api_key`, `base_url`).
2. Build a clear prompt from the user's request. Keep on-image text in the user's language (Chinese text stays Chinese); preserve names, brands, and style constraints. Do not pad prompts with legacy quality tags like "masterpiece, best quality" — write concrete descriptions (subject, scene, lighting, composition, style) instead.
3. Pick the command: `generate` for prompt-only requests; `transform` when editing an existing image. Pass reference images with `--image path.png` (append `::style`, `::composition`, `::subject`, or `::palette` to declare the purpose).
4. Save to a concrete output path, creating the directory if needed. The script decodes `b64_json`, `data:` URLs, and markdown image links automatically.

Python:

```bash
python scripts/image_craft.py generate --prompt "画一只可爱的猫咪" --output outputs/cat.png
python scripts/image_craft.py transform --prompt "改成水彩画风，保留人物构图" --input input.png --output outputs/watercolor.png
```

PowerShell:

```powershell
pwsh -File .\scripts\image_craft.ps1 -Command generate -Prompt "画一只可爱的猫咪" -Output .\outputs\cat.png
pwsh -File .\scripts\image_craft.ps1 -Command transform -Prompt "改成水彩画风" -InputImage .\input.png -Output .\outputs\watercolor.png
```

5. **Inspect the saved image visually (Read the file) before delivering.** Never judge output quality from the API response alone. Apply the acceptance checklist below; on failure, refine the prompt or switch to `sunburst` and retry (max 2 retries), then report honestly what still fails.
6. Report the output path, model used, and any revised prompt the API returned.

## Output Acceptance Checklist

Verify against the task type before delivering any image:

- [ ] **文字图 (text in image)** — fixed titles, numbers, Chinese short sentences: every character readable and correctly spelled. Zoom in; wrong or garbled Chinese glyphs are the most common failure.
- [ ] **参考图 (reference-guided)** — fixed person or product: face, logo, proportions, and colors consistent with the reference image.
- [ ] **局部编辑 (local edit)** — only the requested element changed: untouched regions, lighting, and perspective show no drift; no visible seams at edit boundaries.
- [ ] **复杂构图 (complex composition)** — multiple objects and depth layers: count the objects, check occlusion order matches the request, check hands and limbs.
- [ ] **连续编辑 (multi-round editing)** — editing the same image across rounds (up to 3): subject, style, and layout preserved after each round. If a later round degrades, re-edit from the last good version instead of stacking fixes.
- [ ] **通用 (general)** — aspect ratio and size as requested; no stray watermarks or garbled text; style consistent across a batch of images.

## Advanced Features

Style libraries (54 styles), prompt templates, color palettes, structured briefs, batch A/B variants, style mixing and migration, request-body profiles for non-standard APIs, and payload overrides remain available in `scripts/image_craft.py`. Read [references/advanced-features.md](references/advanced-features.md) only when the core workflow above is not enough.

## Troubleshooting

- Missing key or base URL: fix `private_config.json` or the `IMAGE_CRAFT_*` environment variables.
- Auth failures: check key validity; connection failures: verify the base URL is reachable.
- If the runtime blocks network access, request permission to run the command with network access rather than working around the restriction.
