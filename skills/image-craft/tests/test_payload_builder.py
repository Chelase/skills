#!/usr/bin/env python3
"""Unit tests for payload_builder module."""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from payload_builder import (  # noqa: E402
    PROFILES,
    VALID_PROFILES,
    VALID_IMAGE_PURPOSES,
    build_payload,
    deep_merge,
    parse_image_arg,
    resolve_profile,
    resolve_reference_images,
)


class DeepMergeTests(unittest.TestCase):
    def test_flat_merge_override_wins(self) -> None:
        base = {"model": "a", "prompt": "hello"}
        override = {"model": "b"}
        result = deep_merge(base, override)
        self.assertEqual(result["model"], "b")
        self.assertEqual(result["prompt"], "hello")

    def test_nested_dict_merge(self) -> None:
        base = {"messages": [{"role": "user", "content": "hi"}], "model": "a"}
        override = {"messages": [{"role": "user", "content": "bye"}]}
        result = deep_merge(base, override)
        # Lists are replaced, not concatenated
        self.assertEqual(len(result["messages"]), 1)
        self.assertEqual(result["messages"][0]["content"], "bye")

    def test_deep_nested_merge(self) -> None:
        base = {"a": {"b": {"c": 1, "d": 2}}}
        override = {"a": {"b": {"c": 99}}}
        result = deep_merge(base, override)
        self.assertEqual(result["a"]["b"]["c"], 99)
        self.assertEqual(result["a"]["b"]["d"], 2)

    def test_merge_adds_new_keys(self) -> None:
        base = {"model": "a"}
        override = {"extra_field": True}
        result = deep_merge(base, override)
        self.assertTrue(result["extra_field"])

    def test_merge_does_not_mutate_base(self) -> None:
        base = {"a": 1, "b": {"c": 2}}
        override = {"b": {"d": 3}}
        deep_merge(base, override)
        self.assertNotIn("d", base["b"])


class ResolveProfileTests(unittest.TestCase):
    def test_default_is_images_generations(self) -> None:
        self.assertEqual(resolve_profile(), "images-generations")

    def test_explicit_profile_wins(self) -> None:
        self.assertEqual(
            resolve_profile(explicit_profile="chat-completions-vision"),
            "chat-completions-vision",
        )

    def test_transform_resolves_to_chat_completions_transform(self) -> None:
        self.assertEqual(
            resolve_profile(is_transform=True),
            "chat-completions-transform",
        )

    def test_reference_image_resolves_to_reference_profile(self) -> None:
        self.assertEqual(
            resolve_profile(has_reference_image=True),
            "images-generations-reference",
        )

    def test_input_image_resolves_to_vision(self) -> None:
        self.assertEqual(
            resolve_profile(has_input_image=True),
            "chat-completions-vision",
        )

    def test_unknown_profile_raises(self) -> None:
        with self.assertRaises(ValueError):
            resolve_profile(explicit_profile="nonexistent")

    def test_explicit_overrides_auto_detection(self) -> None:
        # Even with transform=True, explicit wins
        self.assertEqual(
            resolve_profile(is_transform=True, explicit_profile="custom"),
            "custom",
        )


class BuildPayloadImagesGenerationsTests(unittest.TestCase):
    def test_minimal_payload(self) -> None:
        payload, endpoint = build_payload(
            "images-generations",
            model="gpt-image-2",
            enhanced_prompt="a cat",
        )
        self.assertEqual(payload["model"], "gpt-image-2")
        self.assertEqual(payload["prompt"], "a cat")
        self.assertNotIn("negative_prompt", payload)
        self.assertEqual(endpoint, "/v1/images/generations")

    def test_with_negative_prompt(self) -> None:
        payload, _ = build_payload(
            "images-generations",
            model="gpt-image-2",
            enhanced_prompt="a cat",
            negative_prompt="blurry",
        )
        self.assertEqual(payload["negative_prompt"], "blurry")

    def test_with_size_and_response_format(self) -> None:
        payload, _ = build_payload(
            "images-generations",
            model="gpt-image-2",
            enhanced_prompt="a cat",
            size="1024x1024",
            response_format="url",
        )
        self.assertEqual(payload["size"], "1024x1024")
        self.assertEqual(payload["response_format"], "url")

    def test_with_overrides(self) -> None:
        payload, _ = build_payload(
            "images-generations",
            model="gpt-image-2",
            enhanced_prompt="a cat",
            overrides={"custom_field": "value"},
        )
        self.assertEqual(payload["custom_field"], "value")


class BuildPayloadReferenceTests(unittest.TestCase):
    def test_reference_images_in_payload(self) -> None:
        refs = [
            {"type": "image_url", "image_url": {"url": "https://example.com/img.png"}}
        ]
        payload, endpoint = build_payload(
            "images-generations-reference",
            model="gpt-image-2",
            enhanced_prompt="like this",
            reference_images=refs,
        )
        # Single reference → string URL
        self.assertEqual(payload["image"], "https://example.com/img.png")
        self.assertEqual(endpoint, "/v1/images/generations")

    def test_multiple_reference_images_become_list(self) -> None:
        refs = [
            {"type": "image_url", "image_url": {"url": "https://a.com/1.png"}},
            {"type": "image_url", "image_url": {"url": "https://b.com/2.png"}},
        ]
        payload, _ = build_payload(
            "images-generations-reference",
            model="gpt-image-2",
            enhanced_prompt="blend these",
            reference_images=refs,
        )
        self.assertIsInstance(payload["image"], list)
        self.assertEqual(len(payload["image"]), 2)


class BuildPayloadChatCompletionsTests(unittest.TestCase):
    def test_vision_profile_builds_messages(self) -> None:
        refs = [
            {"type": "image_url", "image_url": {"url": "https://example.com/img.png"}}
        ]
        payload, endpoint = build_payload(
            "chat-completions-vision",
            model="gpt-image-2",
            enhanced_prompt="describe this",
            reference_images=refs,
        )
        self.assertEqual(endpoint, "/v1/chat/completions")
        messages = payload["messages"]
        self.assertEqual(len(messages), 1)
        content = messages[0]["content"]
        self.assertEqual(len(content), 2)  # text + image
        self.assertEqual(content[0]["type"], "text")
        self.assertEqual(content[1]["type"], "image_url")

    def test_transform_profile_with_input_image(self) -> None:
        # Use a tiny test image path (won't actually read file in this test)
        # We test the builder directly to avoid file I/O
        from payload_builder import _build_chat_completions_transform

        payload = _build_chat_completions_transform(
            model="gpt-image-2",
            enhanced_prompt="make it watercolor",
            negative_prompt="blurry",
            input_image_url="data:image/png;base64,abc123",
        )
        messages = payload["messages"]
        content = messages[0]["content"]
        self.assertEqual(len(content), 2)
        self.assertEqual(payload["negative_prompt"], "blurry")


class ResolveReferenceImagesTests(unittest.TestCase):
    def test_empty_inputs_return_empty_list(self) -> None:
        self.assertEqual(resolve_reference_images(), [])

    def test_image_urls_are_wrapped(self) -> None:
        refs = resolve_reference_images(image_urls=["https://example.com/a.png"])
        self.assertEqual(len(refs), 1)
        self.assertEqual(refs[0]["type"], "image_url")
        self.assertEqual(refs[0]["image_url"]["url"], "https://example.com/a.png")


class ProfileDefinitionsTests(unittest.TestCase):
    def test_all_profiles_have_required_fields(self) -> None:
        for name, prof in PROFILES.items():
            with self.subTest(profile=name):
                self.assertIn("endpoint", prof)
                self.assertIn("description", prof)
                self.assertIn("builder", prof)

    def test_valid_profiles_matches_profiles_dict(self) -> None:
        self.assertEqual(set(VALID_PROFILES), set(PROFILES.keys()))


class ParseImageArgTests(unittest.TestCase):
    def test_plain_path_no_purpose(self) -> None:
        path, purpose = parse_image_arg("/tmp/cat.png")
        self.assertEqual(path, "/tmp/cat.png")
        self.assertIsNone(purpose)

    def test_path_with_purpose(self) -> None:
        path, purpose = parse_image_arg("/tmp/cat.png::style")
        self.assertEqual(path, "/tmp/cat.png")
        self.assertEqual(purpose, "style")

    def test_url_with_purpose(self) -> None:
        url, purpose = parse_image_arg("https://example.com/img.png::composition")
        self.assertEqual(url, "https://example.com/img.png")
        self.assertEqual(purpose, "composition")

    def test_all_valid_purposes(self) -> None:
        for p in VALID_IMAGE_PURPOSES:
            _, purpose = parse_image_arg(f"img.png::{p}")
            self.assertEqual(purpose, p)

    def test_invalid_purpose_raises(self) -> None:
        with self.assertRaises(ValueError):
            parse_image_arg("img.png::invalid")

    def test_double_colon_in_path(self) -> None:
        # rsplit ensures only the last :: is the separator
        path, purpose = parse_image_arg("C:\\Users\\test::style")
        self.assertEqual(path, "C:\\Users\\test")
        self.assertEqual(purpose, "style")


class ResolveReferenceImagesWithPurposeTests(unittest.TestCase):
    def test_purposes_assigned_in_order(self) -> None:
        refs = resolve_reference_images(
            image_urls=["https://a.com/1.png", "https://b.com/2.png"],
            purposes=["style", "composition"],
        )
        self.assertEqual(refs[0]["purpose"], "style")
        self.assertEqual(refs[1]["purpose"], "composition")

    def test_partial_purposes(self) -> None:
        refs = resolve_reference_images(
            image_urls=["https://a.com/1.png", "https://b.com/2.png"],
            purposes=["style"],  # only first has purpose
        )
        self.assertEqual(refs[0]["purpose"], "style")
        self.assertNotIn("purpose", refs[1])

    def test_no_purposes(self) -> None:
        refs = resolve_reference_images(
            image_urls=["https://a.com/1.png"],
        )
        self.assertNotIn("purpose", refs[0])


class PayloadJsonTests(unittest.TestCase):
    def test_payload_json_replaces_profile_payload(self) -> None:
        full_payload = {"model": "custom-model", "prompt": "direct", "extra": True}
        payload, endpoint = build_payload(
            "images-generations",
            model="gpt-image-2",
            enhanced_prompt="unused",
            payload_json=full_payload,
        )
        self.assertEqual(payload["model"], "custom-model")
        self.assertEqual(payload["prompt"], "direct")
        self.assertTrue(payload["extra"])
        # model/enhanced_prompt should NOT appear from profile builder
        self.assertNotIn("negative_prompt", payload)

    def test_payload_json_with_merge(self) -> None:
        full_payload = {"model": "custom", "prompt": "direct"}
        payload, endpoint = build_payload(
            "images-generations",
            model="gpt-image-2",
            enhanced_prompt="unused",
            payload_json=full_payload,
            overrides={"extra_field": "added"},
        )
        self.assertEqual(payload["extra_field"], "added")

    def test_payload_merge_without_payload_json(self) -> None:
        payload, _ = build_payload(
            "images-generations",
            model="gpt-image-2",
            enhanced_prompt="a cat",
            overrides={"seed": 42, "custom": True},
        )
        self.assertEqual(payload["model"], "gpt-image-2")
        self.assertEqual(payload["prompt"], "a cat")
        self.assertEqual(payload["seed"], 42)
        self.assertTrue(payload["custom"])


if __name__ == "__main__":
    unittest.main()
