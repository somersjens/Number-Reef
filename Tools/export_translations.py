#!/usr/bin/env python3
"""Write the string catalog out as one semicolon-separated sheet for translators.

    python3 Tools/export_translations.py [--out path.csv]

One row per translatable unit — a plain string, or one plural category of one —
and one column per language. English and Dutch are filled in as reference; the
other 75 columns are empty and are what comes back filled.

`import_translations.py` reads the result back. The two identity columns, `key`
and `variant`, are what tie a row to its place in the catalog: everything else
on the row may be rewritten, but those two must survive untouched.
"""
from __future__ import annotations

import argparse
import csv
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import catalog  # noqa: E402

REFERENCE = ["en", "nl"]

PLURAL_HELP = {
    "zero": "the form for zero, in languages that have one",
    "one": "the singular form",
    "two": "the dual form, in languages that have one",
    "few": "the 'few' form, in languages that have one",
    "many": "the 'many' form, in languages that have one",
    "other": "the general form, used for every count without its own rule",
}


def length_guide(values: list[str]) -> int:
    """A character budget, derived from the reference translations.

    Not a measured layout constraint — the app scales text down before it clips
    — but Dutch already runs longer than English almost everywhere, so the pair
    is a fair signal of how much room a string was drawn with. Rounded up so it
    reads as the guideline it is.
    """
    longest = max((len(value) for value in values if value), default=0)
    budget = max(longest + 4, math.ceil(longest * 1.25))
    return int(math.ceil(budget / 5.0) * 5)


def instruction(key: str, entry: dict, variant: str, values: dict[str, str]) -> str:
    """Everything a translator needs for this one cell, in prose."""
    parts: list[str] = []

    comment = (entry.get("comment") or "").strip()
    if comment:
        parts.append(comment)

    if variant.startswith("plural."):
        category = variant.split(".")[1]
        parts.append(
            f"PLURAL: this row is {PLURAL_HELP.get(category, category)}. "
            "Fill in only the categories your language actually uses, and add a "
            "row for any it needs that is not listed (copy the row, change "
            f"'{variant}' to e.g. 'plural.few'). Leave the rest empty."
        )
    elif "." in variant:
        name, _, category = variant.split(".")
        parts.append(
            f"PLURAL: the '{category}' form of the '{name}' part, which is "
            f"slotted into the row above with %#@{name}@. Same rules as any "
            "other plural row."
        )

    source = values.get(catalog.SOURCE, "")
    placeholders = catalog.specifiers(source)
    if placeholders:
        parts.append(
            "PLACEHOLDERS: keep " + ", ".join(placeholders) + " exactly as "
            "written — they are replaced with live values. You may put them "
            "anywhere in the sentence; to reorder them use %1$, %2$ and so on."
        )

    if "**" in source:
        parts.append(
            "BOLD: **double asterisks** make a span bold. Keep them, and move "
            "them to whichever words carry the stress in your language."
        )

    budget = length_guide([values.get(code, "") for code in REFERENCE])
    parts.append(
        f"LENGTH: English {len(source)} characters"
        + (f", Dutch {len(values.get('nl', ''))}" if values.get("nl") else "")
        + f". Aim for {budget} or fewer."
    )

    return " ".join(parts)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=catalog.CSV)
    args = parser.parse_args()

    languages = catalog.languages()
    strings = catalog.load()["strings"]

    header = catalog.FIXED_COLUMNS + REFERENCE + [
        code for code in languages if code not in REFERENCE
    ]

    rows = []
    for key in sorted(strings):
        entry = strings[key]
        source_units = catalog.read_units(entry["localizations"][catalog.SOURCE])
        # A reference language may inflect a string English leaves flat — Dutch
        # splits two of the notification lines into singular and plural. Those
        # rows belong in the sheet too, or the one language that has already
        # solved the problem is the one language the translator cannot see.
        variants = dict.fromkeys(source_units)
        for code in REFERENCE:
            variants.update(dict.fromkeys(
                catalog.read_units(entry["localizations"].get(code, {}))))
        for variant in sorted(variants, key=lambda v: (v.count("."), v)):
            # A cell is filled only when that language really has translated
            # this unit. A language still carrying its English stand-in comes
            # back empty, which is what marks it as outstanding — printing the
            # placeholder would invite translating the placeholder.
            values = {}
            for code in languages:
                localization = entry["localizations"].get(code, {})
                state = catalog.read_states(localization).get(variant)
                values[code] = (catalog.read_units(localization).get(variant, "")
                                if state == "translated" else "")
            row = {
                "key": key,
                "variant": variant,
                "max_chars": length_guide([values.get(c, "") for c in REFERENCE]),
                "instruction": instruction(key, entry, variant, values),
            }
            row.update(values)
            # The source column is always shown; it is what everything else is
            # translated from.
            row[catalog.SOURCE] = catalog.read_units(
                entry["localizations"][catalog.SOURCE]).get(variant, "")
            rows.append(row)

    with open(args.out, "w", encoding=catalog.ENCODING, newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=header,
                                delimiter=catalog.DELIMITER, restval="",
                                quoting=csv.QUOTE_MINIMAL)
        writer.writeheader()
        writer.writerows(rows)

    outstanding = sum(1 for row in rows for code in languages
                      if code != catalog.SOURCE and not row.get(code))
    print(f"{args.out}")
    print(f"  {len(rows)} rows, {len(header)} columns, "
          f"{outstanding} cells still to fill")


if __name__ == "__main__":
    main()
