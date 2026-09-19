#!/usr/bin/env python3
"""Screen harvested conversion failures before they become evaluation cases.

The harvester keeps any sentence whose pinyin decodes to something else. That is necessary but not
sufficient: `resources/eval/README.md` excludes sentences whose pinyin has two equally natural
readings, because "评测集不能既诚实又有歧义" — a case whose gold is one of two defensible answers
measures the grader, not the decoder. Deciding that is a judgement, not a filter.

Two questions per case, asked together over the same state because neither needs the other's answer:

  intended   Choice over the readings the decoder actually produced. If this disagrees with the
             original, the case is not usable: either the corpus sentence is odd, or the decoder's
             answer is defensible and the "failure" is not one.
  ambiguous  Noul on whether more than one reading is equally natural here. This is the README's
             own exclusion rule, asked directly.

A case is proposed for the set when the choice lands on the original and ambiguity is unlikely.
Everything else is written out with the reason attached, for a person to scan. The script proposes;
it does not decide. Nothing here is a gate.

Input is convert_eval's `--dump` JSONL, which carries the real candidate list, the gold and the
context. Text sent to the API is licensed corpus, never user input.

usage: TYPESAFE_API_KEY=... review_harvest.py <dump.jsonl> <out-prefix>
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ENDPOINT = "https://api.typesafe.ai/v1/systemone"
MODEL = "jev-latest"

# Thresholds are starting points to evaluate on this data, not settled policy.
#
# The choice is the primary gate: it is the question with a checkable answer, and its confidence is
# a distribution concentration rather than a guess about a guess. Ambiguity is a veto, and only a
# strong one, because a Noul near 0.5 means the model puts similar probability on yes and no — not
# that the case is moderately ambiguous. A first pass rejecting above 0.40 threw out 70 of 150
# cases whose choice had landed on the original anyway, which is what a coin flip looks like when
# you read it as a score.
MIN_CHOICE_CONFIDENCE = 0.60
MAX_AMBIGUITY = 0.65

KEY = os.environ.get("TYPESAFE_API_KEY", "")
if not KEY:
    sys.exit("TYPESAFE_API_KEY is not set")


def ask(case):
    options, seen = [], set()
    for candidate in case["candidates"]:
        text = candidate["text"]
        if text not in seen:
            seen.add(text)
            options.append(text)
    if case["gold"] not in options:
        case["verdict"] = "gold-absent"
        return case
    # The decoder returns long tails; the readings worth comparing are the ones that answered the
    # same key, which is the length the gold is.
    width = len(case["gold"])
    options = [text for text in options if len(text) == width][:9]
    if case["gold"] not in options or len(options) < 2:
        case["verdict"] = "no-comparable-alternatives"
        return case

    body = {
        "state": {
            "pinyin_keystrokes": case["input"],
            "preceding_text": case.get("context", ""),
            "readings": options,
        },
        "model": MODEL,
        "questions": {
            "intended": {
                "type": "choice",
                "instructions": (
                    "A Chinese writer typed `pinyin_keystrokes` into an input method, "
                    "continuing after `preceding_text`. Every option spells exactly those "
                    "keystrokes and differs only in which characters were chosen. Which one "
                    "did the writer mean?"
                ),
                "criteria": {text: None for text in options},
            },
            "ambiguous": {
                "type": "noul",
                "instructions": (
                    "Considering `readings` for `pinyin_keystrokes` after `preceding_text`: "
                    "is there more than one reading a competent writer could equally well have "
                    "intended here?"
                ),
                "criteria": {
                    "true": (
                        "At least two of the readings are equally natural in this context, so "
                        "which one was meant cannot be settled from the text alone."
                    ),
                    "false": (
                        "Exactly one reading is natural here; the others are wrong or clearly "
                        "less plausible."
                    ),
                },
            },
        },
    }

    request = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
    )
    for attempt in range(5):
        try:
            with urllib.request.urlopen(request, timeout=40) as response:
                answer = json.loads(response.read())
            break
        except urllib.error.HTTPError as error:
            if error.code in (429, 500, 502, 503, 504) and attempt < 4:
                time.sleep(min(2**attempt, 8))
                continue
            case["verdict"] = f"error HTTP {error.code}"
            return case
        except Exception as error:  # noqa: BLE001
            if attempt < 4:
                time.sleep(min(2**attempt, 8))
                continue
            case["verdict"] = f"error {type(error).__name__}"
            return case
    else:
        case["verdict"] = "error retries exhausted"
        return case

    intended = answer["answers"]["intended"]
    ambiguous = answer["answers"]["ambiguous"]
    case["jev_choice"] = intended["choice"]
    case["jev_confidence"] = intended.get("confidence")
    case["jev_ambiguity"] = ambiguous.get("noul")
    case["usage"] = answer.get("usage", {})

    if case["jev_choice"] != case["gold"]:
        case["verdict"] = "disagrees-with-original"
    elif (case["jev_confidence"] or 0) < MIN_CHOICE_CONFIDENCE:
        case["verdict"] = "low-confidence"
    elif case["jev_ambiguity"] is not None and case["jev_ambiguity"] > MAX_AMBIGUITY:
        case["verdict"] = "ambiguous"
    else:
        case["verdict"] = "accept"
    return case


def row(case):
    syllables = len(case["gold"])
    return "\t".join(
        [
            case["id"],
            case["input"],
            case["gold"],
            str(syllables),
            "harvested",
            case.get("context", ""),
        ]
    )


def main():
    dump, prefix = sys.argv[1], sys.argv[2]
    cases = [json.loads(line) for line in open(dump) if line.strip()]
    print(f"{len(cases)} harvested cases", file=sys.stderr)

    with ThreadPoolExecutor(max_workers=8) as pool:
        cases = list(pool.map(ask, cases))

    accepted = [c for c in cases if c["verdict"] == "accept"]
    with open(f"{prefix}-accepted.tsv", "w") as handle:
        handle.write("# Jev 评审通过的收割用例，仍待人工确认后并入评测集。\n")
        handle.write("# 列：id / 拼音 / 金标准 / 字数 / 标签 / 上文\n")
        for case in accepted:
            handle.write(row(case) + "\n")
    with open(f"{prefix}-flagged.tsv", "w") as handle:
        handle.write("# 未通过，附理由。disagrees-with-original 往往说明引擎的答案也站得住。\n")
        for case in cases:
            if case["verdict"] == "accept":
                continue
            handle.write(
                "\t".join(
                    [
                        case["verdict"],
                        case["id"],
                        case["input"],
                        case["gold"],
                        case.get("jev_choice", ""),
                        f"{case.get('jev_ambiguity', -1):.2f}",
                        case.get("context", ""),
                    ]
                )
                + "\n"
            )

    counts = {}
    for case in cases:
        counts[case["verdict"]] = counts.get(case["verdict"], 0) + 1
    tokens = sum(c.get("usage", {}).get("input_tokens", 0) for c in cases)
    for verdict, count in sorted(counts.items(), key=lambda item: -item[1]):
        print(f"  {verdict:28} {count}", file=sys.stderr)
    print(
        f"{len(accepted)} proposed -> {prefix}-accepted.tsv "
        f"({tokens} input tokens, ${tokens / 1e6 * 0.042:.4f})",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
