#!/usr/bin/env python3
"""Search engine for Image Craft skill data."""

from __future__ import annotations

import argparse
import csv
import json
import random
import difflib
import sys
from pathlib import Path
from typing import Any


def data_dir() -> Path:
    return Path(__file__).resolve().parents[1] / "data"


def load_csv(filename: str) -> list[dict[str, Any]]:
    """Load a CSV file and return list of dicts."""
    filepath = data_dir() / filename
    if not filepath.exists():
        return []
    with open(filepath, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        return list(reader)


def split_terms(query: str) -> list[str]:
    """Split a search query into normalized terms."""
    normalized = query.replace(",", " ").strip().lower()
    terms: list[str] = []
    for term in normalized.split():
        if term and term not in terms:
            terms.append(term)

    # Chinese/Japanese/Korean prompts often arrive without spaces. Add CJK
    # characters as additional terms so queries like "赛博朋克城市" can match
    # the Chinese style name "赛博朋克" instead of relying only on whitespace.
    for char in normalized:
        if "\u4e00" <= char <= "\u9fff" and char not in terms:
            terms.append(char)

    return terms


def field_text(item: dict[str, Any], fields: list[str]) -> str:
    """Combine selected fields into one lowercase search string."""
    return " ".join(str(item.get(field, "")) for field in fields).lower()


def fuzzy_contains(term: str, text: str) -> bool:
    """Return true for direct, substring, or close token matches."""
    if not term:
        return False
    if term in text:
        return True
    tokens = [token.strip(";|/()[]{}.,:，。；、") for token in text.split()]
    tokens.extend(char for char in text if "\u4e00" <= char <= "\u9fff")
    return any(difflib.SequenceMatcher(None, term, token).ratio() >= 0.78 for token in tokens if token)


def score_item(item: dict[str, Any], query: str, weighted_fields: list[tuple[str, int]]) -> int:
    """Score an item using exact, token, and fuzzy matches across weighted fields."""
    query_lower = query.lower().strip()
    terms = split_terms(query)
    if not query_lower and not terms:
        return 0

    score = 0
    for field, weight in weighted_fields:
        value = str(item.get(field, "")).lower()
        if not value:
            continue
        if query_lower and query_lower in value:
            score += weight * 3
        for term in terms:
            if term in value:
                score += weight
            elif fuzzy_contains(term, value):
                score += max(1, weight // 2)
    return score


def filter_category(items: list[dict[str, Any]], category: str | None) -> list[dict[str, Any]]:
    """Filter items by category when a category is provided."""
    if not category:
        return items
    category_lower = category.lower()
    return [item for item in items if category_lower in str(item.get("category", "")).lower()]


def ranked_search(
    items: list[dict[str, Any]],
    query: str,
    weighted_fields: list[tuple[str, int]],
    limit: int = 10,
    category: str | None = None,
) -> list[dict[str, Any]]:
    """Search and rank a list of dictionaries."""
    filtered = filter_category(items, category)
    results = []
    for item in filtered:
        score = score_item(item, query, weighted_fields)
        if score > 0:
            enriched = dict(item)
            enriched["_score"] = score
            results.append(enriched)
    results.sort(key=lambda x: x["_score"], reverse=True)
    return results[:limit]


def search_styles(query: str, limit: int = 10, category: str | None = None) -> list[dict[str, Any]]:
    """Search styles by keyword."""
    styles = load_csv("styles.csv")
    return ranked_search(
        styles,
        query,
        [
            ("name_en", 10),
            ("name_cn", 10),
            ("keywords", 8),
            ("category", 5),
            ("use_cases", 5),
            ("description", 3),
            ("prompt_template", 2),
        ],
        limit,
        category,
    )


def search_prompts(query: str, limit: int = 10, category: str | None = None) -> list[dict[str, Any]]:
    """Search prompt templates by keyword."""
    prompts = load_csv("prompts.csv")
    return ranked_search(
        prompts,
        query,
        [
            ("id", 12),
            ("name", 10),
            ("tags", 8),
            ("category", 5),
            ("template", 3),
            ("example", 2),
        ],
        limit,
        category,
    )


def search_colors(query: str, limit: int = 10, category: str | None = None) -> list[dict[str, Any]]:
    """Search color palettes by keyword."""
    colors = load_csv("colors.csv")
    return ranked_search(
        colors,
        query,
        [
            ("name_en", 10),
            ("name_cn", 10),
            ("emotion", 7),
            ("use_cases", 6),
            ("description", 4),
            ("prompt_description", 4),
        ],
        limit,
        category,
    )


def get_random_styles(count: int = 5) -> list[dict[str, Any]]:
    """Get random style recommendations."""
    styles = load_csv("styles.csv")
    return random.sample(styles, min(count, len(styles)))


def get_random_prompts(count: int = 5) -> list[dict[str, Any]]:
    """Get random prompt templates."""
    prompts = load_csv("prompts.csv")
    return random.sample(prompts, min(count, len(prompts)))


def get_random_colors(count: int = 5) -> list[dict[str, Any]]:
    """Get random color palettes."""
    colors = load_csv("colors.csv")
    return random.sample(colors, min(count, len(colors)))


def get_design_system(query: str, category: str | None = None) -> dict[str, Any]:
    """Generate a complete design system recommendation."""
    styles = search_styles(query, limit=3, category=category)
    prompts = search_prompts(query, limit=3, category=category)
    colors = search_colors(query, limit=3, category=category)
    
    # If no results, get random recommendations
    if not styles:
        styles = get_random_styles(3)
    if not prompts:
        prompts = get_random_prompts(3)
    if not colors:
        colors = get_random_colors(3)
    
    return {
        "query": query,
        "recommended_styles": styles,
        "recommended_prompts": prompts,
        "recommended_colors": colors,
        "prompt_building_tips": [
            "Start with a concrete subject, then add style, palette, lighting, and composition.",
            "Use the style prompt_template as the backbone and replace {subject} with the scene.",
            "Add negative_prompt terms when the selected style provides them.",
        ],
    }


def format_style(style: dict[str, Any]) -> str:
    """Format a style for display."""
    return f"""[Style] {style.get('name_en', '')} ({style.get('name_cn', '')})
   Category: {style.get('category', '')}
   Description: {style.get('description', '')}
   Keywords: {style.get('keywords', '')}
   Prompt Template: {style.get('prompt_template', '')}
   Example: {style.get('example_prompt', '')}
   Difficulty: {style.get('difficulty', '')}
   Score: {style.get('_score', '')}"""


def format_prompt(prompt: dict[str, Any]) -> str:
    """Format a prompt template for display."""
    return f"""[Prompt] {prompt.get('name', '')}
   Category: {prompt.get('category', '')}
   Template: {prompt.get('template', '')}
   Variables: {prompt.get('variables', '')}
   Tags: {prompt.get('tags', '')}
   Quality: {prompt.get('quality', 1)}
   Score: {prompt.get('_score', '')}"""


def format_color(color: dict[str, Any]) -> str:
    """Format a color palette for display."""
    return f"""[Color] {color.get('name_en', '')} ({color.get('name_cn', '')})
   Primary: {color.get('primary_color', '')}
   Secondary: {color.get('secondary_color', '')}
   Accent: {color.get('accent_color', '')}
   Emotion: {color.get('emotion', '')}
   Use Cases: {color.get('use_cases', '')}
   Prompt: {color.get('prompt_description', '')}
   Score: {color.get('_score', '')}"""


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Search engine for Image Craft skill data.")
    parser.add_argument("query", nargs="?", help="Search query")
    parser.add_argument("--domain", choices=["style", "prompt", "color", "all"], default="all",
                        help="Search domain")
    parser.add_argument("--category", help="Filter results by category")
    parser.add_argument("--random", action="store_true", help="Get random recommendations")
    parser.add_argument("--design-system", action="store_true", help="Generate complete design system")
    parser.add_argument("-n", "--limit", type=int, default=5, help="Max results")
    parser.add_argument("-f", "--format", choices=["text", "json"], default="text", help="Output format")
    
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    
    if args.random:
        output: dict[str, Any] = {}
        if args.domain == "style" or args.domain == "all":
            styles = get_random_styles(args.limit)
            output["styles"] = styles
            if args.format == "json":
                pass
            else:
                print("\nRandom Style Recommendations:")
                for style in styles:
                    print(format_style(style))
        
        if args.domain == "prompt" or args.domain == "all":
            prompts = get_random_prompts(args.limit)
            output["prompts"] = prompts
            if args.format != "json":
                print("\nRandom Prompt Templates:")
                for prompt in prompts:
                    print(format_prompt(prompt))
        
        if args.domain == "color" or args.domain == "all":
            colors = get_random_colors(args.limit)
            output["colors"] = colors
            if args.format != "json":
                print("\nRandom Color Palettes:")
                for color in colors:
                    print(format_color(color))
        if args.format == "json":
            print(json.dumps(output, ensure_ascii=False, indent=2))
        
        return 0
    
    if not args.query:
        parser.print_help()
        return 1
    
    if args.design_system:
        system = get_design_system(args.query, category=args.category)
        if args.format == "json":
            print(json.dumps(system, ensure_ascii=False, indent=2))
        else:
            print(f"\nDesign System for: {args.query}")
            print("\nRecommended Styles:")
            for style in system["recommended_styles"]:
                print(format_style(style))
            print("\nRecommended Prompts:")
            for prompt in system["recommended_prompts"]:
                print(format_prompt(prompt))
            print("\nRecommended Colors:")
            for color in system["recommended_colors"]:
                print(format_color(color))
        return 0
    
    # Search mode
    if args.domain == "style" or args.domain == "all":
        styles = search_styles(args.query, args.limit, args.category)
        if styles and args.format != "json":
            print(f"\nStyle Results for '{args.query}':")
            for style in styles:
                print(format_style(style))
    
    if args.domain == "prompt" or args.domain == "all":
        prompts = search_prompts(args.query, args.limit, args.category)
        if prompts and args.format != "json":
            print(f"\nPrompt Results for '{args.query}':")
            for prompt in prompts:
                print(format_prompt(prompt))
    
    if args.domain == "color" or args.domain == "all":
        colors = search_colors(args.query, args.limit, args.category)
        if colors and args.format != "json":
            print(f"\nColor Results for '{args.query}':")
            for color in colors:
                print(format_color(color))
    
    if args.format == "json":
        output = {}
        if args.domain == "style" or args.domain == "all":
            output["styles"] = search_styles(args.query, args.limit, args.category)
        if args.domain == "prompt" or args.domain == "all":
            output["prompts"] = search_prompts(args.query, args.limit, args.category)
        if args.domain == "color" or args.domain == "all":
            output["colors"] = search_colors(args.query, args.limit, args.category)
        print(json.dumps(output, ensure_ascii=False, indent=2))

    return 0


if __name__ == "__main__":
    sys.exit(main())
