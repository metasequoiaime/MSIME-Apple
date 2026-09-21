#!/usr/bin/env python3
"""Guard the debounced multi-stroke OCR contract from Apple HandwritingTests."""

from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    view = (root / "platforms/harmony/entry/src/main/ets/keyboard/KeyboardView.ets").read_text()
    start = view.index("  private handwritingTouch(")
    touch = view[start : view.index("  private cancelHandwritingTimer()", start)]
    required = {
        "touches remain writable during OCR": "this.handwritingBusy" not in touch,
        "source debounce is retained": "HANDWRITING_RECOGNITION_DELAY_MS: number = 550" in view
        and "this.scheduleHandwritingRecognition()" in touch,
        "lift point respects the cap":
            "this.handwritingCurrent.length < HANDWRITING_MAX_POINTS" in touch,
        "changed ink invalidates old OCR": "this.handwritingRecognition.changed()" in view
        and "this.handwritingRecognition.accepts(ticket)" in view,
        "latest canvas is queued": "this.handwritingRecognition.request()" in view
        and "this.handwritingRecognition.finish()" in view,
    }
    problems = [name for name, present in required.items() if not present]
    if problems:
        for problem in problems:
            print(f"missing handwriting scheduling guard: {problem}")
        return 1
    print("harmony handwriting scheduling: multi-stroke ink stays writable and OCR is debounced")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
