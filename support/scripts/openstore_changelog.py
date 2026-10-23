#!/usr/bin/env python3
"""Print the OpenStore changelog line for one Ubuntu Touch release.

The OpenStore shows the ``changelog`` form field as the release note. The
markdown changelog is rewritten into a single line without the package
architecture, which users previously saw as ``Release v1.5.6 (1.5.6, amd64)``
and read as a mistake.

Usage: openstore_changelog.py <version> <changelog.md>
"""

import re
import sys

MAX_LENGTH = 900


def changelog_note(version: str, changelog: str) -> str:
    """Return a one-line release note for ``version``."""
    pattern = r"^## " + re.escape(version) + r"[ \t]*\n(.*?)(?=^## |\Z)"
    match = re.search(pattern, changelog, re.S | re.M)
    if not match:
        return f"LocalSend for Ubuntu Touch {version}"

    parts = []
    for raw in match.group(1).splitlines():
        line = raw.strip()
        if not line:
            continue
        line = re.sub(r"^[-*]\s+", "\u2022 ", line)
        line = line.replace("`", "").replace("**", "")
        parts.append(line)

    note = " ".join(parts).strip()
    if not note:
        return f"LocalSend for Ubuntu Touch {version}"
    if len(note) > MAX_LENGTH:
        note = note[:MAX_LENGTH].rsplit(" ", 1)[0].rstrip(",;:") + " \u2026"
    return note


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        return 2
    version, path = argv[1], argv[2]
    with open(path, encoding="utf-8") as handle:
        print(changelog_note(version, handle.read()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
