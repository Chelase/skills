#!/usr/bin/env python3
"""Build API request payloads based on profiles with deep-merge override support."""

from __future__ import annotations

import base64
import mimetypes
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Profile definitions
# ---------------------------------------------------------------------------

PROFILES: dict[str, dict[str, Any]] = {
    "images-generations": {
        "endpoint": "/v1/images/generations",
        "description": "Text-to-image via /v1/images/generations",
        "builder": "_build_images_generations",
    },
    "images-generations-reference": {
        "endpoint": "/v1/images/generations",
        "description": "Text-to-image with reference image(s) via /v1/images/generations",
        "builder": "_build_images_generations_reference",
    },
    "chat-completions-vision": {
        "endpoint": "/v1/chat/completions",
        "description": "Image understanding / vision via /v1/chat/completions",
        "builder": "_build_chat_completions_vision",
    },
    "chat-completions-transform": {
        "endpoint": "/v1/chat/completions",
        "description": "Image transformation via /v1/chat/completions",
        "builder": "_build_chat_completions_transform",
    },
    "custom": {
        "endpoint": "",
        "description": "Custom profile — endpoint and body supplied by caller",
        "builder": "_build_custom",
    },
}

VALID_PROFILES = list(PROFILES.keys())

VALID_IMAGE_PURPOSES = ("style", "composition", "subject", "palette")


def resolve_profile(
    *,
    has_input_image: bool = False,
    has_reference_image: bool = False,
    is_transform: bool = False,
    explicit_profile: str | None = None,
) -> str:
    """Auto-resolve the best profile based on intent signals.

    If *explicit_profile* is given it takes priority.  Otherwise the
    resolution follows the decision table from the ROADMAP.
    """
    if explicit_profile:
        if explicit_profile not in PROFILES:
            raise ValueError(
                f"Unknown profile '{explicit_profile}'. "
                f"Valid profiles: {', '.join(VALID_PROFILES)}"
            )
        return explicit_profile

    if is_transform:
        return "chat-completions-transform"
    if has_reference_image and not has_input_image:
        return "images-generations-reference"
    if has_input_image and not is_transform:
        return "chat-completions-vision"
    return "images-generations"


# ---------------------------------------------------------------------------
# Reference image helpers
# ---------------------------------------------------------------------------

def image_to_data_url(path: Path) -> str:
    """Read a local image file and return a data:-URL with base64 content."""
    mime_type = mimetypes.guess_type(path.name)[0] or "image/png"
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime_type};base64,{encoded}"


def resolve_reference_images(
    images: list[Path | str] | None = None,
    image_urls: list[str] | None = None,
    purposes: list[str] | None = None,
) -> list[dict[str, Any]]:
    """Build a list of image references for the payload.

    Each reference is ``{"type": "image_url", "image_url": {"url": ...}}``.
    If *purposes* is provided (same length as the combined images+urls list),
    each reference also gets a ``"purpose"`` key with one of:
    ``style``, ``composition``, ``subject``, ``palette``.

    Local files are converted to data-URLs; remote URLs are used as-is.
    """
    refs: list[dict[str, Any]] = []
    idx = 0
    if images:
        for p in images:
            path = Path(p) if not isinstance(p, Path) else p
            ref: dict[str, Any] = {
                "type": "image_url",
                "image_url": {"url": image_to_data_url(path)},
            }
            if purposes and idx < len(purposes):
                ref["purpose"] = purposes[idx]
            refs.append(ref)
            idx += 1
    if image_urls:
        for url in image_urls:
            ref = {
                "type": "image_url",
                "image_url": {"url": url},
            }
            if purposes and idx < len(purposes):
                ref["purpose"] = purposes[idx]
            refs.append(ref)
            idx += 1
    return refs


def parse_image_arg(value: str) -> tuple[str, str | None]:
    """Parse an --image or --image-url value that may include a purpose.

    Format: ``path_or_url`` or ``path_or_url::purpose``.
    Returns ``(path_or_url, purpose_or_none)``.
    """
    if "::" in value:
        parts = value.rsplit("::", 1)
        purpose = parts[1].strip().lower()
        if purpose not in VALID_IMAGE_PURPOSES:
            raise ValueError(
                f"Invalid image purpose '{purpose}'. "
                f"Valid purposes: {', '.join(VALID_IMAGE_PURPOSES)}"
            )
        return parts[0].strip(), purpose
    return value, None


# ---------------------------------------------------------------------------
# Profile-specific builders (private)
# ---------------------------------------------------------------------------

def _build_images_generations(
    *,
    model: str,
    enhanced_prompt: str,
    negative_prompt: str | None = None,
    size: str | None = None,
    response_format: str | None = None,
    **_extra: Any,
) -> dict[str, Any]:
    """Build payload for ``/v1/images/generations`` (text-only)."""
    payload: dict[str, Any] = {"model": model, "prompt": enhanced_prompt}
    if negative_prompt:
        payload["negative_prompt"] = negative_prompt
    if size:
        payload["size"] = size
    if response_format:
        payload["response_format"] = response_format
    return payload


def _build_images_generations_reference(
    *,
    model: str,
    enhanced_prompt: str,
    negative_prompt: str | None = None,
    size: str | None = None,
    response_format: str | None = None,
    reference_images: list[dict[str, str]] | None = None,
    **_extra: Any,
) -> dict[str, Any]:
    """Build payload for ``/v1/images/generations`` with reference images.

    Right Codes flavour: the ``image`` field accepts a single URL or a list.
    """
    payload: dict[str, Any] = {"model": model, "prompt": enhanced_prompt}
    if negative_prompt:
        payload["negative_prompt"] = negative_prompt
    if size:
        payload["size"] = size
    if response_format:
        payload["response_format"] = response_format
    if reference_images:
        # Extract raw URLs; the API accepts either a single URL string
        # or a list depending on the provider.
        urls = [r["image_url"]["url"] for r in reference_images]
        payload["image"] = urls[0] if len(urls) == 1 else urls
    return payload


def _build_chat_completions_vision(
    *,
    model: str,
    enhanced_prompt: str,
    reference_images: list[dict[str, str]] | None = None,
    **_extra: Any,
) -> dict[str, Any]:
    """Build payload for ``/v1/chat/completions`` vision understanding."""
    content: list[dict[str, Any]] = [{"type": "text", "text": enhanced_prompt}]
    if reference_images:
        content.extend(reference_images)
    return {
        "model": model,
        "messages": [{"role": "user", "content": content}],
    }


def _build_chat_completions_transform(
    *,
    model: str,
    enhanced_prompt: str,
    negative_prompt: str | None = None,
    input_image_url: str | None = None,
    size: str | None = None,
    **_extra: Any,
) -> dict[str, Any]:
    """Build payload for ``/v1/chat/completions`` image transformation."""
    content: list[dict[str, Any]] = [{"type": "text", "text": enhanced_prompt}]
    if input_image_url:
        content.append(
            {"type": "image_url", "image_url": {"url": input_image_url}}
        )
    payload: dict[str, Any] = {
        "model": model,
        "messages": [{"role": "user", "content": content}],
    }
    if negative_prompt:
        payload["negative_prompt"] = negative_prompt
    if size:
        payload["size"] = size
    return payload


def _build_custom(**kwargs: Any) -> dict[str, Any]:
    """Custom profile — return minimal dict; caller merges overrides."""
    return {}


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def build_payload(
    profile: str,
    *,
    model: str,
    enhanced_prompt: str,
    negative_prompt: str | None = None,
    size: str | None = None,
    response_format: str | None = None,
    input_image_path: Path | None = None,
    reference_images: list[dict[str, Any]] | None = None,
    overrides: dict[str, Any] | None = None,
    payload_json: dict[str, Any] | None = None,
) -> tuple[dict[str, Any], str]:
    """Build an API request payload for the given *profile*.

    Returns ``(payload_dict, endpoint_path)``.

    *overrides* is deep-merged into the payload after the profile builder
    runs, allowing agents or users to add supplier-specific fields.

    *payload_json* replaces the entire profile-built payload when provided.
    Use it when the caller supplies a complete request body from a file or
    inline JSON.
    """
    if profile not in PROFILES:
        raise ValueError(
            f"Unknown profile '{profile}'. "
            f"Valid profiles: {', '.join(VALID_PROFILES)}"
        )

    # If a full payload is supplied, use it directly (with optional merge).
    if payload_json is not None:
        payload = dict(payload_json)
        if overrides:
            payload = deep_merge(payload, overrides)
        endpoint = PROFILES[profile]["endpoint"]
        return payload, endpoint

    builder_name = PROFILES[profile]["builder"]
    builder_fn = globals()[builder_name]

    # Resolve input image for transform / vision profiles.
    input_image_url: str | None = None
    if input_image_path:
        input_image_url = image_to_data_url(input_image_path)

    payload = builder_fn(
        model=model,
        enhanced_prompt=enhanced_prompt,
        negative_prompt=negative_prompt,
        size=size,
        response_format=response_format,
        input_image_url=input_image_url,
        reference_images=reference_images,
    )

    if overrides:
        payload = deep_merge(payload, overrides)

    endpoint = PROFILES[profile]["endpoint"]
    return payload, endpoint


# ---------------------------------------------------------------------------
# Deep merge
# ---------------------------------------------------------------------------

def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    """Recursively merge *override* into *base*, returning a new dict.

    - Scalar values in *override* replace those in *base*.
    - Lists in *override* replace those in *base* (no concatenation).
    - Nested dicts are merged recursively.
    """
    result = dict(base)
    for key, value in override.items():
        if (
            key in result
            and isinstance(result[key], dict)
            and isinstance(value, dict)
        ):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result
