"""Build a character-level training corpus for the candidate-reranking model.

Two sources, both redistributable:

- Chinese Wikipedia article dumps (CC BY-SA 4.0) — written prose, supplies the vocabulary and the register the IME meets when someone is composing a sentence.
- LCCC (MIT) — open-domain dialogue, supplies the colloquial register that Wikipedia has almost none of.

Output is one normalized sentence per line, UTF-8. Everything outside the kept character set is a segmentation boundary rather than a substitution, because the model only ever scores runs of Chinese characters: at inference the candidates handed to it come from the pinyin decoder and contain nothing else.

usage:
  python corpus.py wiki  --out data/wiki.txt  [--max-chars 2_000_000_000]
  python corpus.py lccc  --out data/lccc.txt  [--split base|large]
"""

import argparse
import bz2
import gzip
import json
import os
import re
import sys
import urllib.request

WIKI_DUMP = "https://dumps.wikimedia.org/zhwiki/latest/zhwiki-latest-pages-articles.xml.bz2"
LCCC_BASE = "https://huggingface.co/datasets/silver/lccc/resolve/main/lccc_base_train.jsonl.gz"
LCCC_LARGE = "https://huggingface.co/datasets/silver/lccc/resolve/main/lccc_large.jsonl.gz"

# CJK unified ideographs plus extension A, and the handful of punctuation marks that carry
# sentence structure. Latin, digits and everything else become boundaries.
KEEP = re.compile(r"[一-鿿㐀-䶿]+")
PUNCT = "，。！？、；：""''（）《》…—"

MIN_LINE = 4
MAX_LINE = 96


def download(url, path):
    """Fetch to `path` unless it is already there, reporting progress on a single line."""
    if os.path.exists(path):
        print(f"cached {path}", file=sys.stderr)
        return path
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".part"
    print(f"downloading {url}", file=sys.stderr)
    with urllib.request.urlopen(url) as response, open(tmp, "wb") as out:
        total = int(response.headers.get("content-length") or 0)
        done = 0
        while chunk := response.read(1 << 20):
            out.write(chunk)
            done += len(chunk)
            pct = f"{100 * done / total:.1f}%" if total else f"{done >> 20} MiB"
            print(f"\r  {pct}", end="", file=sys.stderr)
    print("", file=sys.stderr)
    os.replace(tmp, path)
    return path


def segment(text):
    """Yield runs of Chinese characters, split at every other character and clipped to MAX_LINE."""
    for match in KEEP.finditer(text):
        run = match.group()
        for start in range(0, len(run), MAX_LINE):
            piece = run[start : start + MAX_LINE]
            if len(piece) >= MIN_LINE:
                yield piece


# Wikitext constructs that survive into <text> and would otherwise contribute nonsense character
# sequences. Applied in order; each one is replaced by a space so it also acts as a boundary.
WIKI_NOISE = [
    re.compile(r"(?s)<ref.*?(?:/>|</ref>)"),
    re.compile(r"(?s)<!--.*?-->"),
    re.compile(r"(?s)<(math|code|pre|gallery|timeline)[^>]*>.*?</\1>"),
    re.compile(r"(?s)\{\{[^{}]*\}\}"),
    re.compile(r"(?s)\{\|.*?\|\}"),
    re.compile(r"\[\[(?:File|Image|檔案|文件|图像|圖像):[^\]]*\]\]"),
    re.compile(r"</?[a-zA-Z][^>]*>"),
    re.compile(r"^[*#:;=|!].*$", re.MULTILINE),
]
WIKI_LINK = re.compile(r"\[\[(?:[^\]|]*\|)?([^\]|]*)\]\]")
TEXT_OPEN = re.compile(rb"<text[^>]*>")
TEXT_CLOSE = b"</text>"


def strip_wikitext(raw):
    text = WIKI_LINK.sub(r"\1", raw)
    for pattern in WIKI_NOISE:
        # Templates nest, so the innermost-first pattern is applied until it stops matching.
        if pattern.pattern.endswith(r"\{\{[^{}]*\}\}"):
            while pattern.search(text):
                text = pattern.sub(" ", text)
        else:
            text = pattern.sub(" ", text)
    return text.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")


def wiki_lines(path, max_chars):
    """Stream <text> bodies out of the bz2 dump without holding the XML in memory."""
    emitted = 0
    buffer = b""
    capturing = False
    with bz2.open(path, "rb") as handle:
        while chunk := handle.read(1 << 22):
            buffer += chunk
            while True:
                if not capturing:
                    match = TEXT_OPEN.search(buffer)
                    if not match:
                        buffer = buffer[-16:]
                        break
                    buffer = buffer[match.end() :]
                    capturing = True
                end = buffer.find(TEXT_CLOSE)
                if end < 0:
                    break
                body = buffer[:end].decode("utf-8", "replace")
                buffer = buffer[end + len(TEXT_CLOSE) :]
                capturing = False
                for line in segment(strip_wikitext(body)):
                    yield line
                    emitted += len(line)
                    if max_chars and emitted >= max_chars:
                        return


def lccc_lines(path, max_chars):
    """Each row is a JSON array of dialogue turns; every turn is an independent sample."""
    emitted = 0
    with gzip.open(path, "rt", encoding="utf-8") as handle:
        for row in handle:
            row = row.strip()
            if not row or row[0] != "[":
                continue
            try:
                turns = json.loads(row)
            except json.JSONDecodeError:
                continue
            for turn in turns:
                # LCCC ships pre-tokenized with spaces between characters; joining restores the raw text.
                for line in segment(str(turn).replace(" ", "")):
                    yield line
                    emitted += len(line)
                    if max_chars and emitted >= max_chars:
                        return


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", choices=["wiki", "lccc"])
    parser.add_argument("--out", required=True)
    parser.add_argument("--cache", default="data/raw")
    parser.add_argument("--split", choices=["base", "large"], default="base")
    parser.add_argument("--max-chars", type=int, default=0, help="stop after this many kept characters; 0 means the whole source")
    args = parser.parse_args()

    if args.source == "wiki":
        archive = download(WIKI_DUMP, os.path.join(args.cache, "zhwiki-latest-pages-articles.xml.bz2"))
        lines = wiki_lines(archive, args.max_chars)
    else:
        url = LCCC_LARGE if args.split == "large" else LCCC_BASE
        archive = download(url, os.path.join(args.cache, os.path.basename(url)))
        lines = lccc_lines(archive, args.max_chars)

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    count = chars = 0
    with open(args.out, "w", encoding="utf-8") as out:
        for line in lines:
            out.write(line)
            out.write("\n")
            count += 1
            chars += len(line)
            if count % 500_000 == 0:
                print(f"\r  {count:,} lines / {chars:,} chars", end="", file=sys.stderr)
    print(f"\r{args.out}: {count:,} lines / {chars:,} chars", file=sys.stderr)


if __name__ == "__main__":
    main()
