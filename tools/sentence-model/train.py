"""Train the candidate-reranking character model.

Takes one or more normalized corpora from `corpus.py`, derives a vocabulary from character frequency, packs the text into a memory-mapped token array, and trains. Both the vocabulary and the packed array are cached next to the output so that re-running with different hyperparameters does not repeat the preparation.

usage:
  python train.py --corpus data/wiki.txt data/lccc.txt --out runs/keyboard --preset keyboard --steps 40000
"""

import argparse
import dataclasses
import json
import math
import os
import time
from collections import Counter

import numpy as np
import torch

from model import BOS, RESERVED, CharLM, Config


def pick_device():
    if torch.cuda.is_available():
        return "cuda"
    if torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def build_vocab(paths, size):
    """Keep the `size` most frequent characters. Coverage is reported because a vocabulary that drops real text into <unk> teaches the model that <unk> is likely, and it will then rank it highly."""
    counts = Counter()
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                counts.update(line.rstrip("\n"))
    ranked = [ch for ch, _ in counts.most_common(size - len(RESERVED))]
    kept = sum(counts[ch] for ch in ranked)
    total = sum(counts.values())
    print(f"vocab: {len(ranked):,} of {len(counts):,} distinct characters, covering {100 * kept / total:.4f}% of the corpus")
    return RESERVED + ranked


def pack(paths, index, cache):
    """Encode every line as BOS + characters into one flat uint16 array on disk."""
    if os.path.exists(cache):
        print(f"cached {cache}")
        return np.memmap(cache, dtype=np.uint16, mode="r")
    total = 0
    with open(cache, "wb") as out:
        buffer = []
        for path in paths:
            with open(path, encoding="utf-8") as handle:
                for line in handle:
                    line = line.rstrip("\n")
                    if not line:
                        continue
                    buffer.append(BOS)
                    buffer.extend(index.get(ch, 1) for ch in line)
                    if len(buffer) >= 1 << 22:
                        np.asarray(buffer, dtype=np.uint16).tofile(out)
                        total += len(buffer)
                        buffer.clear()
        if buffer:
            np.asarray(buffer, dtype=np.uint16).tofile(out)
            total += len(buffer)
    print(f"packed {total:,} tokens into {cache}")
    return np.memmap(cache, dtype=np.uint16, mode="r")


def batches(tokens, batch, context, device, generator):
    """Sample independent windows. Lines are concatenated, so a window may straddle two of them; BOS marks the boundary and the model learns to restart there, which is what it must do at inference when the committed text is empty."""
    while True:
        starts = torch.randint(0, len(tokens) - context - 1, (batch,), generator=generator)
        x = torch.stack([torch.from_numpy(tokens[s : s + context].astype(np.int64)) for s in starts])
        y = torch.stack([torch.from_numpy(tokens[s + 1 : s + 1 + context].astype(np.int64)) for s in starts])
        yield x.to(device, non_blocking=True), y.to(device, non_blocking=True)


def learning_rate(step, total, peak, warmup):
    if step < warmup:
        return peak * (step + 1) / warmup
    progress = (step - warmup) / max(1, total - warmup)
    return 0.1 * peak + 0.45 * peak * (1 + math.cos(math.pi * progress))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", nargs="+", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--preset", default="keyboard")
    parser.add_argument("--steps", type=int, default=40000)
    parser.add_argument("--batch", type=int, default=64)
    parser.add_argument("--lr", type=float, default=3e-4)
    parser.add_argument("--warmup", type=int, default=500)
    parser.add_argument("--eval-every", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=1234)
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    cfg = Config.preset(args.preset)
    torch.manual_seed(args.seed)

    vocab_path = os.path.join(args.out, "vocab.json")
    if os.path.exists(vocab_path):
        tokens_list = json.load(open(vocab_path, encoding="utf-8"))["tokens"]
    else:
        tokens_list = build_vocab(args.corpus, cfg.vocab)
        json.dump({"tokens": tokens_list}, open(vocab_path, "w", encoding="utf-8"), ensure_ascii=False)
    cfg.vocab = len(tokens_list)
    index = {ch: i for i, ch in enumerate(tokens_list)}

    data = pack(args.corpus, index, os.path.join(args.out, "tokens.u16"))
    split = int(len(data) * 0.999)
    train_tokens, val_tokens = data[:split], data[split:]

    device = pick_device()
    model = CharLM(cfg).to(device)
    print(f"{cfg.parameters():,} parameters on {device}, {len(train_tokens):,} training tokens")

    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, betas=(0.9, 0.95), weight_decay=0.1)
    generator = torch.Generator().manual_seed(args.seed)
    train_stream = batches(train_tokens, args.batch, cfg.context, device, generator)
    val_stream = batches(val_tokens, args.batch, cfg.context, device, torch.Generator().manual_seed(7))

    best = float("inf")
    started = time.monotonic()
    for step in range(args.steps):
        for group in optimizer.param_groups:
            group["lr"] = learning_rate(step, args.steps, args.lr, args.warmup)
        x, y = next(train_stream)
        _, loss = model(x, y)
        optimizer.zero_grad(set_to_none=True)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        optimizer.step()

        if (step + 1) % args.eval_every == 0 or step + 1 == args.steps:
            model.eval()
            with torch.no_grad():
                val = sum(model(*next(val_stream))[1].item() for _ in range(20)) / 20
            model.train()
            elapsed = time.monotonic() - started
            print(f"step {step + 1:>6}/{args.steps}  train {loss.item():.4f}  val {val:.4f}  ppl {math.exp(val):.2f}  {elapsed / 60:.1f} min")
            if val < best:
                best = val
                torch.save(
                    {"config": dataclasses.asdict(cfg), "model": model.state_dict(), "val": val, "step": step + 1},
                    os.path.join(args.out, "checkpoint.pt"),
                )
    print(f"best validation loss {best:.4f} (perplexity {math.exp(best):.2f})")


if __name__ == "__main__":
    main()
