#!/usr/bin/env python3
"""Call the Image Craft API and save the returned image."""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

from payload_builder import (
    PROFILES as PAYLOAD_PROFILES,
    VALID_PROFILES,
    build_payload as build_api_payload,
    parse_image_arg,
    resolve_profile,
    resolve_reference_images,
)
from prompts_enhancer import StyleWeight, enhance, is_simple_prompt, load_styles
from check_update import check_for_update, format_update_message
from search import (
    format_color,
    format_prompt,
    format_style,
    get_design_system,
    get_random_colors,
    get_random_prompts,
    get_random_styles,
    search_colors,
    search_prompts,
    search_styles,
)

DEFAULT_MODEL = "gpt-image-2-5-flare"

CATEGORY_DEFAULT_STYLE_IDS = {
    "3d": "blender-render",
    "digital": "cyberpunk",
    "photography": "film-noir",
    "illustration": "isometric",
    "traditional": "oil-painting",
    "effect": "double-exposure",
    "special": "double-exposure",
}


def skill_dir() -> Path:
    return Path(__file__).resolve().parents[1]


def load_config() -> dict:
    config_path = skill_dir() / "private_config.json"
    config: dict = {}
    if config_path.exists():
        config = json.loads(config_path.read_text(encoding="utf-8"))

    base_url = os.environ.get("IMAGE_CRAFT_BASE_URL") or config.get("base_url")
    api_key = os.environ.get("IMAGE_CRAFT_API_KEY") or config.get("api_key")
    model = os.environ.get("IMAGE_CRAFT_MODEL") or config.get("model") or DEFAULT_MODEL

    if not base_url:
        raise SystemExit(
            "Missing base URL. Set IMAGE_CRAFT_BASE_URL, or add base_url to private_config.json."
        )

    if not api_key:
        raise SystemExit(
            "Missing API key. Set IMAGE_CRAFT_API_KEY or add api_key to private_config.json."
        )

    return {"base_url": base_url.rstrip("/"), "api_key": api_key, "model": model}


def post_json(url: str, payload: dict, api_key: str) -> dict:
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=180) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"API request failed with HTTP {exc.code}: {error_body}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"API request failed: {exc}") from exc

    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"API returned non-JSON response: {body[:500]}") from exc


def image_data_url(path: Path) -> str:
    mime_type = mimetypes.guess_type(path.name)[0] or "image/png"
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime_type};base64,{encoded}"


def extract_image_b64(response: dict) -> tuple[str, str | None]:
    data = response.get("data")
    if isinstance(data, list) and data:
        first = data[0]
        if isinstance(first, dict):
            # b64_json response
            if first.get("b64_json"):
                return first["b64_json"], first.get("revised_prompt")
            # URL response — download the image
            url = first.get("url")
            if url:
                img_b64 = _download_image_url(url)
                return img_b64, first.get("revised_prompt")

    choices = response.get("choices")
    if isinstance(choices, list) and choices:
        message = choices[0].get("message", {}) if isinstance(choices[0], dict) else {}
        content = message.get("content") if isinstance(message, dict) else None
        if isinstance(content, str):
            # data:image/...;base64,... embedded in content
            match = re.search(r"data:image/[a-zA-Z0-9.+-]+;base64,([A-Za-z0-9+/=\r\n]+)", content)
            if match:
                return re.sub(r"\s+", "", match.group(1)), None
            # Markdown image link from chat completions, e.g. ![image](https://...)
            match = re.search(r"!\[[^\]]*\]\((https?://[^\s)]+)\)", content)
            if match:
                img_b64 = _download_image_url(match.group(1))
                return img_b64, None
            # plain remote image URL in content
            match = re.search(r'(https?://[^\s)]+\.(?:png|jpg|jpeg|webp|gif)(?:\?[^\s)]*)?)', content)
            if match:
                img_b64 = _download_image_url(match.group(1))
                return img_b64, None

    raise SystemExit("Could not find image base64 in API response.")


def _download_image_url(url: str) -> str:
    """Download an image from a URL and return its base64-encoded content."""
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = resp.read()
    except (urllib.error.HTTPError, urllib.error.URLError) as exc:
        raise SystemExit(f"Failed to download image from URL: {exc}") from exc
    return base64.b64encode(body).decode("ascii")


def save_image(image_b64: str, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(base64.b64decode(image_b64))


def _maybe_check_update(no_check: bool) -> None:
    """Run update check unless disabled; print message to stderr."""
    if no_check:
        return
    try:
        info = check_for_update()
        if info:
            print(format_update_message(info), file=sys.stderr)
    except Exception:
        pass  # never let update check break the main flow


def _parse_json_arg(value: str, arg_name: str) -> dict:
    """Parse a JSON string from a CLI argument, raising on invalid JSON."""
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{arg_name}: invalid JSON — {exc}") from exc
    if not isinstance(parsed, dict):
        raise SystemExit(f"{arg_name}: expected a JSON object, got {type(parsed).__name__}")
    return parsed


def resolve_style(style_name: str | None = None, style_id: str | None = None) -> dict | None:
    """Resolve a style by name or ID, returning the style dict or None."""
    if not style_name and not style_id:
        return None

    styles = load_styles()
    if style_id:
        normalized_style_id = style_id.lower().strip()
        for s in styles:
            if s.get("id", "") == normalized_style_id:
                return s
        default_style_id = CATEGORY_DEFAULT_STYLE_IDS.get(normalized_style_id)
        if default_style_id:
            for s in styles:
                if s.get("id", "") == default_style_id:
                    return s
    if style_name:
        # Search by name (supports Chinese and English)
        name_lower = style_name.lower()
        default_style_id = CATEGORY_DEFAULT_STYLE_IDS.get(name_lower)
        if default_style_id:
            for s in styles:
                if s.get("id", "") == default_style_id:
                    return s
        for s in styles:
            if name_lower in s.get("name_cn", "").lower() or name_lower in s.get("name_en", "").lower():
                return s
        # Fuzzy match via the unified Phase 2 search backend.
        matches = search_styles(style_name, limit=1)
        if matches:
            return matches[0]
    return None


def parse_style_mix(value: str | None) -> list[tuple[str, float]]:
    """Parse style mix values like 'cyberpunk:0.7,blender-render:0.3'."""
    if not value:
        return []

    parsed: list[tuple[str, float]] = []
    for raw_part in re.split(r"[,+]", value):
        part = raw_part.strip()
        if not part:
            continue
        if ":" in part:
            style_ref, raw_weight = part.rsplit(":", 1)
            style_ref = style_ref.strip()
            try:
                weight = float(raw_weight.strip())
            except ValueError as exc:
                raise SystemExit(f"Invalid --style-mix weight in '{part}'. Use style:weight.") from exc
        else:
            style_ref = part
            weight = 1.0
        if not style_ref:
            raise SystemExit(f"Invalid --style-mix value '{part}'. Style name is empty.")
        if weight <= 0:
            raise SystemExit(f"Invalid --style-mix weight in '{part}'. Weight must be positive.")
        parsed.append((style_ref, weight))
    return parsed


def resolve_style_mix(style_mix: str | None) -> list[StyleWeight]:
    """Resolve a comma/plus separated weighted style mix into style dicts."""
    styles: list[StyleWeight] = []
    for style_ref, weight in parse_style_mix(style_mix):
        style = resolve_style(style_id=style_ref) or resolve_style(style_name=style_ref)
        if not style:
            raise SystemExit(f"Could not resolve style in --style-mix: {style_ref}")
        styles.append((style, weight))
    return styles


def parse_vars(values: list[str] | None) -> dict[str, str]:
    """Parse repeated key=value CLI arguments."""
    parsed: dict[str, str] = {}
    for value in values or []:
        if "=" not in value:
            raise SystemExit(f"Invalid --var value '{value}'. Use key=value.")
        key, raw = value.split("=", 1)
        key = key.strip()
        if not key:
            raise SystemExit(f"Invalid --var value '{value}'. Variable name is empty.")
        parsed[key] = raw.strip()
    return parsed


def resolve_template(template: str | None) -> dict | None:
    """Resolve a prompt template by ID/name/query using search.py."""
    if not template:
        return None
    matches = search_prompts(template, limit=10)
    template_lower = template.lower()
    for match in matches:
        if template_lower in {match.get("id", "").lower(), match.get("name", "").lower()}:
            return match
    return matches[0] if matches else None


def render_template(template: dict, prompt: str, variables: dict[str, str]) -> str:
    """Render a prompt template, using the prompt as the default subject-like value."""
    rendered = template.get("template", "")
    if not rendered:
        return prompt

    variable_names = [name.strip() for name in template.get("variables", "").split(",") if name.strip()]
    for name in variable_names:
        value = variables.get(name)
        if value is None:
            value = variables.get(name.replace(" ", "_"))
        if value is None:
            value = variables.get(name.replace(" ", "-"))
        if value is None and name in {"subject", "product", "location", "city", "items"}:
            value = prompt
        if value is not None:
            rendered = rendered.replace("{" + name + "}", value)
    return rendered


def resolve_color(color: str | None) -> dict | None:
    """Resolve a color palette query using search.py."""
    if not color:
        return None
    matches = search_colors(color, limit=1)
    return matches[0] if matches else None


def apply_template_and_color(args: argparse.Namespace) -> tuple[str, dict | None, dict | None]:
    """Build the base prompt from a template and optional color palette."""
    variables = parse_vars(getattr(args, "var", None))
    template = resolve_template(getattr(args, "template", None))
    color = resolve_color(getattr(args, "color", None))

    prompt = args.prompt
    if template:
        prompt = render_template(template, prompt, variables)
    if color and color.get("prompt_description"):
        prompt = f"{prompt}, {color['prompt_description']}"

    return prompt, template, color


def prepare_prompt(args: argparse.Namespace) -> tuple[str, str | None, dict | None, list[StyleWeight]]:
    """Enhance the prompt and return (final_prompt, negative_prompt, style_dict, style_mix)."""
    style_mix = resolve_style_mix(getattr(args, "style_mix", None))
    style = resolve_style(style_name=args.style_name, style_id=args.style_id)
    style_strength = getattr(args, "style_strength", None)
    if style_strength is not None and not 0.0 <= style_strength <= 1.0:
        raise SystemExit("--style-strength must be between 0.0 and 1.0.")
    if style_strength is not None and style_mix:
        raise SystemExit("--style-strength cannot be combined with --style-mix.")
    if style_strength is not None and style is None:
        raise SystemExit("--style-strength requires --style-id or --style-name.")
    prompt, _, _ = apply_template_and_color(args)

    # Build scene negatives from --scene and --brief-type
    scene = getattr(args, "scene", None) or getattr(args, "brief_type", None)
    from prompts_enhancer import load_scene_negatives
    scene_negatives = ",".join(load_scene_negatives(scene))

    result = enhance(
        prompt=prompt,
        style_id=args.style_id,
        style_dict=style,
        style_dicts=style_mix,
        style_migration_strength=style_strength,
        include_negative=args.negative,
        inject_quality_terms=bool(getattr(args, "quality", False)),
        scene_terms=scene_negatives,
        ban_terms=getattr(args, "ban", "") or "",
    )

    return result["enhanced_prompt"], result["negative_prompt"] if args.negative else None, style, style_mix


BRIEF_FIELD_ORDER = ["主题", "场景", "光影", "构图", "镜头", "色调", "画面比例", "风格参考", "禁止"]
BRIEF_TYPES = ["auto", "product-photography", "ui", "video-storyboard"]


def build_brief(
    fields: list[tuple[str, str]],
    brief_type: str = "auto",
) -> dict:
    """Build a structured design brief from Chinese or English field pairs."""
    if brief_type not in BRIEF_TYPES:
        brief_type = "auto"
    ordered: dict[str, str] = {}
    seen_keys: set[str] = set()
    eng_to_cn = {
        "subject": "主题", "scene": "场景", "lighting": "光影",
        "composition": "构图", "lens": "镜头", "tone": "色调",
        "aspect": "画面比例", "style": "风格参考", "ban": "禁止",
    }
    for key, value in fields:
        normalized_key = eng_to_cn.get(key.strip().lower(), key.strip())
        if normalized_key and not seen_keys.intersection({normalized_key}):
            ordered[normalized_key] = value
            seen_keys.add(normalized_key)
    return {
        "brief_type": brief_type,
        "fields": ordered,
    }


def _field_text(brief: dict, key: str, default: str = "") -> str:
    return brief.get("fields", {}).get(key, default)


def _prompt_from_brief(brief: dict) -> str:
    """Build a natural-language prompt from a structured brief's fields."""
    parts: list[str] = []
    f = brief.get("fields", {})

    subject = f.get("主题") or f.get("subject", "")
    if subject:
        parts.append(subject)

    scene = f.get("场景") or f.get("scene", "")
    if scene:
        parts.append(scene)

    lighting = f.get("光影") or f.get("lighting", "")
    if lighting:
        parts.append(lighting)

    composition = f.get("构图") or f.get("composition", "")
    if composition:
        parts.append(composition)

    lens = f.get("镜头") or f.get("lens", "")
    if lens:
        parts.append(lens)

    tone = f.get("色调") or f.get("tone", "")
    if tone:
        parts.append(tone)

    aspect = f.get("画面比例") or f.get("aspect", "")
    if aspect:
        parts.append(aspect)

    style_ref = f.get("风格参考") or f.get("style", "")
    if style_ref:
        parts.append(style_ref)

    return ", ".join(parts)


def brief_to_prompt(
    brief: dict,
    style_id: str | None = None,
    style_dict: dict | None = None,
    include_negative: bool = False,
    inject_quality: bool = False,
    ban_terms: str = "",
) -> str:
    """Convert a structured brief into an enhanced prompt using the existing pipeline."""
    from prompts_enhancer import enhance as enh, load_scene_negatives

    raw_prompt = _prompt_from_brief(brief)
    if not raw_prompt:
        return ""

    ban = _field_text(brief, "禁止") or _field_text(brief, "ban")
    # Merge brief's "禁止" field with CLI --ban terms
    merged_ban = ",".join(filter(None, [ban, ban_terms]))
    scene = brief.get("brief_type", "")
    scene_neg = ",".join(load_scene_negatives(scene))

    result = enh(
        prompt=raw_prompt,
        style_id=style_id,
        style_dict=style_dict,
        include_negative=include_negative,
        inject_quality_terms=inject_quality,
        scene_terms=scene_neg,
        ban_terms=merged_ban or "",
    )

    return result["enhanced_prompt"]


def load_brief_templates() -> list[dict]:
    """Load brief templates from data/briefs.csv."""
    filepath = skill_dir() / "data" / "briefs.csv"
    if not filepath.exists():
        return []
    import csv
    with open(filepath, "r", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def resolve_brief_template(template_ref: str | None) -> dict | None:
    """Resolve a brief template by id, Chinese name, or partial match."""
    if not template_ref:
        return None
    templates = load_brief_templates()
    ref_lower = template_ref.strip().lower()
    for t in templates:
        if t.get("id", "").lower() == ref_lower:
            return t
    for t in templates:
        name_cn = t.get("name_cn", "")
        if ref_lower in name_cn.lower():
            return t
    for t in templates:
        if ref_lower in t.get("id", "").lower() or ref_lower in t.get("name_cn", "").lower():
            return t
    return None


def apply_brief_template(template: dict, user_fields: list[tuple[str, str]]) -> dict:
    """Merge a brief template with user-provided fields.

    - Start with defaults from the template.
    - Override with user field values.
    - Build the prompt using the template's prompt_template.
    - Check required_fields are present.
    """
    # Parse defaults
    defaults_raw = template.get("defaults", "").strip()
    default_pairs: list[tuple[str, str]] = []
    if defaults_raw:
        for part in defaults_raw.split(","):
            part = part.strip()
            if "=" in part:
                key, value = part.split("=", 1)
                key = key.strip()
                if key:
                    default_pairs.append((key, value.strip()))

    # Parse required fields
    required_raw = template.get("required_fields", "").strip()
    required_fields = [f.strip() for f in required_raw.split(",") if f.strip()]

    # Merge: defaults → user fields (user wins)
    user_dict = {key: value for key, value in user_fields}
    merged: list[tuple[str, str]] = []
    seen: set[str] = set()
    for key, value in default_pairs:
        merged.append((key, value))
        seen.add(key)
    for key, value in user_fields:
        if key not in seen:
            merged.append((key, value))
            seen.add(key)
        else:
            # Override default
            merged = [(k, v if k != key else value) for k, v in merged]

    # Check required
    merged_keys = {k for k, _ in merged}
    missing = [f for f in required_fields if f not in merged_keys]
    if missing:
        raise SystemExit(
            f"Brief template '{template.get('id', '')}' requires fields: "
            f"{', '.join(missing)}. "
            f"Expected fields: {template.get('fields', '')}"
        )

    # Build the brief
    brief = build_brief(merged, brief_type=template.get("id", "auto"))

    # Render prompt from template
    tmpl = template.get("prompt_template", "")
    if tmpl:
        rendered = tmpl
        for key, value in merged:
            rendered = rendered.replace("{" + key + "}", value)
        brief["prompt"] = rendered

    return brief


def brief(args: argparse.Namespace) -> None:
    """Generate a structured brief from natural-language field pairs."""
    fields: list[tuple[str, str]] = []
    field_args: list[str] = getattr(args, "field", []) or []
    for fv in field_args:
        if "=" not in fv:
            raise SystemExit(f"Invalid --field value '{fv}'. Use key=value.")
        key, raw = fv.split("=", 1)
        key = key.strip()
        if key:
            fields.append((key, raw.strip()))

    template = resolve_brief_template(getattr(args, "template", None))

    if template:
        brief = apply_brief_template(template, fields)
    else:
        if not fields:
            raise SystemExit("At least one --field is required. Example: --field '主题=一杯桂花乌龙茶'")
        brief = build_brief(fields, brief_type=args.brief_type or "auto")

    if getattr(args, "to_prompt", False):
        style_id = getattr(args, "style_id", None)
        style_name = getattr(args, "style_name", None)
        style_dict = None
        if style_name:
            suggestions = search_styles(style_name, limit=1)
            if suggestions:
                style_dict = suggestions[0]
                style_id = style_dict.get("id", "")
        elif style_id:
            from prompts_enhancer import load_styles
            styles = load_styles()
            for s in styles:
                if s.get("id", "") == style_id.lower().strip():
                    style_dict = s
                    break

        prompt_text = brief_to_prompt(
            brief,
            style_id=style_id,
            style_dict=style_dict,
            include_negative=args.negative,
            inject_quality=bool(getattr(args, "quality", False)),
            ban_terms=getattr(args, "ban", "") or "",
        )
        brief["prompt"] = prompt_text

    if args.format == "json":
        print(json.dumps(brief, ensure_ascii=False, indent=2))
    elif args.format == "markdown":
        print(f"# Design Brief ({brief['brief_type']})")
        print()
        fields_dict = brief.get("fields", {})
        for key, value in fields_dict.items():
            print(f"**{key}**: {value}")
            print()
        if "prompt" in brief:
            print(f"---")
            print(f"**Enhanced Prompt**: {brief['prompt']}")


def split_style_refs(value: str | None) -> list[str]:
    """Split a comma/plus separated style reference list."""
    refs: list[str] = []
    for raw_part in re.split(r"[,+]", value or ""):
        part = raw_part.strip()
        if part and part not in refs:
            refs.append(part)
    return refs


def resolve_batch_styles(args: argparse.Namespace) -> tuple[str, list[dict]]:
    """Resolve styles for batch variants from explicit refs or explore mode."""
    style_refs = split_style_refs(getattr(args, "styles", None))
    if style_refs:
        styles = []
        for style_ref in style_refs:
            style = resolve_style(style_id=style_ref) or resolve_style(style_name=style_ref)
            if not style:
                raise SystemExit(f"Could not resolve style in --styles: {style_ref}")
            styles.append(style)
        return "batch", styles

    if getattr(args, "explore", False):
        styles = search_styles(args.prompt, limit=args.limit, category=args.category)
        if not styles:
            styles = get_random_styles(args.limit)
        return "explore", styles

    raise SystemExit("batch requires --styles or --explore.")


def batch_output_path(output_dir: Path, style_id: str, index: int, variant_index: int, variants_per_style: int) -> str:
    """Return a stable output path for a batch variant."""
    safe_style_id = re.sub(r"[^a-zA-Z0-9_-]+", "-", style_id).strip("-") or "style"
    suffix = f"-{variant_index}" if variants_per_style > 1 else ""
    directory = str(output_dir).replace(os.sep, "/").rstrip("/")
    return f"{directory}/{index:02d}-{safe_style_id}{suffix}.png"


def ab_label_for(labels: list[str], index: int) -> str:
    """Return an A/B label for a one-based variant index."""
    if index <= len(labels):
        return labels[index - 1]
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    if index <= len(alphabet):
        return alphabet[index - 1]
    return f"V{index}"


def build_batch_plan(args: argparse.Namespace) -> dict:
    """Build a deterministic batch generation plan without calling the image API."""
    if args.variants <= 0:
        raise SystemExit("--variants must be positive.")

    mode, styles = resolve_batch_styles(args)
    base_prompt, template, color = apply_template_and_color(args)
    labels = [label.strip() for label in getattr(args, "ab_label", []) if label.strip()]
    variants = []
    index = 1

    for style in styles:
        for variant_index in range(1, args.variants + 1):
            from prompts_enhancer import load_scene_negatives
            scene_neg = ",".join(load_scene_negatives(getattr(args, "scene", None)))
            result = enhance(
                prompt=base_prompt,
                style_dict=style,
                include_negative=args.negative,
                inject_quality_terms=bool(getattr(args, "quality", False)),
                scene_terms=scene_neg,
                ban_terms=getattr(args, "ban", "") or "",
            )
            style_id = style.get("id", "style")
            variants.append({
                "index": index,
                "variant": variant_index,
                "ab_label": ab_label_for(labels, index),
                "style_id": style_id,
                "style_name_cn": style.get("name_cn", ""),
                "style_name_en": style.get("name_en", ""),
                "output": batch_output_path(args.output_dir, style_id, index, variant_index, args.variants),
                "enhanced_prompt": result["enhanced_prompt"],
                "negative_prompt": result["negative_prompt"],
            })
            index += 1

    return {
        "prompt": args.prompt,
        "base_prompt": base_prompt,
        "mode": mode,
        "variants_per_style": args.variants,
        "template_id": template.get("id", "") if template else "",
        "color_id": color.get("id", "") if color else "",
        "variants": variants,
    }


def generate(args: argparse.Namespace) -> None:
    config = load_config()
    model = args.model or config["model"]

    enhanced_prompt, negative_prompt, style, style_mix = prepare_prompt(args)
    _, template, color = apply_template_and_color(args)

    # Parse reference images with optional purpose declarations
    ref_image_paths: list[str] = []
    ref_image_urls: list[str] = []
    ref_purposes: list[str] = []
    for img_val in (args.image or []):
        path_str, purpose = parse_image_arg(str(img_val))
        ref_image_paths.append(path_str)
        if purpose:
            ref_purposes.append(purpose)
    for url_val in (args.image_url or []):
        url_str, purpose = parse_image_arg(url_val)
        ref_image_urls.append(url_str)
        if purpose:
            ref_purposes.append(purpose)

    ref_images = resolve_reference_images(
        images=[Path(p) for p in ref_image_paths] if ref_image_paths else None,
        image_urls=ref_image_urls if ref_image_urls else None,
        purposes=ref_purposes if ref_purposes else None,
    )

    # Parse --payload-json and --payload-merge
    payload_json = _parse_json_arg(args.payload_json, "--payload-json") if args.payload_json else None
    payload_merge = _parse_json_arg(args.payload_merge, "--payload-merge") if args.payload_merge else None

    profile = resolve_profile(
        has_reference_image=bool(ref_images),
        explicit_profile=args.profile,
    )
    payload, endpoint = build_api_payload(
        profile,
        model=model,
        enhanced_prompt=enhanced_prompt,
        negative_prompt=negative_prompt or None,
        size=args.size,
        response_format=args.response_format,
        reference_images=ref_images or None,
        overrides=payload_merge,
        payload_json=payload_json,
    )

    response = post_json(
        f"{config['base_url']}{endpoint}",
        payload,
        config["api_key"],
    )
    image_b64, revised_prompt = extract_image_b64(response)
    save_image(image_b64, args.output)

    output_info = {
        "output": str(args.output),
        "model": model,
        "revised_prompt": revised_prompt,
    }
    if style_mix:
        output_info["style_mix"] = [
            {
                "style_id": item_style.get("id", ""),
                "style_name_cn": item_style.get("name_cn", ""),
                "style_name_en": item_style.get("name_en", ""),
                "weight": item_weight,
            }
            for item_style, item_weight in style_mix
        ]
    elif style:
        output_info["style_id"] = style.get("id", "")
        output_info["style_name_cn"] = style.get("name_cn", "")
    if getattr(args, "style_strength", None) is not None:
        output_info["style_migration_strength"] = args.style_strength
    if template:
        output_info["template_id"] = template.get("id", "")
    if color:
        output_info["color_id"] = color.get("id", "")
    if negative_prompt:
        output_info["negative_prompt"] = negative_prompt

    print(json.dumps(output_info, ensure_ascii=False))
    _maybe_check_update(getattr(args, "no_update_check", False))


def batch(args: argparse.Namespace) -> None:
    """Generate or preview multiple style variants for the same prompt."""
    plan = build_batch_plan(args)
    if args.dry_run:
        if args.format == "json":
            print(json.dumps(plan, ensure_ascii=False, indent=2))
            return
        print(f"Batch plan for: {plan['prompt']}")
        for variant in plan["variants"]:
            print(f"{variant['ab_label']}: {variant['style_id']} -> {variant['output']}")
        return

    config = load_config()
    model = args.model or config["model"]
    for variant in plan["variants"]:
        payload, endpoint = build_api_payload(
            "images-generations",
            model=model,
            enhanced_prompt=variant["enhanced_prompt"],
            negative_prompt=variant["negative_prompt"] or None,
        )
        response = post_json(
            f"{config['base_url']}{endpoint}",
            payload,
            config["api_key"],
        )
        image_b64, revised_prompt = extract_image_b64(response)
        save_image(image_b64, Path(variant["output"]))
        variant["model"] = model
        variant["revised_prompt"] = revised_prompt

    if args.format == "json":
        print(json.dumps(plan, ensure_ascii=False, indent=2))
        return
    for variant in plan["variants"]:
        print(f"{variant['ab_label']}: saved {variant['output']}")
    _maybe_check_update(getattr(args, "no_update_check", False))


def transform(args: argparse.Namespace) -> None:
    config = load_config()
    model = args.model or config["model"]

    enhanced_prompt, negative_prompt, style, style_mix = prepare_prompt(args)
    _, template, color = apply_template_and_color(args)

    # Parse reference images with optional purpose declarations
    ref_image_urls: list[str] = []
    ref_purposes: list[str] = []
    for url_val in (args.image_url or []):
        url_str, purpose = parse_image_arg(url_val)
        ref_image_urls.append(url_str)
        if purpose:
            ref_purposes.append(purpose)

    ref_images = resolve_reference_images(
        image_urls=ref_image_urls if ref_image_urls else None,
        purposes=ref_purposes if ref_purposes else None,
    )

    # Parse --payload-json and --payload-merge
    payload_json = _parse_json_arg(args.payload_json, "--payload-json") if args.payload_json else None
    payload_merge = _parse_json_arg(args.payload_merge, "--payload-merge") if args.payload_merge else None

    profile = resolve_profile(
        is_transform=True,
        has_reference_image=bool(ref_images),
        explicit_profile=args.profile,
    )
    payload, endpoint = build_api_payload(
        profile,
        model=model,
        enhanced_prompt=enhanced_prompt,
        negative_prompt=negative_prompt or None,
        size=args.size,
        input_image_path=args.input,
        reference_images=ref_images or None,
        overrides=payload_merge,
        payload_json=payload_json,
    )

    response = post_json(
        f"{config['base_url']}{endpoint}",
        payload,
        config["api_key"],
    )
    image_b64, revised_prompt = extract_image_b64(response)
    save_image(image_b64, args.output)

    output_info = {
        "output": str(args.output),
        "model": model,
        "revised_prompt": revised_prompt,
    }
    if style_mix:
        output_info["style_mix"] = [
            {
                "style_id": item_style.get("id", ""),
                "style_name_cn": item_style.get("name_cn", ""),
                "style_name_en": item_style.get("name_en", ""),
                "weight": item_weight,
            }
            for item_style, item_weight in style_mix
        ]
    elif style:
        output_info["style_id"] = style.get("id", "")
        output_info["style_name_cn"] = style.get("name_cn", "")
    if getattr(args, "style_strength", None) is not None:
        output_info["style_migration_strength"] = args.style_strength
    if template:
        output_info["template_id"] = template.get("id", "")
    if color:
        output_info["color_id"] = color.get("id", "")
    if negative_prompt:
        output_info["negative_prompt"] = negative_prompt

    print(json.dumps(output_info, ensure_ascii=False))
    _maybe_check_update(getattr(args, "no_update_check", False))


def suggest(args: argparse.Namespace) -> None:
    """Print search suggestions without generating an image."""
    if args.design_system:
        print(json.dumps(get_design_system(args.prompt, category=args.category), ensure_ascii=False, indent=2))
        return

    if args.random:
        output = {}
        if args.domain in {"style", "all"}:
            output["styles"] = get_random_styles(args.limit)
        if args.domain in {"prompt", "all"}:
            output["prompts"] = get_random_prompts(args.limit)
        if args.domain in {"color", "all"}:
            output["colors"] = get_random_colors(args.limit)
    else:
        output = {}
        if args.domain in {"style", "all"}:
            output["styles"] = search_styles(args.prompt, limit=args.limit, category=args.category)
        if args.domain in {"prompt", "all"}:
            output["prompts"] = search_prompts(args.prompt, limit=args.limit, category=args.category)
        if args.domain in {"color", "all"}:
            output["colors"] = search_colors(args.prompt, limit=args.limit, category=args.category)

    if args.format == "json":
        print(json.dumps(output, ensure_ascii=False, indent=2))
        return

    print(f"Suggestions for: {args.prompt}")
    print(f"(Detected as {'simple' if is_simple_prompt(args.prompt) else 'detailed'} prompt)\n")
    for style in output.get("styles", []):
        print(format_style(style))
    for prompt in output.get("prompts", []):
        print(format_prompt(prompt))
    for color in output.get("colors", []):
        print(format_color(color))


def preview_prompt(args: argparse.Namespace) -> None:
    """Print the final prompt payload without calling the image API."""
    enhanced_prompt, negative_prompt, style, style_mix = prepare_prompt(args)
    prompt, template, color = apply_template_and_color(args)
    output = {
        "original_prompt": args.prompt,
        "base_prompt": prompt,
        "enhanced_prompt": enhanced_prompt,
        "negative_prompt": negative_prompt or "",
    }
    if style_mix:
        output["style_mix"] = [
            {
                "style_id": item_style.get("id", ""),
                "style_name_cn": item_style.get("name_cn", ""),
                "style_name_en": item_style.get("name_en", ""),
                "weight": item_weight,
            }
            for item_style, item_weight in style_mix
        ]
    elif style:
        output["style_id"] = style.get("id", "")
        output["style_name_cn"] = style.get("name_cn", "")
        output["style_name_en"] = style.get("name_en", "")
    if getattr(args, "style_strength", None) is not None:
        output["style_migration_strength"] = args.style_strength
    if template:
        output["template_id"] = template.get("id", "")
        output["template_name"] = template.get("name", "")
    if color:
        output["color_id"] = color.get("id", "")
        output["color_name"] = color.get("name", "")

    if args.format == "json":
        print(json.dumps(output, ensure_ascii=False, indent=2))
        return

    print("=" * 60)
    print("PROMPT PREVIEW")
    print("=" * 60)
    print(f"Original: {output['original_prompt']}")
    print(f"Base:     {output['base_prompt']}")
    print(f"Final:    {output['enhanced_prompt']}")
    if output["negative_prompt"]:
        print(f"Negative: {output['negative_prompt']}")
    if style_mix:
        mix_summary = ", ".join(f"{item_style.get('id', '')}:{item_weight:g}" for item_style, item_weight in style_mix)
        print(f"StyleMix: {mix_summary}")
    elif style:
        print(f"Style:    {output.get('style_name_cn', '')} ({output.get('style_id', '')})")
    print("=" * 60)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate or transform images with the Image Craft API.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # ----- generate -----
    gen = subparsers.add_parser("generate", help="Generate an image from text.")
    gen.add_argument("--prompt", required=True)
    gen.add_argument("--output", required=True, type=Path)
    gen.add_argument("--model", default=None)
    gen.add_argument("--style-id", default=None, help="Style ID to apply (e.g. cyberpunk)")
    gen.add_argument("--style-name", default=None, help="Style name to search and auto-apply")
    gen.add_argument("--style-mix", default=None, help="Weighted styles, e.g. cyberpunk:0.7,blender-render:0.3")
    gen.add_argument("--template", default=None, help="Prompt template ID/name/query to render before generation")
    gen.add_argument("--var", action="append", default=[], help="Template variable in key=value form; repeat as needed")
    gen.add_argument("--color", default=None, help="Color palette name/query to append to the prompt")
    gen.add_argument("--negative", action="store_true", help="Include negative prompt")
    gen.add_argument("--quality", action="store_true", help="Append quality terms (default: off)")
    gen.add_argument("--ban", default=None, help="Comma-separated custom ban terms appended to negative prompt")
    gen.add_argument("--scene", default=None, help="Scene name for scene-specific negative prompt terms (e.g. xiaohongshu, portrait)")
    gen.add_argument("--profile", default=None, choices=VALID_PROFILES, help="Request body profile (auto-detected by default)")
    gen.add_argument("--image", action="append", default=[], help="Local reference image (path or path::purpose); repeat for multiple")
    gen.add_argument("--image-url", action="append", default=[], help="Remote reference image URL (url or url::purpose); repeat for multiple")
    gen.add_argument("--size", default=None, help="Image size, e.g. 1024x1024")
    gen.add_argument("--response-format", default=None, choices=["url", "b64_json"], help="API response format")
    gen.add_argument("--payload-json", default=None, help="Complete request body as JSON string (replaces profile-built payload)")
    gen.add_argument("--payload-merge", default=None, help="JSON to deep-merge into the profile-built payload")
    gen.add_argument("--no-update-check", action="store_true", help="Skip update check after generation")
    gen.set_defaults(func=generate)

    # ----- batch -----
    batch_parser = subparsers.add_parser("batch", help="Generate multiple style variants for one prompt.")
    batch_parser.add_argument("--prompt", required=True)
    batch_parser.add_argument("--styles", default=None, help="Comma-separated style IDs/names to generate as variants")
    batch_parser.add_argument("--explore", action="store_true", help="Auto-select styles from local search recommendations")
    batch_parser.add_argument("--limit", type=int, default=3, help="Max styles in explore mode")
    batch_parser.add_argument("--category", default=None, help="Optional style category filter for explore mode")
    batch_parser.add_argument("--variants", type=int, default=1, help="Number of variants per style")
    batch_parser.add_argument("--output-dir", required=True, type=Path)
    batch_parser.add_argument("--ab-label", action="append", default=[], help="Optional A/B label for each generated variant; repeat as needed")
    batch_parser.add_argument("--model", default=None)
    batch_parser.add_argument("--template", default=None)
    batch_parser.add_argument("--var", action="append", default=[])
    batch_parser.add_argument("--color", default=None)
    batch_parser.add_argument("--negative", action="store_true")
    batch_parser.add_argument("--quality", action="store_true")
    batch_parser.add_argument("--ban", default=None, help="Comma-separated custom ban terms appended to negative prompt")
    batch_parser.add_argument("--scene", default=None, help="Scene name for scene-specific negative prompt terms")
    batch_parser.add_argument("--dry-run", action="store_true", help="Print the batch plan without calling the image API")
    batch_parser.add_argument("--no-update-check", action="store_true", help="Skip update check after generation")
    batch_parser.add_argument("-f", "--format", choices=["text", "json"], default="json")
    batch_parser.set_defaults(func=batch)

    # ----- brief -----
    brief_parser = subparsers.add_parser("brief", help="Generate a structured design brief from field pairs.")
    brief_parser.add_argument("--field", action="append", default=[], help="Field in key=value form; repeat as needed (e.g. '主题=一杯桂花乌龙茶放在石桌上')")
    brief_parser.add_argument("--brief-type", choices=BRIEF_TYPES, default="auto", help="Brief type template")
    brief_parser.add_argument("--template", default=None, help="Brief template ID or name from data/briefs.csv; fills defaults and shows expected fields")
    brief_parser.add_argument("--to-prompt", action="store_true", help="Convert the structured brief to an enhanced prompt")
    brief_parser.add_argument("--style-id", default=None, help="Style ID to apply in brief→prompt conversion")
    brief_parser.add_argument("--style-name", default=None, help="Style name to apply in brief→prompt conversion")
    brief_parser.add_argument("--negative", action="store_true", help="Include negative prompt in brief→prompt conversion")
    brief_parser.add_argument("--quality", action="store_true", help="Append quality terms in brief-prompt conversion (default: off)")
    brief_parser.add_argument("--ban", default=None, help="Comma-separated custom ban terms appended to negative prompt in brief→prompt conversion")
    brief_parser.add_argument("-f", "--format", choices=["json", "markdown"], default="json")
    brief_parser.set_defaults(func=brief)

    # ----- transform -----
    trans = subparsers.add_parser("transform", help="Transform an input image with a text instruction.")
    trans.add_argument("--prompt", required=True)
    trans.add_argument("--input", required=True, type=Path)
    trans.add_argument("--output", required=True, type=Path)
    trans.add_argument("--model", default=None)
    trans.add_argument("--style-id", default=None)
    trans.add_argument("--style-name", default=None)
    trans.add_argument("--style-mix", default=None)
    trans.add_argument("--style-strength", type=float, default=None, help="Style migration strength from 0.0 to 1.0")
    trans.add_argument("--template", default=None)
    trans.add_argument("--var", action="append", default=[])
    trans.add_argument("--color", default=None)
    trans.add_argument("--negative", action="store_true")
    trans.add_argument("--quality", action="store_true")
    trans.add_argument("--ban", default=None, help="Comma-separated custom ban terms appended to negative prompt")
    trans.add_argument("--scene", default=None, help="Scene name for scene-specific negative prompt terms")
    trans.add_argument("--profile", default=None, choices=VALID_PROFILES, help="Request body profile (auto-detected by default)")
    trans.add_argument("--image-url", action="append", default=[], help="Remote reference image URL (url or url::purpose); repeat for multiple")
    trans.add_argument("--size", default=None, help="Image size, e.g. 1024x1024")
    trans.add_argument("--response-format", default=None, choices=["url", "b64_json"], help="API response format")
    trans.add_argument("--payload-json", default=None, help="Complete request body as JSON string (replaces profile-built payload)")
    trans.add_argument("--payload-merge", default=None, help="JSON to deep-merge into the profile-built payload")
    trans.add_argument("--no-update-check", action="store_true", help="Skip update check after transformation")
    trans.set_defaults(func=transform)

    # ----- suggest -----
    sugg = subparsers.add_parser("suggest", help="Suggest styles for a prompt without generating.")
    sugg.add_argument("prompt", help="The prompt to get style suggestions for")
    sugg.add_argument("-n", "--limit", type=int, default=5, help="Max suggestions")
    sugg.add_argument("--domain", choices=["style", "prompt", "color", "all"], default="style")
    sugg.add_argument("--category", default=None)
    sugg.add_argument("--design-system", action="store_true", help="Return style + prompt + color recommendations")
    sugg.add_argument("--random", action="store_true", help="Return random recommendations")
    sugg.add_argument("-f", "--format", choices=["text", "json"], default="text")
    sugg.set_defaults(func=suggest)

    # ----- prompt preview -----
    prev = subparsers.add_parser("prompt", help="Preview the enhanced prompt without generating an image.")
    prev.add_argument("--prompt", required=True)
    prev.add_argument("--style-id", default=None, help="Style ID or category to apply (e.g. blender-render or 3d)")
    prev.add_argument("--style-name", default=None, help="Style name or category to search and auto-apply")
    prev.add_argument("--style-mix", default=None, help="Weighted styles, e.g. cyberpunk:0.7,blender-render:0.3")
    prev.add_argument("--style-strength", type=float, default=None, help="Preview style migration strength from 0.0 to 1.0")
    prev.add_argument("--template", default=None, help="Prompt template ID/name/query to render before preview")
    prev.add_argument("--var", action="append", default=[], help="Template variable in key=value form; repeat as needed")
    prev.add_argument("--color", default=None, help="Color palette name/query to append to the prompt")
    prev.add_argument("--negative", action="store_true", help="Include negative prompt")
    prev.add_argument("--quality", action="store_true", help="Append quality terms (default: off)")
    prev.add_argument("--ban", default=None, help="Comma-separated custom ban terms appended to negative prompt")
    prev.add_argument("--scene", default=None, help="Scene name for scene-specific negative prompt terms")
    prev.add_argument("-f", "--format", choices=["text", "json"], default="text")
    prev.set_defaults(func=preview_prompt)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
