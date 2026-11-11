#!/usr/bin/env python3
"""Check whether a newer version of image-craft is available on GitHub.

Reads the local version from ``SKILL.md`` frontmatter and compares it against
the latest tag on ``github.com/Chelase/image-craft``.  Results are cached for
24 hours to avoid hammering the API on every image generation.

Environment variables
---------------------
``IMAGE_CRAFT_DISABLE_UPDATE_CHECK``
    Set to ``1`` to skip the check entirely.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = "Chelase/image-craft"
CACHE_DIR_NAME = ".cache"
CACHE_FILE_NAME = "update_check.json"
CACHE_TTL_SECONDS = 24 * 60 * 60  # 24 hours


def skill_dir() -> Path:
    return Path(__file__).resolve().parents[1]


def _frontmatter_version(skill_md: Path) -> str | None:
    """Extract the ``version`` value from SKILL.md YAML frontmatter."""
    try:
        text = skill_md.read_text(encoding="utf-8")
    except OSError:
        return None

    # Match between the first pair of '---' fences
    m = re.search(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return None

    for line in m.group(1).splitlines():
        if line.strip().startswith("version:"):
            _, _, val = line.partition(":")
            return val.strip().strip("\"'")
    return None


def _parse_semver(v: str) -> tuple[int, ...]:
    """Parse ``x.y.z`` into a comparable tuple; non-numeric parts become 0."""
    parts: list[int] = []
    for p in v.split("."):
        try:
            parts.append(int(p))
        except ValueError:
            parts.append(0)
    return tuple(parts)


def get_local_version() -> str | None:
    return _frontmatter_version(skill_dir() / "SKILL.md")


def get_remote_latest_tag() -> str | None:
    """Fetch the latest tag name from the GitHub API."""
    url = f"https://api.github.com/repos/{REPO}/tags?per_page=1"
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            tags = json.loads(resp.read().decode("utf-8"))
        if isinstance(tags, list) and tags:
            return tags[0].get("name", "").lstrip("v")
    except (urllib.error.URLError, OSError, json.JSONDecodeError):
        return None
    return None


def get_remote_skill_md_version() -> str | None:
    """Fallback: read the raw SKILL.md on GitHub and extract its version."""
    url = f"https://raw.githubusercontent.com/{REPO}/master/SKILL.md"
    req = urllib.request.Request(url, headers={"Accept": "text/plain"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            text = resp.read().decode("utf-8")
    except (urllib.error.URLError, OSError):
        return None

    m = re.search(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return None
    for line in m.group(1).splitlines():
        if line.strip().startswith("version:"):
            _, _, val = line.partition(":")
            return val.strip().strip("\"'")
    return None


def get_remote_version() -> str | None:
    return get_remote_latest_tag() or get_remote_skill_md_version()


def _cache_path() -> Path:
    return skill_dir() / CACHE_DIR_NAME / CACHE_FILE_NAME


def _read_cache() -> dict | None:
    p = _cache_path()
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _write_cache(data: dict) -> None:
    p = _cache_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def should_check() -> bool:
    """Return True if the cache has expired or doesn't exist."""
    cache = _read_cache()
    if not cache:
        return True
    last_checked = cache.get("checked_at", 0)
    return (time.time() - last_checked) >= CACHE_TTL_SECONDS


def mark_checked() -> None:
    _write_cache({"checked_at": time.time()})


def check_for_update() -> dict | None:
    """Return ``{"local": str, "remote": str}`` if an update is available,
    otherwise ``None``.

    Returns ``None`` on any network/parse failure so the caller never crashes.
    """
    if os.environ.get("IMAGE_CRAFT_DISABLE_UPDATE_CHECK", "").strip() == "1":
        return None

    if not should_check():
        return None

    local_ver = get_local_version()
    remote_ver = get_remote_version()

    # Always mark as checked to avoid retrying on every call after a failure
    mark_checked()

    if not local_ver or not remote_ver:
        return None

    if _parse_semver(remote_ver) > _parse_semver(local_ver):
        return {"local": local_ver, "remote": remote_ver}

    return None


def format_update_message(info: dict) -> str:
    return (
        f"\nImage Craft update available: {info['local']} -> {info['remote']}\n"
        f"Run: git -C \"{skill_dir()}\" pull\n"
    )


def main() -> int:
    """CLI entry point: check and print update info; exit 0 always."""
    info = check_for_update()
    if info:
        print(format_update_message(info), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
