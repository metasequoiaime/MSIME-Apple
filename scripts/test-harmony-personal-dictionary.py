#!/usr/bin/env python3
"""Keep Harmony's bounded personal-dictionary queue draining while the IME stays alive."""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SESSION = ROOT / "platforms/harmony/entry/src/main/ets/keyboard/KeyboardSession.ets"
STORE = ROOT / "crates/client-core/src/dictionary/personal.rs"


def main() -> int:
    session = SESSION.read_text(encoding="utf-8")
    store = STORE.read_text(encoding="utf-8")
    start = session.index("  start(resources:")
    drain = session.index("this.personalDictionarySettled = this.drainPersonalDictionary(options)")
    create = session.index("client.create(options)", drain)
    scheduler = session[
        session.index("  private schedulePersonalDictionaryDrain()") : session.index(
            "\n  /** Whether the Engine's output",
            session.index("  private schedulePersonalDictionaryDrain()"),
        )
    ]
    queued = session[
        session.index("      if (decision.queued)") : session.index(
            "    } catch (error)", session.index("      if (decision.queued)")
        )
    ]
    stop = scheduler.find("this.stop()")
    restart = scheduler.find("this.start(")
    required = {
        "four-entry native batch": ".take(4)" in store,
        "idle sync before Engine session": start < drain < create,
        "two-second yield": "PERSONAL_DICTIONARY_RETRY_MS: number = 2000" in session,
        "composition guard": "this.composing() || this.isInLocalMode()" in scheduler,
        "Engine session release": stop >= 0 and restart >= 0 and stop < restart,
        "mode restoration": "client.setEnglishMode" in scheduler
        and "client.setNineKeyMode" in scheduler,
        "remaining work rescheduled": "this.schedulePersonalDictionaryDrain();" in scheduler,
        "new queue work noticed": "this.personalDictionarySettled = false" in queued
        and "this.schedulePersonalDictionaryDrain();" in queued,
        "shutdown cancels timer": "clearTimeout(this.personalDictionaryTimer)" in session,
    }
    missing = [name for name, present in required.items() if not present]
    if missing:
        print("harmony personal dictionary: missing " + ", ".join(missing), file=sys.stderr)
        return 1
    print("harmony personal dictionary: bounded batches resume while idle")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
