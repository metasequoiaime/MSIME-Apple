#!/usr/bin/env python3
"""Add the Main-pipe event the TSF sends after it auto-closes a book title the Server's Engine opened.

With candidates open the Server's Engine translates `<` and counts the nesting, so the next `<` gives 〈 until a `>` pays it back. When paired completion is on, the TSF inserts the closing half itself and a later `>` only steps over it, so the Server never sees the key that would balance the count and every following book title degrades into 〈〉. The reference has one process and one counter (`CCompositionProcessorEngine::_nestCount`), and its KeyHandler balances it right after the auto-close. Here the counter the opening advanced lives in the Server's Engine, so the TSF tells the Server over the Main pipe and the Server calls `msime_client_balance_paired_punctuation_after_auto_close`.

The event is a fire-and-forget notification like `PuncSwitch`: `keycode` carries the opening key, which is always `<` because it is the only paired punctuation with nesting state. It has no reply.
"""
from pathlib import Path

BEFORE = """constexpr std::uint32_t FocusRestored = 15;
"""

AFTER = """constexpr std::uint32_t FocusRestored = 15;
// The TSF auto-closed a paired punctuation whose opening half the Server may have resolved, so the Engine's nesting count must be paid back as if the closing key had been typed. keycode: the opening key, always '<'. No reply.
constexpr std::uint32_t PairedPunctuationAutoClosed = 16;
"""


def apply(root: Path) -> None:
    path = root / "contracts/windows_ipc.h"
    text = path.read_text(encoding="utf-8")
    if AFTER in text:
        return
    if text.count(BEFORE) != 1:
        raise RuntimeError(f"Engine overlay did not match: {path}")
    path.write_text(text.replace(BEFORE, AFTER, 1), encoding="utf-8")


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
