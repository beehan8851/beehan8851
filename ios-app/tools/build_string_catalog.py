#!/usr/bin/env python3
"""
Rebuild Localizable.xcstrings from the strings the compiler extracted.

Why this exists
---------------
`String(localized:comment:)` calls are extracted into `.stringsdata` files on every
build, but only Xcode.app writes them back into the String Catalog — `xcodebuild`
leaves the catalog untouched. This reads the same `.stringsdata` and produces the
catalog, so the source of truth stays the code and the catalog can be regenerated
from a terminal.

Existing translations are preserved: a key that is already in the catalog keeps its
`localizations` block. Keys the code no longer contains are dropped, which is the
point — a stale entry is a translation nobody will ever see.

Usage:  python3 tools/build_string_catalog.py [--check]
        --check exits non-zero if the catalog is out of date, for CI.
"""

import argparse
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TRANSLATIONS = pathlib.Path(__file__).resolve().parent / "translations"

# Each target gets its own catalog: an extension is a separate bundle at runtime,
# so a widget looking up a string finds only what ships inside the .appex. Widget
# text was English in every locale until this existed.
TARGETS = {
    "MorningCompanion":        ROOT / "MorningCompanion" / "Localizable.xcstrings",
    "MorningCompanionWidgets": ROOT / "MorningCompanionWidgets" / "Localizable.xcstrings",
}




def derived_data_root() -> pathlib.Path:
    """The build directory xcodebuild is using for this project."""
    # The scheme matters: without it xcodebuild reports the legacy ./build location
    # rather than the DerivedData path an actual build writes to.
    out = subprocess.run(
        ["xcodebuild", "-project", "MorningCompanion.xcodeproj",
         "-scheme", "MorningCompanion",
         "-destination", "generic/platform=iOS Simulator",
         "-showBuildSettings"],
        capture_output=True, text=True, cwd=ROOT,
    ).stdout
    for line in out.splitlines():
        if line.strip().startswith("OBJROOT ="):
            return pathlib.Path(line.split("=", 1)[1].strip())
    raise SystemExit("Could not find OBJROOT — build the app target first.")


def collect(target: str) -> dict[str, str]:
    """Every localizable key in one target, mapped to its comment."""
    # Scoped to the target. Scanning the whole intermediates directory also picks up
    # every SPM dependency, which is how "Entitlement Verification Mode" and the rest
    # of RevenueCat's debug UI ended up in the first draft of this catalog.
    # The configuration directory sits between the project and target folders and
    # its name depends on the build, so the target folder is matched rather than spelled.
    root = derived_data_root() / "MorningCompanion.build"
    files = sorted(root.rglob(f"{target}.build/**/Objects-normal/**/*.stringsdata"))
    if not files:
        raise SystemExit(f"No .stringsdata for {target} — build it first.")

    keys: dict[str, str] = {}
    for path in files:
        try:
            data = json.loads(path.read_text())
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        for entry in data.get("tables", {}).get("Localizable", []):
            key = entry.get("key")
            if key is None:
                continue
            comment = entry.get("comment", "")
            # First comment wins; the same string used twice usually has the better
            # comment at its first site, and a blank one should never overwrite a real one.
            if key not in keys or (not keys[key] and comment):
                keys[key] = comment
    return keys


def translations() -> dict[str, dict[str, str]]:
    """Every `tools/translations/<language>.json`, as {language: {key: value}}.

    Held outside the catalog because the catalog is generated: keeping the
    translations in plain per-language files means a regeneration can never lose
    them, and a reviewer can read one language without wading through the rest.
    """
    if not TRANSLATIONS.is_dir():
        return {}
    result = {}
    for path in sorted(TRANSLATIONS.glob("*.json")):
        result[path.stem] = json.loads(path.read_text())
    return result


def build(keys: dict[str, str], existing: dict) -> dict:
    previous = existing.get("strings", {})
    translated = translations()
    strings = {}
    for key in sorted(keys):
        entry: dict = {}
        if keys[key]:
            entry["comment"] = keys[key]

        # Anything already in the catalog is kept, then the translation files win —
        # they are the source of truth, the catalog is the artefact.
        localizations = dict(previous.get(key, {}).get("localizations", {}))
        for language, table in translated.items():
            value = table.get(key)
            if not value:
                continue
            if isinstance(value, dict):
                # A dictionary is a set of CLDR plural forms — one/few/many/other.
                # Russian needs three, most Romance languages two, and Japanese,
                # Korean, Chinese and Turkish only ever use "other".
                localizations[language] = {
                    "variations": {
                        "plural": {
                            form: {"stringUnit": {"state": "translated", "value": text}}
                            for form, text in value.items()
                        }
                    }
                }
            else:
                localizations[language] = {
                    "stringUnit": {"state": "translated", "value": value}
                }
        if localizations:
            entry["localizations"] = localizations
        strings[key] = entry
    return {
        "sourceLanguage": existing.get("sourceLanguage", "en"),
        "strings": strings,
        "version": "1.0",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true",
                        help="exit non-zero when the catalog is out of date")
    args = parser.parse_args()

    stale = False
    for target, path in TARGETS.items():
        existing = json.loads(path.read_text()) if path.exists() else {}
        catalog = build(collect(target), existing)
        # Xcode's own serialisation puts a space before each colon; matching it keeps a
        # regeneration from rewriting every line of a file Xcode last saved.
        rendered = json.dumps(catalog, indent=2, ensure_ascii=False, sort_keys=True, separators=(",", " : ")) + "\n"
        total = len(catalog["strings"])

        if args.check:
            if (path.read_text() if path.exists() else "") != rendered:
                print(f"{target}: catalog is out of date — run tools/build_string_catalog.py",
                      file=sys.stderr)
                stale = True
            else:
                print(f"{target}: up to date ({total} strings)")
            continue

        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(rendered)
        languages = sorted({l for e in catalog["strings"].values() for l in e.get("localizations", {})})
        done = [sum(1 for e in catalog["strings"].values() if l in e.get("localizations", {}))
                for l in languages]
        summary = f", {min(done)}–{max(done)} translated in {len(languages)} languages" if languages else ""
        print(f"{target}: {total} strings{summary}")

    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
