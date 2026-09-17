"""Export a trained checkpoint as a single file the client can ship and load.

The output is plain safetensors. The configuration, the vocabulary and the corpus attribution travel in the safetensors `__metadata__` header, so the model is one self-describing file with no sidecars to keep in sync and no bespoke container format to parse on the other side.

Quantization is per-output-row and symmetric. Norm parameters and biases stay in float32: they are a negligible share of the file and the most sensitive to rounding.

usage:
  python export.py --run runs/keyboard --out dist/sentence-v1.safetensors [--precision f16|int8]
"""

import argparse
import json
import os

import torch
from safetensors.torch import save_file

from model import CharLM, Config

# Both corpora permit redistribution of a model trained on them, and both require that the
# attribution travel with it. It is written into the file rather than into a document beside
# the file so that it cannot be separated from the weights.
ATTRIBUTION = (
    "Trained on Chinese Wikipedia (CC BY-SA 4.0, https://dumps.wikimedia.org/zhwiki/) "
    "and LCCC (MIT, https://github.com/thu-coai/CDial-GPT)."
)

# Rounding these to int8 costs more accuracy than it saves bytes.
KEEP_FLOAT = ("ln1.", "ln2.", "ln_f.", ".bias", "pos.weight")


def quantize_int8(tensor):
    """Symmetric per-row quantization. Returns the int8 values and the float32 scale per row."""
    flat = tensor.reshape(tensor.shape[0], -1).float()
    scale = flat.abs().amax(dim=1).clamp(min=1e-8) / 127.0
    values = torch.round(flat / scale[:, None]).clamp(-127, 127).to(torch.int8)
    return values.reshape(tensor.shape), scale


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", required=True, help="training output directory containing checkpoint.pt and vocab.json")
    parser.add_argument("--out", required=True)
    parser.add_argument("--precision", choices=["f16", "int8"], default="f16")
    args = parser.parse_args()

    checkpoint = torch.load(os.path.join(args.run, "checkpoint.pt"), map_location="cpu", weights_only=True)
    vocab = json.load(open(os.path.join(args.run, "vocab.json"), encoding="utf-8"))["tokens"]
    cfg = Config(**checkpoint["config"])

    model = CharLM(cfg)
    model.load_state_dict(checkpoint["model"])
    model.eval()

    tensors = {}
    for name, tensor in model.state_dict().items():
        # The head is tied to the token table; writing it again would double the largest tensor.
        if name == "head.weight":
            continue
        if args.precision == "int8" and tensor.dim() == 2 and not any(k in name for k in KEEP_FLOAT):
            values, scale = quantize_int8(tensor)
            tensors[name] = values.contiguous()
            tensors[name + ".scale"] = scale.contiguous()
        elif args.precision == "f16" and tensor.is_floating_point() and not any(k in name for k in KEEP_FLOAT):
            tensors[name] = tensor.to(torch.float16).contiguous()
        else:
            tensors[name] = tensor.float().contiguous()

    metadata = {
        "format": "msime-sentence-model",
        "version": "1",
        "precision": args.precision,
        "config": json.dumps(checkpoint["config"], separators=(",", ":")),
        "vocab": json.dumps(vocab, ensure_ascii=False, separators=(",", ":")),
        "tied_embeddings": "true",
        "validation_loss": f"{checkpoint['val']:.6f}",
        "training_steps": str(checkpoint["step"]),
        "license": "GPL-3.0-only",
        "attribution": ATTRIBUTION,
    }

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    save_file(tensors, args.out, metadata=metadata)
    size = os.path.getsize(args.out)
    print(f"{args.out}: {size / 1e6:.1f} MB, {cfg.parameters():,} parameters, {args.precision}, validation loss {checkpoint['val']:.4f}")


if __name__ == "__main__":
    main()
