# Sentence model

A character-level language model that reranks candidates the pinyin decoder assembled.

## What it is for, and what it is not for

Measured against the evaluation sets in `resources/eval`, reranking helps in exactly one situation and hurts in the other:

| Leading candidate from the engine | cases | engine top-1 | reranked top-1 |
|---|---|---|---|
| Exact dictionary hit on the whole key (`Database` / `UserDatabase`) | 2065 | **0.747** | 0.602 |
| Assembled by the lattice or the fallback decoder | 40 | 0.400 | **0.700** |

A dictionary hit on the whole key carries corpus frequency that a character model does not have, and overriding it loses accuracy at every margin threshold tried. A decoder-assembled candidate carries no frequency evidence, and that is where the model pays for itself.

So the model is gated: it reranks only when the engine's leading candidate is decoder-assembled. `rerank_eval.py` enforces that gate and reports both buckets, so a regression in either one is visible.

The second rule the evaluation depends on is that only candidates covering the whole key are comparable. The engine also returns prefixes, and a summed log-probability is larger for fewer characters, so scoring a mixed-length list puts the shortest candidate first every time.

## What the pipeline produces

The `keyboard` preset trained for 50,000 steps on 520 million characters of Wikipedia and LCCC, 66 minutes on an M-series GPU, reaching validation perplexity 49.0:

| | cases | engine top-1 | reranked top-1 |
|---|---|---|---|
| Sentences | 26 | 0.615 | **0.769** |
| Words, decoder-assembled leader | 14 | 0.000 | **0.500** |
| Words, dictionary leader | 2065 | 0.747 | 0.747 |

The corpus mix matters in the direction the split predicts. Trained on LCCC dialogue alone the model reached the same sentence accuracy but only 0.286 on decoder-assembled words, whose vocabulary is written register — 火力发电, 保护国, 畅销品. Adding Wikipedia moved that bucket to 0.500 and left sentences where they were.

Quantization is free here. The int8 and float16 exports disagree on no ranking decision across all 2105 cases, so the 7.1 MB file is the one to ship.

## Running it

```sh
pip install -r requirements.txt

python corpus.py wiki --out data/wiki.txt
python corpus.py lccc --out data/lccc.txt --split large

python train.py --corpus data/wiki.txt data/lccc.txt --out runs/keyboard --preset keyboard
python export.py --run runs/keyboard --out dist/sentence-v1.safetensors --precision int8

cargo run --release -p msime-input-runtime --example convert_eval -- \
  --resources <resource directory> --set resources/eval/sentences-v1.tsv --dump dumps/sentences.jsonl
python rerank_eval.py --model dist/sentence-v1.safetensors --cases dumps/sentences.jsonl
```

## Presets

| Preset | Layers | Width | Context | Vocabulary | Parameters | int8 | f16 |
|---|---|---|---|---|---|---|---|
| `keyboard` | 6 | 256 | 64 | 8192 | 6.8M | 7.1 MB | 13.9 MB |
| `desktop` | 8 | 448 | 128 | 12288 | ~24M | ~24 MB | ~48 MB |

`keyboard` is sized to load inside an iOS keyboard extension, which shares a memory budget with the engine and its dictionaries.

## Output format

Plain safetensors. The configuration, the vocabulary and the corpus attribution travel in the `__metadata__` header, so the model is one self-describing file with no sidecars to keep in sync.

Embeddings are tied, and `head.weight` is therefore absent from the file; a loader reuses `tok.weight`. Under `--precision int8`, two-dimensional weights are quantized symmetrically per output row and accompanied by a `<name>.scale` float32 tensor; norm parameters, biases and the positional table stay in float32.

## Corpora and licensing

- Chinese Wikipedia article dumps — CC BY-SA 4.0
- LCCC — MIT

Both permit redistributing a model trained on them, and both require the attribution to travel with it. `export.py` writes it into the `attribution` metadata field of the weights file rather than into a document beside it, so it cannot be separated from the weights.
