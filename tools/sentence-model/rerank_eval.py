"""Measure what a trained model does to real candidate lists from the input runtime.

The input is the JSONL that `convert_eval --dump` writes: for every evaluation case, the candidates the engine actually produced, in the order it produced them, each tagged with the source that produced it.

Two rules make this measurement mean something, and both were established by measurement rather than assumed:

Only candidates that cover the whole key are comparable. The engine also returns prefixes, and a summed log-probability is larger for fewer characters, so scoring a mixed-length list ranks the shortest candidate first every time regardless of quality.

Only decoder-assembled leading candidates are reranked. When the engine's first candidate is an exact dictionary hit on the whole key it carries corpus frequency that this model does not have, and reranking those loses accuracy at every margin. When the first candidate was assembled by the lattice or the fallback decoder it carries no frequency evidence, and that is where the model pays.

usage:
  python rerank_eval.py --model dist/sentence-v1.safetensors --cases dumps/sentences.jsonl
"""

import argparse
import json

import torch
import torch.nn.functional as F
from safetensors.torch import load_file

from model import BOS, CharLM, Config

# CandidateSource values that mean "this row is an exact full-key hit in a dictionary".
# See quanpin/word_lattice.h for the ordering these come from.
DICTIONARY_SOURCES = (0, 1)


def load(path, device):
    tensors = load_file(path)
    with open(path, "rb") as handle:
        header_len = int.from_bytes(handle.read(8), "little")
        metadata = json.loads(handle.read(header_len))["__metadata__"]

    cfg = Config(**json.loads(metadata["config"]))
    vocab = json.loads(metadata["vocab"])

    if metadata["precision"] == "int8":
        restored = {}
        for name, tensor in tensors.items():
            if name.endswith(".scale"):
                continue
            scale = tensors.get(name + ".scale")
            restored[name] = tensor.float() * scale[:, None] if scale is not None else tensor.float()
        tensors = restored
    else:
        tensors = {name: tensor.float() for name, tensor in tensors.items()}

    tensors["head.weight"] = tensors["tok.weight"]
    model = CharLM(cfg)
    model.load_state_dict(tensors)
    model.eval().to(device)
    return model, cfg, {ch: i for i, ch in enumerate(vocab)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True)
    parser.add_argument("--cases", required=True)
    parser.add_argument("--margin", type=float, default=0.0, help="required advantage in nats per character before the engine's order is overridden")
    parser.add_argument("--ungated", action="store_true", help="also rerank dictionary hits, to show what the gate is worth")
    args = parser.parse_args()

    device = "mps" if torch.backends.mps.is_available() else ("cuda" if torch.cuda.is_available() else "cpu")
    model, cfg, index = load(args.model, device)

    @torch.no_grad()
    def score(context, texts):
        """Mean log P(character) over each candidate, conditioned on the committed text."""
        prefix = ([BOS] + [index.get(ch, 1) for ch in context])[-(cfg.context - 1) :]
        tails = [[index.get(ch, 1) for ch in text][: cfg.context - len(prefix)] for text in texts]
        width = max(len(tail) for tail in tails)
        rows = [prefix + tail + [0] * (width - len(tail)) for tail in tails]
        logits, _ = model(torch.tensor(rows, dtype=torch.long, device=device))
        logp = F.log_softmax(logits.float(), dim=-1)
        start = len(prefix) - 1
        return [
            sum(logp[r, start + j, token].item() for j, token in enumerate(tail)) / max(1, len(tail))
            for r, tail in enumerate(tails)
        ]

    buckets = {}
    for line in open(args.cases, encoding="utf-8"):
        case = json.loads(line)
        gold = case["gold"]
        covering = [c for c in case["candidates"] if len(c["text"]) == len(gold)][:9]
        if len(covering) < 2:
            continue
        texts = [c["text"] for c in covering]
        gated = covering[0]["source"] in DICTIONARY_SOURCES

        bucket = buckets.setdefault("dictionary" if gated else "decoded", {"n": 0, "before": 0, "after": 0})
        bucket["n"] += 1
        bucket["before"] += texts[0] == gold

        if gated and not args.ungated:
            bucket["after"] += texts[0] == gold
            continue
        scores = score(case.get("context", ""), texts)
        best = max(range(len(texts)), key=lambda i: scores[i])
        chosen = texts[best] if scores[best] - scores[0] > args.margin else texts[0]
        bucket["after"] += chosen == gold

    total = {"n": 0, "before": 0, "after": 0}
    for key in ("dictionary", "decoded"):
        if key in buckets:
            for field in total:
                total[field] += buckets[key][field]
    rows = [(k, buckets[k]) for k in ("dictionary", "decoded") if k in buckets] + [("all", total)]

    print(f"{'leading candidate':<20}{'n':>7}{'engine':>9}{'reranked':>10}{'delta':>8}")
    for name, bucket in rows:
        n = bucket["n"] or 1
        before, after = bucket["before"] / n, bucket["after"] / n
        print(f"{name:<20}{bucket['n']:>7}{before:>9.3f}{after:>10.3f}{after - before:>+8.3f}")


if __name__ == "__main__":
    main()
