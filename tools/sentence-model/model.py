"""Character-level transformer language model for candidate reranking.

The model exists to answer one question at inference time: given the text already committed, which of the candidates the pinyin decoder assembled reads like Chinese? It is deliberately small. The probe that justified this work showed the gain is confined to decoder-assembled candidates and never applies to exact dictionary hits, so the model runs on a narrow slice of keystrokes and has to fit inside a mobile keyboard extension alongside the engine.

Sizes are configuration, not constants: `Config.preset` names the shapes we have measured.
"""

import dataclasses
import math

import torch
import torch.nn.functional as F
from torch import nn

PAD, UNK, BOS = 0, 1, 2
RESERVED = ["<pad>", "<unk>", "<bos>"]


@dataclasses.dataclass
class Config:
    vocab: int = 8192
    n_layer: int = 6
    n_head: int = 4
    n_embd: int = 256
    context: int = 64
    dropout: float = 0.1

    @staticmethod
    def preset(name):
        if name == "keyboard":
            # ~6.8M parameters. Fits an iOS keyboard extension after int8 quantization.
            return Config()
        if name == "desktop":
            # ~24M parameters. For measuring how much accuracy the keyboard preset gives up.
            return Config(vocab=12288, n_layer=8, n_head=8, n_embd=448, context=128)
        raise ValueError(f"unknown preset {name!r}")

    def parameters(self):
        """Parameter count, counting the tied embedding once."""
        embed = self.vocab * self.n_embd + self.context * self.n_embd
        attn = 4 * self.n_embd * self.n_embd + 4 * self.n_embd
        mlp = 8 * self.n_embd * self.n_embd + 5 * self.n_embd
        return embed + self.n_layer * (attn + mlp) + 2 * self.n_embd


class Block(nn.Module):
    def __init__(self, cfg):
        super().__init__()
        self.n_head = cfg.n_head
        self.ln1 = nn.LayerNorm(cfg.n_embd)
        self.qkv = nn.Linear(cfg.n_embd, 3 * cfg.n_embd)
        self.proj = nn.Linear(cfg.n_embd, cfg.n_embd)
        self.ln2 = nn.LayerNorm(cfg.n_embd)
        self.fc = nn.Linear(cfg.n_embd, 4 * cfg.n_embd)
        self.out = nn.Linear(4 * cfg.n_embd, cfg.n_embd)
        self.drop = nn.Dropout(cfg.dropout)

    def forward(self, x):
        b, t, c = x.shape
        h = self.n_head
        q, k, v = self.qkv(self.ln1(x)).split(c, dim=2)
        shape = (b, t, h, c // h)
        q, k, v = (z.view(shape).transpose(1, 2) for z in (q, k, v))
        y = F.scaled_dot_product_attention(q, k, v, is_causal=True)
        x = x + self.drop(self.proj(y.transpose(1, 2).reshape(b, t, c)))
        return x + self.drop(self.out(F.gelu(self.fc(self.ln2(x)))))


class CharLM(nn.Module):
    def __init__(self, cfg):
        super().__init__()
        self.cfg = cfg
        self.tok = nn.Embedding(cfg.vocab, cfg.n_embd)
        self.pos = nn.Embedding(cfg.context, cfg.n_embd)
        self.drop = nn.Dropout(cfg.dropout)
        self.blocks = nn.ModuleList(Block(cfg) for _ in range(cfg.n_layer))
        self.ln_f = nn.LayerNorm(cfg.n_embd)
        # Tied embeddings: the output projection reuses the token table. On a vocabulary this
        # large relative to the model, an untied head would be a third of the whole file.
        self.head = nn.Linear(cfg.n_embd, cfg.vocab, bias=False)
        self.head.weight = self.tok.weight
        self.apply(self._init)
        for name, param in self.named_parameters():
            # Scale the residual projections so the residual stream does not grow with depth.
            if name.endswith(("proj.weight", "out.weight")):
                nn.init.normal_(param, std=0.02 / math.sqrt(2 * cfg.n_layer))

    @staticmethod
    def _init(module):
        if isinstance(module, (nn.Linear, nn.Embedding)):
            nn.init.normal_(module.weight, std=0.02)
        if isinstance(module, nn.Linear) and module.bias is not None:
            nn.init.zeros_(module.bias)

    def forward(self, idx, targets=None):
        t = idx.shape[1]
        pos = torch.arange(t, device=idx.device)
        x = self.drop(self.tok(idx) + self.pos(pos))
        for block in self.blocks:
            x = block(x)
        logits = self.head(self.ln_f(x))
        if targets is None:
            return logits, None
        loss = F.cross_entropy(
            logits.view(-1, logits.size(-1)), targets.reshape(-1), ignore_index=PAD
        )
        return logits, loss
