#!/usr/bin/env python3
"""One-off helper used at import time: merges the extraction reports (Markdown tables) into docs/catalogue.csv
and docs/third-party.md. Kept for transparency; not needed for day-to-day use.

    python tools/build_catalogue_from_reports.py <report.md> [<report.md> ...]
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_CSV = ROOT / "docs" / "catalogue.csv"
OUT_TP = ROOT / "docs" / "third-party.md"


def parse(path: Path) -> list[dict[str, str]]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("|") or line.startswith("|---") or line.startswith("| page_id"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 9:
            cells += [""] * (9 - len(cells))
        rows.append(dict(zip(["page_id", "title", "status", "file", "category", "description", "requires", "impact", "source"], cells)))
    return rows


def main(reports: list[str]) -> None:
    rows = [r for p in reports for r in parse(Path(p))]
    included, third_party, skipped = [], [], []
    for r in rows:
        if r["status"].startswith("included"):
            files = [f.strip() for f in r["file"].replace(";", ",").split(",") if f.strip() and f.strip() != "—"]
            impacts = [i.strip() for i in r["impact"].split("/")] if "/" in r["impact"] and len(files) > 1 else [r["impact"]] * len(files)
            for i, f in enumerate(files):
                cat, _, name = f.partition("/")
                if not (ROOT / "scripts" / cat / name).exists():
                    print("WARN missing on disk:", f)
                    continue
                included.append({
                    "category": cat, "file": name, "title": Path(name).stem,
                    "description": r["description"], "requires": r["requires"] or "none",
                    "impact": (impacts[i] if i < len(impacts) else impacts[-1]) or "Read-only",
                })
        elif r["status"].startswith("excluded"):
            third_party.append(r)
        else:
            skipped.append(r)

    with OUT_CSV.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["category", "file", "title", "description", "requires", "impact"], lineterminator="\n")
        w.writeheader()
        w.writerows(sorted(included, key=lambda r: (r["category"], r["file"].lower())))

    lines = ["# Third-party scripts used alongside this library", "",
             "These were part of the original working library but are **not** included here because they were written by",
             "someone else. They are excellent — get them from the source, with the author's licence.", "",
             "| Script / query | Author · source |", "|----------------|-----------------|"]
    for r in sorted(third_party, key=lambda r: r["title"].lower()):
        lines.append(f"| {r['title']} — {r['description']} | {r['source'] or 'see page'} |")
    OUT_TP.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"included {len(included)} files, third-party {len(third_party)}, skipped {len(skipped)}")


if __name__ == "__main__":
    main(sys.argv[1:])
