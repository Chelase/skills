#!/usr/bin/env python3
"""Prompt enhancer for Image Craft - auto-enhance, inject quality keywords, and generate negative prompts."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path
from typing import Any

from search import search_styles


StyleWeight = tuple[dict[str, Any], float]


# Quality keywords injected to improve model output
QUALITY_TERMS = [
    "masterpiece", "best quality", "high resolution", "detailed",
    "professional", "trending on artstation",
]
QUALITY_NEGATIVE = [
    "lowres", "bad anatomy", "bad hands", "missing fingers",
    "extra digits", "fewer digits", "cropped", "worst quality",
    "low quality", "jpeg artifacts", "blurry", "duplicate",
]


def data_dir() -> Path:
    return Path(__file__).resolve().parents[1] / "data"


def load_csv(filename: str) -> list[dict[str, Any]]:
    filepath = data_dir() / filename
    if not filepath.exists():
        return []
    with open(filepath, "r", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load_styles() -> list[dict[str, Any]]:
    return load_csv("styles.csv")


def load_prompts() -> list[dict[str, Any]]:
    return load_csv("prompts.csv")


def load_colors() -> list[dict[str, Any]]:
    return load_csv("colors.csv")


# ----------------------------------------------------------------------
# Style detection
# ----------------------------------------------------------------------

STYLE_KEYWORDS = {
    "traditional": ["油画", "水彩", "素描", "版画", "国画", "oil", "watercolor", "sketch", "print", "ink wash", "woodcut"],
    "digital": ["像素", "赛博", "蒸汽波", "故障", "pixel", "cyberpunk", "vaporwave", "glitch", "digital"],
    "illustration": ["扁平", "等距", "日系", "美漫", "儿童", "flat", "isometric", "anime", "comic", "children"],
    "photography": ["胶片", "宝丽来", "黑白", "长曝光", "微距", "film", "polaroid", "black and white", "long exposure", "macro"],
    "3d": ["低多边形", "体素", "C4D", "blender", "low poly", "voxel", "3d render"],
    "special": ["双重曝光", "光绘", "红外", "移轴", "double exposure", "light painting", "infrared", "tilt-shift"],
}

CATEGORY_DEFAULT_STYLE_IDS = {
    "3d": "blender-render",
    "digital": "cyberpunk",
    "photography": "film-noir",
    "illustration": "isometric",
    "traditional": "oil-painting",
    "effect": "double-exposure",
    "special": "double-exposure",
}


ASPECT_RATIO_PATTERNS = {
    "16:9": "16:9 widescreen cinematic aspect ratio",
    "9:16": "9:16 vertical portrait aspect ratio",
    "1:1": "1:1 square composition",
    "4:3": "4:3 classic frame aspect ratio",
    "3:4": "3:4 vertical frame aspect ratio",
    "21:9": "21:9 ultra-wide cinematic aspect ratio",
}


SCENE_PHRASE_MAP = [
    ("3d风格", "3D render style"),
    ("3D风格", "3D render style"),
    ("未来科幻城市", "futuristic sci-fi city"),
    ("科幻城市", "sci-fi city"),
    ("未来城市", "futuristic city"),
    ("宏大场景", "epic large-scale scene"),
    ("飞行汽车", "flying cars"),
    ("傍晚蓝调时分", "blue hour at dusk"),
    ("蓝调时分", "blue hour"),
    ("阴天", "overcast weather"),
    ("高楼林立", "dense skyline of towering skyscrapers"),
    ("雾蒙蒙", "hazy atmosphere"),
    ("灰色天空", "grey sky"),
    ("一望无际", "boundless urban sprawl stretching to the horizon"),
    ("半空场景", "mid-air viewpoint"),
    ("城市高空俯瞰", "high-altitude aerial view over the city"),
    ("高空俯瞰", "high-altitude aerial view"),
    ("霓虹灯占比不多", "subtle restrained neon accents"),
    ("霓虹灯不多", "subtle restrained neon accents"),
    ("城市灯光", "city lights glowing through the haze"),
]


PUNCTUATION_RE = re.compile(r"[，、；;。]+")
GENERIC_STYLE_PHRASES = {"3D render style"}


def detect_style_category(prompt: str) -> str | None:
    """Detect which style category a prompt mentions."""
    prompt_lower = prompt.lower()
    for category, keywords in STYLE_KEYWORDS.items():
        for kw in keywords:
            if kw.lower() in prompt_lower:
                return category
    return None


def normalize_aspect_ratios(prompt: str) -> tuple[str, list[str]]:
    """Remove raw aspect-ratio tokens and return professional composition phrases."""
    composition_terms: list[str] = []
    normalized = prompt
    for raw, phrase in ASPECT_RATIO_PATTERNS.items():
        if raw in normalized:
            composition_terms.append(phrase)
            normalized = normalized.replace(raw, "")
    normalized = re.sub(r"\s*,\s*,+", ", ", normalized)
    normalized = re.sub(r"\s{2,}", " ", normalized).strip(" ,，、")
    return normalized, composition_terms


def normalize_visual_prompt(prompt: str, suppress_generic_style: bool = False) -> str:
    """Convert common Chinese visual scene descriptors into compact English prompt phrases.

    This is not a general translation layer. It is a deterministic prompt-normalization
    pass for frequent image-generation descriptors, so style templates receive a clean
    scene phrase instead of awkward mixed-language fragments.
    """
    source, composition_terms = normalize_aspect_ratios(prompt.strip())
    remaining = source
    phrases: list[str] = []

    for chinese, english in SCENE_PHRASE_MAP:
        if chinese in remaining:
            if not (suppress_generic_style and english in GENERIC_STYLE_PHRASES):
                phrases.append(english)
            remaining = remaining.replace(chinese, "")

    leftovers = [part.strip() for part in PUNCTUATION_RE.split(remaining) if part.strip()]
    for part in leftovers:
        if part and part not in phrases:
            phrases.append(part)

    phrases.extend(term for term in composition_terms if term not in phrases)
    if not phrases:
        return prompt.strip()

    return ", ".join(phrases)


# ----------------------------------------------------------------------
# Simple prompt detection
# ----------------------------------------------------------------------

def is_simple_prompt(prompt: str) -> bool:
    """Return True if the prompt is short / lacks technical descriptors."""
    # Strip placeholder syntax like {subject}
    stripped = re.sub(r"\{[^}]+\}", "", prompt).strip()
    words = stripped.split()
    if len(words) <= 8:
        return True
    technical = [
        "style", "lighting", "composition", "perspective", "texture",
        "color palette", "depth of field", "焦距", "光圈", "风格",
    ]
    return not any(t in stripped.lower() for t in technical)


def tokenize(text: str) -> set[str]:
    """Return a set of searchable tokens from text (handles CJK as characters)."""
    # Treat CJK characters as individual tokens; split ASCII on spaces/punctuation
    text_lower = text.lower()
    # Split ASCII text normally, keep each CJK char as its own token
    tokens: set[str] = set()
    current = ""
    for ch in text_lower:
        if "\u4e00" <= ch <= "\u9fff":
            if current:
                tokens.update(current.split())
                current = ""
            tokens.add(ch)
        else:
            current += ch
    if current:
        tokens.update(current.split())
    # Remove empty tokens
    tokens.discard("")
    return tokens


# ----------------------------------------------------------------------
# Enhancement
# ----------------------------------------------------------------------

def build_style_enhancement(style: dict[str, Any]) -> str:
    """Build style modifier string from a style dict."""
    parts = []

    template = style.get("prompt_template", "")
    if template:
        parts.append(template)

    keywords = style.get("keywords", "")
    if keywords:
        parts.append(f"keywords: {keywords}")

    return ", ".join(parts)


def normalize_style_weights(styles: list[StyleWeight]) -> list[StyleWeight]:
    """Return positive style weights normalized to percentages, highest first."""
    weighted = [(style, weight) for style, weight in styles if weight > 0]
    if not weighted:
        return []

    total = sum(weight for _, weight in weighted)
    if total <= 0:
        equal = 1.0 / len(weighted)
        return [(style, equal) for style, _ in weighted]

    normalized = [(style, weight / total) for style, weight in weighted]
    return sorted(normalized, key=lambda item: item[1], reverse=True)


def suggest_styles_for_prompt(prompt: str, limit: int = 3) -> list[dict[str, Any]]:
    """Suggest styles via the unified Phase 2 search backend."""
    category = detect_style_category(prompt)
    results = search_styles(prompt, limit=limit, category=category)
    if results:
        return results
    # Broaden intentionally when the category hint was too restrictive.
    return search_styles(prompt, limit=limit, category=None)


def apply_style_enhancement(prompt: str, style: dict[str, Any]) -> str:
    """Merge the user's prompt with style enhancement terms."""
    template = style.get("prompt_template", "")
    if not template:
        return normalize_visual_prompt(prompt)

    # Replace {subject} placeholder with actual prompt
    subject = normalize_visual_prompt(prompt, suppress_generic_style=True).strip().rstrip(",.。")
    if "," in subject:
        template = template.replace("{subject} in ", "{subject}, in ", 1)
    if subject.lower().startswith(("a ", "an ")):
        template = template.replace("A {subject}", "{subject}", 1)
        template = template.replace("An {subject}", "{subject}", 1)
    enhanced = template.replace("{subject}", subject)
    return enhanced


def format_style_mix_description(weighted_styles: list[StyleWeight]) -> str:
    """Build a compact description of the blended style influences."""
    parts: list[str] = []
    for style, weight in weighted_styles:
        percent = round(weight * 100)
        name = style.get("name_en") or style.get("id", "style")
        keywords = style.get("keywords", "").strip()
        if keywords:
            parts.append(f"{percent}% {name} influence ({keywords})")
        else:
            parts.append(f"{percent}% {name} influence")
    return ", ".join(parts)


def apply_style_mix_enhancement(prompt: str, styles: list[StyleWeight]) -> str:
    """Merge the user's prompt with multiple weighted style influences."""
    weighted_styles = normalize_style_weights(styles)
    if not weighted_styles:
        return normalize_visual_prompt(prompt)

    primary_style = weighted_styles[0][0]
    enhanced = apply_style_enhancement(prompt, primary_style)
    mix_description = format_style_mix_description(weighted_styles)
    if mix_description:
        enhanced = f"{enhanced}, blended style mix: {mix_description}"
    return enhanced


def style_migration_instruction(prompt: str, style: dict[str, Any], strength: float = 1.0) -> str:
    """Build an image-to-image instruction for migrating a source image toward a style."""
    bounded_strength = min(1.0, max(0.0, strength))
    style_percent = round(bounded_strength * 100)
    source_percent = 100 - style_percent
    style_name = style.get("name_en") or style.get("id", "target style")
    keywords = style.get("keywords", "").strip()
    normalized_prompt = normalize_visual_prompt(prompt)

    parts = [
        normalized_prompt,
        f"target style: {style_name}",
        f"style migration strength: {style_percent}%",
        f"preserve {source_percent}% of the source image structure, subject identity, and composition",
    ]
    if keywords:
        parts.append(f"style keywords: {keywords}")
    return ", ".join(parts)


# ----------------------------------------------------------------------
# Quality injection
# ----------------------------------------------------------------------

QUALITY_POSITIVE = ", ".join(QUALITY_TERMS)

QUALITY_NEGATIVE_STR = ", ".join(QUALITY_NEGATIVE)


def inject_quality(prompt: str) -> str:
    """Append quality-positive terms to the prompt."""
    return f"{prompt.strip()}, {QUALITY_POSITIVE}"


def unique_terms(terms: list[str]) -> list[str]:
    """Return terms with stable de-duplication, case-insensitive."""
    seen: set[str] = set()
    unique: list[str] = []
    for term in terms:
        clean = term.strip()
        if not clean:
            continue
        key = clean.lower()
        if key in seen:
            continue
        seen.add(key)
        unique.append(clean)
    return unique


def load_scene_negatives(scene: str | None = None) -> list[str]:
    """Load scene-specific negative terms from data/negatives.csv.

    If a scene name is provided, return the matched scene's negative terms.
    Otherwise return an empty list.
    """
    if not scene:
        return []
    filepath = data_dir() / "negatives.csv"
    if not filepath.exists():
        return []
    import csv
    scene_lower = scene.lower().strip()
    with open(filepath, "r", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            row_id = row.get("id", "").lower().strip()
            row_name = row.get("name_cn", "").lower().strip()
            if row_id == scene_lower or row_name == scene_lower:
                neg = row.get("negative_prompt", "").strip()
                if neg:
                    return [t.strip() for t in neg.split(",") if t.strip()]
    return []


def generate_negative_prompt(
    style: dict[str, Any] | None = None,
    styles: list[StyleWeight] | None = None,
    scene_terms: str = "",
    ban_terms: str = "",
) -> str:
    """Generate a negative prompt.

    Always include general quality negatives.
    If a style is provided, also append the style's negative_prompt column.
    If scene_terms is provided, parse them as comma-separated scene negatives.
    If ban_terms is provided, parse them as user-provided ban terms.
    """
    parts = list(QUALITY_NEGATIVE)
    if style:
        style_neg = style.get("negative_prompt", "").strip()
        if style_neg:
            parts.extend(term.strip() for term in style_neg.split(",") if term.strip())
    for style_dict, _ in normalize_style_weights(styles or []):
        style_neg = style_dict.get("negative_prompt", "").strip()
        if style_neg:
            parts.extend(term.strip() for term in style_neg.split(",") if term.strip())
    if scene_terms:
        parts.extend(t.strip() for t in scene_terms.split(",") if t.strip())
    if ban_terms:
        parts.extend(t.strip() for t in ban_terms.split(",") if t.strip())
    return ", ".join(unique_terms(parts))


# ----------------------------------------------------------------------
# Full enhancement pipeline
# ----------------------------------------------------------------------

def enhance(
    prompt: str,
    style_id: str | None = None,
    style_dict: dict[str, Any] | None = None,
    style_dicts: list[StyleWeight] | None = None,
    style_migration_strength: float | None = None,
    include_negative: bool = False,
    inject_quality_terms: bool = False,
    scene_terms: str = "",
    ban_terms: str = "",
) -> dict[str, Any]:
    """Fully enhance a user prompt.

    If both style_dict and style_id are provided, style_dict wins. style_id is
    resolved only when style_dict is None.

    Returns a dict with keys:
      - original_prompt
      - enhanced_prompt
      - negative_prompt
      - style_id
      - style_name_cn
    """
    # Determine style
    style: dict[str, Any] | None = None
    weighted_styles = normalize_style_weights(style_dicts or [])
    style_name_cn = ""
    detected_style_id = ""

    if weighted_styles:
        detected_style_id = ",".join(style.get("id", "") for style, _ in weighted_styles)
        style_name_cn = ",".join(style.get("name_cn", "") for style, _ in weighted_styles)
    elif style_dict is not None:
        style = style_dict
        detected_style_id = style.get("id", "")
        style_name_cn = style.get("name_cn", "")
    elif style_id:
        normalized_style_id = style_id.lower().strip()
        default_style_id = CATEGORY_DEFAULT_STYLE_IDS.get(normalized_style_id)
        target_style_id = default_style_id or normalized_style_id
        styles = load_styles()
        for s in styles:
            if s.get("id", "") == target_style_id:
                style = s
                detected_style_id = s.get("id", "")
                style_name_cn = s.get("name_cn", "")
                break

    # Apply style enhancement
    enhanced = prompt
    if style and style_migration_strength is not None:
        enhanced = style_migration_instruction(prompt, style, style_migration_strength)
    elif weighted_styles:
        enhanced = apply_style_mix_enhancement(prompt, weighted_styles)
    elif style:
        enhanced = apply_style_enhancement(prompt, style)

    # Inject quality terms
    if inject_quality_terms:
        enhanced = inject_quality(enhanced)

    # Negative prompt
    negative = generate_negative_prompt(style, weighted_styles, scene_terms, ban_terms) if include_negative else ""

    return {
        "original_prompt": prompt,
        "enhanced_prompt": enhanced,
        "negative_prompt": negative,
        "style_id": detected_style_id,
        "style_name_cn": style_name_cn,
        "style_mix": [
            {
                "style_id": style.get("id", ""),
                "style_name_cn": style.get("name_cn", ""),
                "style_name_en": style.get("name_en", ""),
                "weight": weight,
            }
            for style, weight in weighted_styles
        ],
        "is_simple": is_simple_prompt(prompt),
    }


# ----------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------

def build_parser():
    import argparse
    parser = argparse.ArgumentParser(description="Enhance image generation prompts.")
    parser.add_argument("prompt", help="The user's prompt")
    parser.add_argument("--style-id", help="Style ID to apply (e.g. cyberpunk)")
    parser.add_argument("--style-name", help="Style name to search and auto-apply")
    parser.add_argument("--negative", action="store_true", help="Include negative prompt in output")
    parser.add_argument("--quality", action="store_true", help="Append quality terms (default: off)")
    parser.add_argument("--suggest", action="store_true", help="Suggest styles for the prompt")
    parser.add_argument("-f", "--format", choices=["text", "json"], default="text")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    style_dict = None
    style_id = args.style_id or ""

    if args.style_name:
        suggestions = suggest_styles_for_prompt(args.style_name, limit=1)
        if suggestions:
            style_dict = suggestions[0]
            style_id = style_dict.get("id", "")

    result = enhance(
        prompt=args.prompt,
        style_id=style_id or None,
        style_dict=style_dict,
        include_negative=args.negative,
        inject_quality_terms=args.quality,
    )

    if args.format == "json":
        import json
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0

    print("=" * 60)
    print("PROMPT ENHANCEMENT REPORT")
    print("=" * 60)
    print(f"Original:  {result['original_prompt']}")
    print(f"Enhanced:  {result['enhanced_prompt']}")
    if result["negative_prompt"]:
        print(f"Negative:  {result['negative_prompt']}")
    print(f"Style:     {result['style_name_cn']} ({result['style_id']})")
    print(f"Detected as simple prompt: {result['is_simple']}")
    print("=" * 60)

    if args.suggest:
        suggestions = suggest_styles_for_prompt(args.prompt)
        print(f"\nStyle suggestions for this prompt ({len(suggestions)} found):")
        for i, s in enumerate(suggestions, 1):
            print(f"  {i}. {s.get('name_cn', '')} ({s.get('name_en', '')}) - {s.get('category', '')}")
            print(f"     Keywords: {s.get('keywords', '')}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
