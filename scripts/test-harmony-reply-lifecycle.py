#!/usr/bin/env python3
"""Guard reply invalidation when its Harmony view is closed or destroyed."""

from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    view = (root / "platforms/harmony/entry/src/main/ets/keyboard/KeyboardView.ets").read_text()
    disappear_start = view.index("  aboutToDisappear(): void")
    disappear = view[disappear_start : view.index("\n  /**", disappear_start)]
    show_start = view.index("  private show(surface: string): void")
    show = view[show_start : view.index("\n  /** Tapping", show_start)]
    required = {
        "destroyed callback removed":
            "KeyboardSession.shared.onReplyContextChanged = undefined" in disappear,
        "destroyed request invalidated":
            "KeyboardSession.shared.invalidateReplyContext(false)" in disappear,
        "closed request invalidated": "this.surface === SURFACE_REPLY" in show
            and "KeyboardSession.shared.invalidateReplyContext(false)" in show,
        "late local result invalidated": "this.replyGeneration += 1" in show,
        "visible old result cleared": "this.replyResults = []" in show,
        "diagnostic timer cancelled": "clearTimeout(this.diagnosticTimer)" in disappear
            and "this.diagnosticTimer = -1" in disappear,
        "reply generation invalidated": "this.replyGeneration += 1" in disappear,
        "polish generation invalidated": "this.polishGeneration += 1" in disappear,
    }
    problems = [name for name, present in required.items() if not present]
    if problems:
        for problem in problems:
            print(f"missing reply lifecycle guard: {problem}")
        return 1
    print("harmony reply lifecycle: closed and destroyed views reject late results")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
