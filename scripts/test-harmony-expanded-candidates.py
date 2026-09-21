#!/usr/bin/env python3
"""Guard the expanded-candidate width contract taken from the Apple Japanese tests."""

from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    view = (root / "platforms/harmony/entry/src/main/ets/keyboard/KeyboardView.ets").read_text()
    policy = (
        root
        / "platforms/harmony/entry/src/main/ets/keyboard/candidate/ExpandedCandidateLayout.ts"
    ).read_text()
    start = view.index("  expandedFace()")
    expanded = view[start : view.index("  @Builder\n  geometryFace()", start)]
    required = {
        "shared measured width": "ExpandedCandidateLayout.width" in view
        and ".width(this.expandedCandidateWidth(index))" in expanded,
        "visible-width cap": "Math.min(natural, availableWidth)" in policy,
        "single-line candidate": "Text(this.expanded[index].text)" in expanded
        and ".maxLines(1)" in expanded
        and "TextOverflow.Ellipsis" in expanded,
        "constrained text column": ".layoutWeight(1)" in expanded,
    }
    problems = [name for name, present in required.items() if not present]
    if problems:
        for problem in problems:
            print(f"missing expanded candidate guard: {problem}")
        return 1
    print("harmony expanded candidates: measured cells stay single-line and within the panel")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
