#!/usr/bin/env python3
"""Check native UI keys, locale coverage, and the catalog's format/plural contract."""
from copy import deepcopy
import json
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent.parent
locales = ("en", "ko", "ja", "zh-Hans")


def values(node):
    if isinstance(node, dict):
        if "stringUnit" in node:
            yield node["stringUnit"].get("value", "")
        for key, child in node.items():
            if key != "stringUnit":
                yield from values(child)


def arguments(text):
    # These are the only argument types used by the app's format calls.
    result = {}
    next_index = 1
    positional = set()
    for match in re.finditer(r"%%|%(?:(\d+)\$)?(ld|@)|%", text):
        if match.group() == "%%":
            continue
        if match[2] is None:
            raise ValueError("unsupported or unescaped format token")
        positional.add(match[1] is not None)
        if len(positional) > 1:
            raise ValueError("mixed positional and sequential arguments")
        index = int(match[1]) if match[1] else next_index
        kind = match[2]
        if index < 1 or (index in result and result[index] != kind):
            raise ValueError("inconsistent format argument")
        result[index] = kind
        next_index += 1
    return result


def check_catalog(catalog):
    errors = []
    if catalog.get("sourceLanguage") != "en":
        errors.append("sourceLanguage must be en")
    for key, entry in catalog["strings"].items():
        translations = entry.get("localizations", {})
        source = translations.get("en", {})
        source_values = list(values(source))
        try:
            expected = arguments(source_values[0]) if source_values else {}
            for locale in locales:
                translation = translations.get(locale, {})
                translated = list(values(translation))
                if not translated or any(not text.strip() for text in translated):
                    errors.append(f"{key}: missing or empty {locale}")
                if any(arguments(text) != expected for text in translated):
                    errors.append(f"{key}: format arguments differ in {locale}")
                if any("plural" in item.get("variations", {}) for item in translations.values()):
                    forms = translation.get("variations", {}).get("plural", {})
                    required = {"one", "other"} if locale == "en" else {"other"}
                    if not required.issubset(forms):
                        errors.append(f"{key}: missing plural forms in {locale}")
        except ValueError as error:
            errors.append(f"{key}: {error}")
    return errors


def used_keys(text, prefixes):
    literals = re.findall(r'"([a-zA-Z]+(?:\.[a-zA-Z][a-zA-Z0-9]*)+)"', text)
    used = {key for key in literals if key.split(".")[0] in prefixes and not key.endswith((".png", ".json", ".html"))}
    calls = r"L|localizedCount|Text|Button|Toggle|Label|TableColumn|Section|Picker|TextField|DisclosureGroup|ContentUnavailableView|accessibilityLabel|accessibilityHint|accessibilityValue|help"
    used.update(re.findall(r'\b(?:' + calls + r')\(\s*"([a-z]+(?:\.[\w]+)+)"', text))
    return used


def self_test(catalog):
    assert arguments("%1$@ has %2$ld items (100%%)") == arguments("%2$ld: %1$@")
    assert arguments("%%ld") == {}
    for invalid in ("%@ %s", "%1$@ %ld", "%0$@", "%1$@ %1$ld"):
        try:
            arguments(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError(invalid)
    assert not check_catalog(catalog)
    mutations = [
        ("error.invalid", "ko", {"stringUnit": {"value": "%ld"}}),
        ("error.invalid", "ja", {"stringUnit": {"value": "Missing argument"}}),
        ("error.invalid", "zh-Hans", {"stringUnit": {"value": "%2$@"}}),
        ("error.invalid", "en", {"stringUnit": {"value": "%@ %s"}}),
        ("editor.bookmarkCount", "en", {"variations": {"plural": {"other": {"stringUnit": {"value": "%ld bookmarks"}}}}}),
        ("editor.bookmarkCount", "ko", {"stringUnit": {"value": "%ld"}}),
        ("editor.bookmarkCount", "ja", {"variations": {"plural": {"other": {"stringUnit": {"value": ""}}}}}),
    ]
    for key, locale, replacement in mutations:
        changed = deepcopy(catalog)
        changed["strings"][key]["localizations"][locale] = replacement
        assert check_catalog(changed), (key, locale)
    for call in ("Picker", "TextField", "accessibilityLabel", "localizedCount"):
        assert "unknown.missing" in used_keys(f'{call}("unknown.missing", value)', set())
    print("Localization checker regression assertions passed.")


catalog = json.loads((root / "localization/Localizable.xcstrings").read_text())
strings = catalog["strings"]
errors = check_catalog(catalog)

prefixes = {key.split(".")[0] for key in strings}
used = set()
for source in (root / "Sources/GalmuriApp").glob("*.swift"):
    used.update(used_keys(source.read_text(), prefixes))
for key in sorted(used - strings.keys()):
    errors.append(f"native UI key missing: {key}")

if errors:
    raise SystemExit("\n".join(errors))
if "--self-test" in sys.argv:
    self_test(catalog)
print(f"{len(strings)} keys cover all four locales; {len(used)} literal native UI keys found.")
