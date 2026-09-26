#!/usr/bin/env python3
"""Guard AI skin cancellation against leaving its HTTP request alive."""

from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    bridge = (root / "platforms/harmony/entry/src/main/ets/account/AccountCloudBridge.ts").read_text()
    transport = (root / "platforms/harmony/entry/src/main/ets/account/HarmonyAccountCloudBridge.ets").read_text()
    skins = (root / "platforms/harmony/entry/src/main/ets/account/HarmonyAiSkins.ets").read_text()
    required = {
        "account transport accepts a request tag": "requestTag?: string" in bridge,
        "transport tracks tagged requests": "activeRequests" in transport and "requests.add(request)" in transport,
        "transport destroys tagged requests": "cancelRequests(requestTag: string)" in transport
            and "for (const request of requests) request.destroy();" in transport,
        "skin bridge exposes cancellation": "cancelAiSkinRequests(requestTag: string)" in bridge,
        "skin run tags every request": "this.runner(requestId)" in skins
            and "requestTag);" in skins,
        "skin cancellation destroys its requests": "this.bridge.cancelAiSkinRequests(requestId);" in skins,
    }
    problems = [name for name, present in required.items() if not present]
    if problems:
        for problem in problems:
            print(f"missing Harmony AI skin lifecycle guard: {problem}")
        return 1
    print("harmony AI skin lifecycle: cancellation destroys tagged HTTP requests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
