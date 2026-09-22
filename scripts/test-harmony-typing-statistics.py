#!/usr/bin/env python3
"""Guard Harmony's complete typing-statistics bridge, including desktop-only retention UI."""

from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    app = (root / "apps/harmony/src/main.tsx").read_text()
    bridge = (root / "platforms/harmony/entry/src/main/ets/pages/Settings.ets").read_text()

    required = {
        "shared client exposes retention": "setRetention: async (retention: StatisticsRetention)" in app,
        "shared client sends retention": 'operation: "set_retention", retention' in app,
        "native bridge accepts retention": "'set_retention'" in bridge,
        "native bridge validates every retention choice": all(
            repr(choice) in bridge for choice in ("forever", "30d", "90d", "180d", "365d")
        ),
        "native bridge forwards the validated action": "directory: this.stateDirectory, action: action" in bridge,
    }
    problems = [name for name, present in required.items() if not present]
    if problems:
        for problem in problems:
            print(f"missing Harmony typing-statistics wiring: {problem}")
        return 1
    print("harmony typing statistics: retention reaches the native aggregate store")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
