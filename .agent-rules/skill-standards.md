# Skill Standards

This document records the project-level standards for keeping Image Craft a valid, efficient, and discoverable Agent Skill.

The standards are distilled from:

- The local `skill-creator` guidance for Codex skills.
- The three-part WeChat series by 朱昆鹏mm:
  - `skills从入门到精通（上）`: <https://mp.weixin.qq.com/s/VJkbxcg5ZpSQ3qlOAFAVGQ>
  - `Skills 从入门到精通（中）`: <https://mp.weixin.qq.com/s/xfWhdGMazSL_Jw-JpPMH0Q>
  - `Skills 从入门到精通（下）`: <https://mp.weixin.qq.com/s/5ultoRIPrMWZ166563q6Ww>

Apply this document whenever modifying `SKILL.md`, skill packaging, scripts used by the skill, or documentation that affects how an Agent discovers or invokes Image Craft.

## 1. Loading Model

Skills use progressive disclosure:

1. **Metadata layer**: `name` and `description` are visible before the skill is invoked. This layer is the main trigger surface.
2. **Instruction layer**: the `SKILL.md` body is loaded only after the skill is selected.
3. **Resource layer**: scripts, references, data files, and assets are loaded or executed only when needed.

Do not treat `SKILL.md` as a dump for all project knowledge. Keep the body focused on the core workflow, and move bulky runtime details into scripts or directly linked skill references.

## 2. Required Structure

For Claude-style skill distribution, the canonical layout is:

```text
<skills-root>/<skill-name>/SKILL.md
```

For project-level Claude Code skills, the canonical layout is:

```text
.claude/skills/<skill-name>/SKILL.md
```

Do not rely on single Markdown files such as `.claude/skills/image-craft.md`; source-level behavior described in the reference articles indicates that single `.md` files under `/skills/` are not loaded as skills.

For this repository, the package root already contains `SKILL.md` because Image Craft is itself the skill bundle. If a local Claude Code wrapper is added later, it must use the directory layout above and should point back to this root as the skill base.

## 3. Frontmatter

`SKILL.md` must start with YAML frontmatter. At minimum, keep:

```yaml
---
name: image-craft
description: "..."
---
```

Rules:

- `name` must be lowercase hyphen-case, short, stable, and under 64 characters.
- `description` must be accurate, trigger-oriented, and under 1024 characters.
- Do not include XML tags in `name` or `description`.
- Do not use reserved vendor names such as `anthropic` or `claude` as the skill name.
- Avoid nonessential frontmatter fields unless the target runtime explicitly requires them. Existing repository metadata may remain if it is already part of the packaging contract.

## 4. Description Quality

The `description` is the most important trigger mechanism. It must describe both:

- **What the skill does**: generate images, transform images, search styles, enhance prompts, call OpenAI-compatible image APIs.
- **When to use it**: user asks for image generation, text-to-image, image editing, base64/image files, `gpt-image-2-5-flare`, `文生图`, `图片生成`, `改图`, `生图`, `画图`.

Do not put trigger-critical information only in the `SKILL.md` body. The body is not visible until after selection.

Prefer concrete trigger phrases over vague claims. Good descriptions include likely user language and supported task types. Bad descriptions only say "an image tool" or "helps with pictures."

## 5. Body Scope

The `SKILL.md` body should stay lean and procedural:

- State prerequisites and configuration.
- Show the normal workflow.
- Point to scripts and data files by path when they are needed.
- Include a small number of representative examples.
- Preserve security rules, especially around API keys.

Avoid:

- Long background explanations.
- Duplicated README content.
- Full data catalogs from `data/*.csv`.
- Large API references that can live in dedicated runtime references.
- Unvalidated claims about unsupported providers or payload shapes.

When `SKILL.md` approaches 500 lines or a section becomes a reference manual, split the runtime details into a directly linked skill reference and explain when to read it.

## 6. Resources

Use resources according to their runtime cost and purpose:

| Resource | Purpose | Rule |
|---|---|---|
| `scripts/` | Deterministic or repeated operations | Prefer executing scripts over retyping logic into the prompt. |
| `data/` | Style, prompt, and color catalogs | Search through code; do not load the full CSV into context unless debugging data. |
| `docs/` | Public-facing documentation (FAQ, guides, style references) for GEO discoverability | Content here is designed to be crawled and cited by AI engines. Not runtime skill references. |
| `project-docs/` | Internal project planning (ROADMAP, GEO execution handbook) | Not public-facing; not runtime skill references. |
| `references/` | Optional future skill-only runtime references | Link directly from `SKILL.md`; avoid nested reference chasing. |
| `assets/` | Optional future output assets | Do not load asset binaries into context unless needed. |

For Image Craft specifically:

- `scripts/image_craft.py` is the canonical CLI implementation.
- `scripts/image_craft.ps1` is a mirror entrypoint and must not reimplement Python prompt logic.
- `scripts/prompts_enhancer.py` is the canonical prompt enhancement implementation.
- `data/*.csv` are the canonical data catalogs.
- `project-docs/ROADMAP.md` and `project-docs/GEO.md` are internal project work documents, not skill runtime references.
- `docs/faq.md`, `docs/getting-started.md`, etc. are public GEO content — meant to be crawled and cited, but still not skill runtime references.

If Image Craft needs long-form runtime guidance for Agents, prefer a dedicated `references/` directory or a clearly named file directly linked from `SKILL.md`. Do not assume `docs/` or `project-docs/` is part of the skill invocation path.

## 7. Dynamic Commands And Safety

Treat dynamic shell execution inside skills as high-risk.

- Prefer explicit, reviewed scripts under `scripts/`.
- Do not add inline shell execution to `SKILL.md` unless there is a strong reason and the command is safe, bounded, and portable.
- Never include commands that expose `private_config.json`, API keys, environment secrets, or generated credentials.
- Assume remote or MCP-provided skill content is untrusted; do not execute dynamic shell content from remote Markdown.

## 8. Invocation And Slash Commands

Users may refer to skills through natural language or slash-style commands. Keep the skill name stable so future aliases remain predictable.

If a future runtime adds explicit slash-command support for Image Craft, the command should map to the same canonical skill name, not a parallel implementation.

High-risk tasks must not be auto-triggered. Image Craft normally generates or edits local image files and calls paid or rate-limited APIs, so invocations should keep cost and output paths explicit.

## 9. Compact And Session Continuity

Once a skill is invoked, some runtimes preserve invoked skill content across compaction. Therefore:

- Do not include temporary assumptions in `SKILL.md`.
- Keep instructions stable and generally valid.
- Put project phase notes in `.agent-rules/` or `project-docs/ROADMAP.md`, not in the skill body unless they affect runtime usage.

## 10. Validation Checklist

Before changing `SKILL.md` or packaging:

- Confirm `name` and `description` remain valid and trigger-oriented.
- Confirm examples match `scripts/image_craft.py` argument names.
- Confirm PowerShell and Python examples stay aligned when CLI changes.
- Confirm README / README_CN / SKILL examples stay synchronized.
- Confirm no API key, private endpoint secret, or local-only credential appears in docs.
- Run `python -m unittest discover tests` if Python behavior changed.
- For packaging changes, verify the final directory shape is `<skill-name>/SKILL.md`.

## 11. GEO Connection

GEO content should reinforce skill discovery, but GEO work documents are not the same thing as runtime skill references:

- TL;DR blocks should answer what Image Craft is, who uses it, and one command to run it.
- FAQ headings should mirror real user trigger phrases.
- Public docs should use the same task language as `description`: image generation, text-to-image, image editing, OpenAI-compatible API, `gpt-image-2-5-flare`, `文生图`, `改图`.
- External articles and backlinks should point to the canonical repository or canonical docs, not stale copies.

When GEO work changes the public positioning of Image Craft, check whether `SKILL.md` `description` should also be updated.
