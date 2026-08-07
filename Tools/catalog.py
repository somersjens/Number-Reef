#!/usr/bin/env python3
"""Shared reading of the string catalog and the language roster.

Used by both `export_translations.py` and `import_translations.py` so the two
sides can never disagree about what a row means.
"""
from __future__ import annotations

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "Number Reef", "Localizable.xcstrings")
ROSTER = os.path.join(ROOT, "Number Reef", "Localization.swift")
CSV = os.path.join(ROOT, "Tools", "translations.csv")

SOURCE = "en"
DELIMITER = ";"
# Excel only reads a CSV as UTF-8 if it carries a byte-order mark, and this file
# has to survive Amharic, Khmer and Georgian intact.
ENCODING = "utf-8-sig"

FIXED_COLUMNS = ["key", "variant", "max_chars", "instruction"]


def open_sheet(path: str):
    """Open a translation sheet, whatever shape it comes back in.

    A sheet makes a round trip through spreadsheet software and a translator's
    machine before it returns, and comes back with whatever delimiter and
    encoding that chain preferred — Excel on an English locale writes commas,
    on a Dutch one semicolons, and only some of them keep the byte-order mark.
    Sniffing beats insisting, so the returned rows are read on their own terms.

    Returns (rows, delimiter, encoding) so the caller can report what it found.
    """
    raw = open(path, "rb").read()
    if not raw.strip():
        raise SystemExit(f"{path}: empty file")

    encoding = ENCODING if raw[:3] == b"\xef\xbb\xbf" else "utf-8"
    try:
        text = raw.decode(encoding)
    except UnicodeDecodeError:
        # Excel on Windows still writes UTF-16 for "Unicode Text", and a sheet
        # saved as CSV from a non-Unicode locale can land in cp1252.
        for fallback in ("utf-16", "cp1252"):
            try:
                text = raw.decode(fallback)
                encoding = fallback
                break
            except UnicodeDecodeError:
                continue
        else:
            raise SystemExit(f"{path}: not readable as UTF-8, UTF-16 or cp1252")

    header = text.split("\n", 1)[0]
    delimiter = max((";", ",", "\t"), key=header.count)
    if header.count(delimiter) == 0:
        raise SystemExit(f"{path}: no ';', ',' or tab in the header row")

    import csv as _csv
    import io as _io
    rows = list(_csv.DictReader(_io.StringIO(text), delimiter=delimiter))
    return rows, delimiter, encoding


def languages() -> list[str]:
    """The roster codes, read from Localization.swift so it stays the one list."""
    source = open(ROSTER, encoding="utf-8").read()
    block = re.search(r"static let all: \[AppLanguage\] = \[(.*?)\n    \]",
                      source, re.S)
    if not block:
        raise SystemExit("could not find AppLanguage.all in Localization.swift")
    codes = re.findall(r'AppLanguage\(code:\s*"([^"]+)"', block.group(1))
    if SOURCE not in codes:
        raise SystemExit(f"roster has no {SOURCE!r} row")
    return codes


def load() -> dict:
    return json.load(open(CATALOG, encoding="utf-8"))


def save(catalog: dict) -> None:
    with open(CATALOG, "w", encoding="utf-8") as handle:
        json.dump(catalog, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def substitution_names(entry: dict) -> list[str]:
    """Named substitutions on a key, taken from the source language."""
    source = entry["localizations"].get(SOURCE, {})
    return sorted(source.get("substitutions", {}))


def read_units(localization: dict) -> dict[str, str]:
    """Flatten one language's entry into {variant: value}.

    Variants: "" for the plain string, "plural.one" for a plural variation, and
    "bubbles.plural.one" for a category inside the substitution named `bubbles`.
    """
    units: dict[str, str] = {}
    if "stringUnit" in localization:
        units[""] = localization["stringUnit"]["value"]
    for name, substitution in localization.get("substitutions", {}).items():
        for category, node in substitution.get("variations", {}).get("plural", {}).items():
            units[f"{name}.plural.{category}"] = node["stringUnit"]["value"]
    for category, node in localization.get("variations", {}).get("plural", {}).items():
        units[f"plural.{category}"] = node["stringUnit"]["value"]
    return units


def read_states(localization: dict) -> dict[str, str]:
    """The `state` of each unit, alongside `read_units`' values."""
    states: dict[str, str] = {}
    if "stringUnit" in localization:
        states[""] = localization["stringUnit"].get("state", "new")
    for name, substitution in localization.get("substitutions", {}).items():
        for category, node in substitution.get("variations", {}).get("plural", {}).items():
            states[f"{name}.plural.{category}"] = node["stringUnit"].get("state", "new")
    for category, node in localization.get("variations", {}).get("plural", {}).items():
        states[f"plural.{category}"] = node["stringUnit"].get("state", "new")
    return states


def write_units(units: dict[str, tuple[str, str]], template: dict) -> dict:
    """Rebuild a language's entry from {variant: (value, state)}.

    `template` is the source-language entry, consulted only for the shape of the
    substitutions (their argument number and format specifier), which is part of
    the string's machinery rather than of its translation.
    """
    built: dict = {}
    plural: dict = {}
    substitutions: dict = {}

    for variant, (value, state) in units.items():
        unit = {"stringUnit": {"state": state, "value": value}}
        if variant == "":
            built["stringUnit"] = unit["stringUnit"]
            continue
        parts = variant.split(".")
        if parts[0] == "plural" and len(parts) == 2:
            plural[parts[1]] = unit
            continue
        if len(parts) == 3 and parts[1] == "plural":
            name, category = parts[0], parts[2]
            source = template.get("substitutions", {}).get(name, {})
            entry = substitutions.setdefault(name, {
                "argNum": source.get("argNum"),
                "formatSpecifier": source.get("formatSpecifier"),
                "variations": {"plural": {}},
            })
            entry["variations"]["plural"][category] = unit
            continue
        raise ValueError(f"unrecognised variant {variant!r}")

    if plural:
        built["variations"] = {"plural": plural}
    if substitutions:
        for entry in substitutions.values():
            if entry["argNum"] is None:
                del entry["argNum"]
            if entry["formatSpecifier"] is None:
                del entry["formatSpecifier"]
        built["substitutions"] = substitutions
    return built


FORMAT_SPECIFIER = re.compile(r"%(?:\d+\$)?[#@]?[a-zA-Z@]*[@a-zA-Z]")


def specifiers(value: str) -> list[str]:
    """Every format placeholder in a string, sorted, for comparing two strings.

    `%%` is an escaped percent sign and carries no argument, so it is dropped.
    """
    return sorted(m for m in FORMAT_SPECIFIER.findall(value) if m != "%%")


def argument_indices(value: str, substitutions: dict) -> set[int]:
    """Which of the arguments passed in code a format string actually consumes.

    This, rather than the literal spelling, is what has to match between a
    source string and its translation. There is more than one correct way to
    spell the same argument — `%#@times@` and `%1$lld` both render argument one,
    the first with plural agreement and the second without — and a translator is
    entitled to choose. What is never allowed is reaching for an argument the
    code does not pass, or quietly dropping one.
    """
    indices: set[int] = set()
    automatic = 0
    for token in FORMAT_SPECIFIER.findall(value):
        if token == "%%":
            continue
        explicit = re.match(r"%(\d+)\$", token)
        if explicit:
            indices.add(int(explicit.group(1)))
            continue
        named = re.fullmatch(r"%#@(\w+)@", token)
        if named:
            declared = substitutions.get(named.group(1), {}).get("argNum")
            if declared is not None:
                indices.add(int(declared))
                continue
        automatic += 1
        indices.add(automatic)
    return indices
