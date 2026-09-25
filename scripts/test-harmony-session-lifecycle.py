#!/usr/bin/env python3
"""Guard final Harmony session teardown against late editor callbacks."""

from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    session = (root / "platforms/harmony/entry/src/main/ets/keyboard/KeyboardSession.ets").read_text()
    ability = (root / "platforms/harmony/entry/src/main/ets/inputmethodextability/KeyboardExtensionAbility.ets").read_text()
    checks = {
        "final teardown has a separate method": "shutdown(): void" in session,
        "final teardown invalidates attribute callbacks":
            "this.attributeGeneration++;" in session
            and "this.inputClient = undefined;" in session,
        "ability uses final teardown": "KeyboardSession.shared.shutdown();" in ability,
        "reply request is cancelled with its context":
            "private replyRequest: http.HttpRequest | undefined" in session
            and "if (request !== undefined) request.destroy();" in session,
        "reply request is cleared after completion":
            "if (this.replyRequest === requestHttp) this.replyRequest = undefined;" in session,
    }
    problems = [name for name, present in checks.items() if not present]
    if problems:
        for problem in problems:
            print(f"missing Harmony session lifecycle guard: {problem}")
        return 1
    print("harmony session lifecycle: final teardown rejects late editor attributes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
