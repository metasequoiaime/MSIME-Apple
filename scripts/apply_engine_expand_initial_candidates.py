#!/usr/bin/env python3
"""Expose the Engine's existing initial-candidate expansion on the public session facade.

The Engine caps a single-letter query at twenty-four candidates so the first page is cheap, and
`InputSession::expand_initial_candidates` hands over the rest. The Windows source reaches that
through the internal session; this repository only links the `metasequoia::Session` facade, which
never forwarded it, so those candidates were unreachable and paging stopped at the cap.

This adds the forwarder and nothing else: no algorithm, no ranking, no new behaviour in the Engine.
"""
from pathlib import Path


def replace_once(path: Path, before: str, after: str, applied: str) -> None:
    """`applied` is text only the rewritten file carries.

    These hunks append to their anchor rather than consuming it, so the anchor survives the
    rewrite and "is the anchor still there?" cannot answer whether the overlay already ran. It has
    to be asked separately, or a second run appends the same code again and the Engine stops
    compiling on a redefinition.
    """
    text = path.read_text()
    if applied in text:
        return
    if before not in text:
        raise RuntimeError(f"Engine overlay did not match: {path}")
    path.write_text(text.replace(before, after, 1))


def apply(root: Path) -> None:
    # The expansion grows the engine's own candidate list, while `candidates()` serves the mixed
    # list built from it. Without the refresh the call reports success and its own accessor keeps
    # the short answer, so every caller sees the cap it just asked to lift.
    replace_once(
        root / "core/input_session_composition.cpp",
        "bool InputSession::expand_initial_candidates()\n{\n"
        "    return engine_.expand_initial_candidates();\n}\n",
        "bool InputSession::expand_initial_candidates()\n{\n"
        "    if (!engine_.expand_initial_candidates())\n"
        "        return false;\n"
        "    update_mixed_candidates();\n"
        "    return true;\n}\n",
        applied="    update_mixed_candidates();\n    return true;\n}",
    )
    replace_once(
        root / "include/metasequoia/session.h",
        "    void reset_cache();\n",
        "    void reset_cache();\n"
        "    // Hand over the candidates withheld from a single-letter query, reporting whether the\n"
        "    // list grew. Hosts call this when paging reaches the end of what the first answer held.\n"
        "    bool expand_initial_candidates();\n",
        applied="    bool expand_initial_candidates();",
    )
    replace_once(
        root / "core/session.cpp",
        "void Session::reset_cache()\n{\n    impl_->session.reset_cache();\n}\n",
        "void Session::reset_cache()\n{\n    impl_->session.reset_cache();\n}\n"
        "bool Session::expand_initial_candidates()\n{\n"
        "    // Nine-key candidates come from the spelling session rather than a dictionary query,\n"
        "    // so there is nothing withheld to hand over. Local modes need no guard here: the\n"
        "    // expansion itself only answers single-letter database queries.\n"
        "    if (impl_->nine_key.active())\n"
        "        return false;\n"
        "    return impl_->session.expand_initial_candidates();\n}\n",
        applied="bool Session::expand_initial_candidates()",
    )


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
