#!/usr/bin/env python3
"""Read a filled-in translation sheet back into the string catalog.

    python3 Tools/import_translations.py [path.csv] [--dry-run] [--only de,fr]

Columns are found by name, so the sheet may be reordered or have columns hidden,
and languages may be handed back a few at a time. Only `key` and `variant` must
survive untouched — they are what ties a row to its place in the catalog.

Nothing is written until every check passes. The checks that block a write are
the ones that would otherwise ship a broken build: a changed set of placeholders,
a substitution left without its plural forms, an unknown key. Everything else —
a string running long, unbalanced bold markers — is reported and let through.

An empty cell is not an error and never blanks anything out: it keeps the
English stand-in for that unit, still marked `new`. That is what keeps every
language column complete, which is the one thing this app cannot do without —
SwiftUI prints the raw key for a blank string rather than falling back.
"""
from __future__ import annotations

import argparse
import collections
import csv
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import catalog  # noqa: E402


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)


CATEGORIES = ("other", "one", "many", "few", "two", "zero")


def source_for(variant: str, source_units: dict[str, str]) -> str:
    """The source string a translated cell should be judged against.

    Languages disagree with English about which strings need inflecting, in both
    directions: Polish needs a `few` form English has no use for, and Dutch
    splits a notification line English leaves flat. Either way the row has no
    exact counterpart, so the nearest relative stands in — it carries the same
    placeholders and the same emphasis, which is all these checks look at.
    """
    if variant in source_units:
        return source_units[variant]
    parts = variant.split(".")
    # "plural.few" is a category of the string itself; "bubbles.plural.few" is a
    # category of the substitution named `bubbles`. Siblings live under the same
    # owner, so the owner is what the lookup has to preserve.
    owner = "" if not parts or parts[0] == "plural" else parts[0]
    for sibling in CATEGORIES:
        candidate = f"{owner}.plural.{sibling}" if owner else f"plural.{sibling}"
        if candidate in source_units:
            return source_units[candidate]
    return source_units.get("", "")


def check_cell(report: Report, where: str, source: str, value: str,
               budget: int, substitutions: dict) -> None:
    """Everything that can be judged from the source and the translation alone."""
    wanted = catalog.argument_indices(source, substitutions)
    got = catalog.argument_indices(value, substitutions)
    if wanted != got:
        missing = sorted(wanted - got)
        invented = sorted(got - wanted)
        detail = []
        if missing:
            detail.append(f"drops argument {', '.join(map(str, missing))}")
        if invented:
            detail.append(f"reaches for argument {', '.join(map(str, invented))} "
                          f"which the code does not pass")
        report.error(
            f"{where}: {' and '.join(detail)}. Source is {source!r}, "
            f"translation is {value!r}."
        )
    elif catalog.specifiers(source) != catalog.specifiers(value):
        report.warn(
            f"{where}: placeholders spelled differently from the source "
            f"({', '.join(catalog.specifiers(source)) or 'none'} → "
            f"{', '.join(catalog.specifiers(value)) or 'none'}). The same "
            f"arguments are used, so this is allowed — check it is deliberate."
        )
    if value.count("**") % 2:
        report.warn(f"{where}: odd number of ** markers, bold will not close")
    if "**" in source and "**" not in value:
        report.warn(f"{where}: source is emphasised but the translation is not")
    if budget and len(value) > budget * 1.5:
        report.warn(f"{where}: {len(value)} characters against a guide of {budget}")



def write_todo(path: str, strings: dict, rebuilt: dict,
               languages: list[str], dry_run: bool) -> None:
    """Write the units still needing work as a sheet in the same shape.

    Whatever did not make it through — a cell that failed a check, a row nobody
    filled in — comes back out as a sheet that can go straight to a translator,
    so a second pass is about the handful that went wrong rather than all of it.
    """
    import export_translations as export

    pending: dict[str, set[str]] = collections.defaultdict(set)
    for key, entry in strings.items():
        source = entry["localizations"][catalog.SOURCE]
        for code in languages:
            localization = rebuilt.get((key, code)) or entry["localizations"].get(code, {})
            states = catalog.read_states(localization)
            if not states or any(state != "translated" for state in states.values()):
                pending[key].add(code)
    if not pending:
        print("\nnothing outstanding — no to-do sheet written")
        return

    codes = [c for c in languages if any(c in v for v in pending.values())]
    header = catalog.FIXED_COLUMNS + ["en", "nl"] + codes
    rows = []
    for key in sorted(pending):
        entry = strings[key]
        source_units = catalog.read_units(entry["localizations"][catalog.SOURCE])
        for variant in sorted(source_units, key=lambda v: (v.count("."), v)):
            values = {c: catalog.read_units(entry["localizations"].get(c, {})).get(variant, "")
                      for c in ("en", "nl")}
            note = export.instruction(key, entry, variant, values)
            if ".plural." in variant:
                note = ("REDO — this row must hold only the part that changes "
                        "with the count, written with %arg, not the whole "
                        "sentence. " + note)
            rows.append({"key": key, "variant": variant,
                         "max_chars": export.length_guide(list(values.values())),
                         "instruction": note, **values})

    with open(path, "w", encoding=catalog.ENCODING, newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=header,
                                delimiter=catalog.DELIMITER, restval="")
        writer.writeheader()
        writer.writerows(rows)
    print(f"\n{'would write' if dry_run else 'wrote'} {path}: "
          f"{len(rows)} rows across {len(pending)} key(s), {len(codes)} language(s)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", default=catalog.CSV)
    parser.add_argument("--dry-run", action="store_true",
                        help="check the sheet and report, write nothing")
    parser.add_argument("--only", default="",
                        help="comma-separated language codes to import")
    parser.add_argument("--skip-invalid", action="store_true",
                        help="import what passes, drop and report what does not")
    parser.add_argument("--todo", default="",
                        help="write the units still needing work to this sheet")
    args = parser.parse_args()

    roster = catalog.languages()
    data = catalog.load()
    strings = data["strings"]
    report = Report()

    rows, delimiter, encoding = catalog.open_sheet(args.path)
    if not rows:
        raise SystemExit(f"{args.path}: no rows")
    print(f"{os.path.basename(args.path)}: {len(rows)} rows, "
          f"{delimiter!r}-separated, {encoding}")

    header = [name for name in rows[0] if name]
    for required in ("key", "variant"):
        if required not in header:
            raise SystemExit(f"{args.path}: no {required!r} column")

    wanted = [code.strip() for code in args.only.split(",") if code.strip()]
    languages = [name for name in header
                 if name in roster and name != catalog.SOURCE
                 and (not wanted or name in wanted)]
    for code in wanted:
        if code not in languages:
            raise SystemExit(f"--only {code}: not a column in the sheet")
    unknown = [name for name in header
               if name not in roster and name not in catalog.FIXED_COLUMNS]
    if unknown:
        report.error(f"columns that are not roster languages: {', '.join(unknown)}")

    # Gather the sheet into {key: {variant: {language: value}}}.
    sheet: dict[str, dict[str, dict[str, str]]] = collections.defaultdict(dict)
    budgets: dict[tuple[str, str], int] = {}
    for number, row in enumerate(rows, start=2):
        key, variant = row["key"], (row["variant"] or "")
        if not key:
            continue
        if key not in strings:
            report.error(f"row {number}: no such key {key!r}")
            continue
        source_units = catalog.read_units(strings[key]["localizations"][catalog.SOURCE])
        # A language may reshape a string relative to English: inflecting one
        # that English leaves flat, or leaving flat one that English inflects.
        # Both are legitimate, so any well-formed variant is accepted, not only
        # the ones the source happens to use.
        well_formed = (variant == "" or
                       re.fullmatch(r"(?:[A-Za-z_]\w*\.)?plural\.\w+", variant))
        if variant not in source_units and not well_formed:
            report.error(
                f"row {number}: {variant!r} is not a variant this tool "
                f"understands. Use an empty cell for the whole string, or "
                f"'plural.few' / 'bubbles.plural.few' for a plural category.")
            continue
        cells = {code: (row.get(code) or "").strip() for code in languages}
        for code, value in list(cells.items()):
            # `%#@name\@` is a substitution reference that picked up a stray
            # escape somewhere between the catalog and the spreadsheet. Left
            # alone it stops being a reference at all and prints verbatim.
            repaired = re.sub(r"%#@(\w+)\\@", r"%#@\1@", value)
            if repaired != value:
                cells[code] = repaired
                report.warn(f"{key} [{variant or 'text'}] {code}: repaired "
                            f"an escaped %#@…\\@ substitution marker")
        sheet[key][variant] = {c: v for c, v in cells.items() if v}
        try:
            budgets[(key, variant)] = int(row.get("max_chars") or 0)
        except ValueError:
            budgets[(key, variant)] = 0

    # Check every filled cell against its source. A cell that fails is dropped
    # from `bad` rather than silently corrected — with --skip-invalid the rest
    # of that language still lands, which is what makes a sheet with one
    # systematic mistake in it worth importing at all.
    bad: set[tuple[str, str]] = set()
    for key, variants in sheet.items():
        template = strings[key]["localizations"][catalog.SOURCE]
        source_units = catalog.read_units(template)
        declared = template.get("substitutions", {})
        for variant, cells in variants.items():
            source = source_for(variant, source_units)
            for code, value in cells.items():
                where = f"{key} [{variant or 'text'}] {code}"
                owner = variant.split(".")[0] if ".plural." in variant else None
                if owner:
                    base = variants.get("", {}).get(code, "")
                    if f"%#@{owner}@" not in base:
                        # The sentence renders the count itself instead of
                        # slotting in this fragment, so the fragment is dead
                        # weight and gets dropped below. Judging it against a
                        # source it will never stand in for only produces noise.
                        continue
                    if "%#@" in value:
                        report.error(
                            f"{where}: a plural fragment cannot itself contain "
                            f"%#@…@ — this row holds the whole sentence, but it "
                            f"should hold only the part that changes with the "
                            f"count, written with %arg (English has "
                            f"{source!r}).")
                        bad.add((key, code))
                        continue
                before = len(report.errors)
                check_cell(report, where, source, value,
                           budgets.get((key, variant), 0), declared)
                if len(report.errors) > before:
                    bad.add((key, code))

    if bad and args.skip_invalid:
        for key, code in bad:
            for cells in sheet[key].values():
                cells.pop(code, None)
        report.errors.clear()
        print(f"— skipping {len(bad)} key/language pair(s) that failed a check")

    # Rebuild each touched language, filling any gap from English so no column
    # is ever left with a hole in it.
    touched: collections.Counter = collections.Counter()
    rebuilt: dict[tuple[str, str], dict] = {}
    for key, variants in sheet.items():
        entry = strings[key]
        template = entry["localizations"][catalog.SOURCE]
        source_units = catalog.read_units(template)
        for code in languages:
            filled = {variant: cells[code]
                      for variant, cells in variants.items() if code in cells}
            if not filled:
                continue
            # Fill every unit the source has, best available first: the sheet,
            # then whatever this language already had, then English. An empty
            # cell therefore leaves an existing translation alone — a sheet
            # handed back with one language filled in must not quietly undo
            # another — and still guarantees no unit is left blank.
            existing = catalog.read_units(entry["localizations"].get(code, {}))
            existing_states = catalog.read_states(entry["localizations"].get(code, {}))
            units: dict[str, tuple[str, str]] = {}
            for variant, value in source_units.items():
                if variant in existing:
                    units[variant] = (existing[variant], existing_states[variant])
                else:
                    units[variant] = (value, "new")
            for variant, value in existing.items():
                units.setdefault(variant, (value, existing_states[variant]))
            for variant, value in filled.items():
                units[variant] = (value, "translated")

            # A string is either one sentence or a set of plural forms, never
            # both — the catalog would carry two answers to the same question
            # and the build picks the inflected one, which after gap-filling
            # could still be English. Languages genuinely disagree with English
            # about which strings need inflecting (Dutch splits two of the
            # notification lines; it leaves flat an accessibility label English
            # inflects), so the shape follows whoever actually said something:
            # the sheet first, then what the language already had, then English.
            def inflected(variants) -> bool:
                return any(v.startswith("plural.") for v in variants)

            if inflected(filled):
                wants_plural = True
            elif "" in filled:
                wants_plural = False
            elif existing:
                wants_plural = inflected(existing)
            else:
                wants_plural = inflected(source_units)

            if wants_plural:
                units.pop("", None)
            else:
                for variant in [v for v in units if v.startswith("plural.")]:
                    del units[variant]
            # A substitution's plural forms only mean anything if the text
            # actually slots them in. A translator who renders the count
            # directly — "%1$lld keer" rather than "%#@times@" — has simply
            # chosen not to inflect it, and should not be left carrying an
            # unreachable copy of the English forms.
            base = units.get("", ("", ""))[0]
            for name in catalog.substitution_names(entry):
                parts = [v for v in units if v.startswith(f"{name}.plural.")]
                if f"%#@{name}@" in base:
                    untranslated = [v for v in parts if units[v][1] != "translated"]
                    if untranslated and any(units[v][1] == "translated"
                                            for v in [""] if v in units):
                        report.warn(
                            f"{key} [{code}]: the text slots in %#@{name}@ but "
                            f"{len(untranslated)} of its plural rows are empty — "
                            f"English will be used for those counts")
                else:
                    for variant in parts:
                        del units[variant]
            rebuilt[(key, code)] = catalog.write_units(units, template)
            touched[code] += len(filled)

    if report.warnings:
        print(f"— {len(report.warnings)} warning(s)")
        for message in report.warnings[:40]:
            print(f"   {message}")
        if len(report.warnings) > 40:
            print(f"   … and {len(report.warnings) - 40} more")

    if report.errors:
        print(f"\n✗ {len(report.errors)} error(s), nothing written")
        for message in report.errors[:40]:
            print(f"   {message}")
        if len(report.errors) > 40:
            print(f"   … and {len(report.errors) - 40} more")
        raise SystemExit(1)

    total_units = sum(len(catalog.read_units(entry["localizations"][catalog.SOURCE]))
                      for entry in strings.values())
    print(f"\n{'would import' if args.dry_run else 'imported'} "
          f"{sum(touched.values())} units across {len(touched)} language(s):")
    for code, count in sorted(touched.items()):
        print(f"   {code}: {count}/{total_units} units "
              f"({100 * count // total_units}%)")

    if args.todo:
        write_todo(args.todo, strings, rebuilt, languages, args.dry_run)

    if args.dry_run:
        print("\ndry run — catalog untouched")
        return

    for (key, code), localization in rebuilt.items():
        strings[key]["localizations"][code] = localization
    for entry in strings.values():
        entry["localizations"] = dict(sorted(entry["localizations"].items()))
    catalog.save(data)
    print(f"\nwrote {catalog.CATALOG}")
    print("build once and check a screen per language before committing")


if __name__ == "__main__":
    main()
