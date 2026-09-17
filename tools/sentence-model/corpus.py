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
import urllib.error
import urllib.request

WIKI_DUMP = "https://dumps.wikimedia.org/zhwiki/latest/zhwiki-latest-pages-articles.xml.bz2"
LCCC_BASE = "https://huggingface.co/datasets/silver/lccc/resolve/main/lccc_base_train.jsonl.gz"
LCCC_LARGE = "https://huggingface.co/datasets/silver/lccc/resolve/main/lccc_large.jsonl.gz"

USER_AGENT = "MSIME-Client sentence-model corpus builder (https://github.com/metasequoiaime/MSIME-Client)"

# CJK unified ideographs plus extension A. Everything else — Latin, digits, punctuation — is a
# boundary rather than a substitution, because at inference the candidates handed to the model
# come from the pinyin decoder and contain nothing but these characters.
KEEP = re.compile(r"[一-鿿㐀-䶿]+")

MIN_LINE = 4
MAX_LINE = 96

# Chinese Wikipedia stores each article in whichever variant its editors used and converts only at
# render time, so the dump is a mix. This engine emits simplified characters, so traditional text
# would teach the model a parallel vocabulary that no candidate can ever contain, splitting
# probability mass between variants and spending vocabulary slots on the half we never score.
#
# These are traditional forms whose simplified counterpart is a different character.
TRADITIONAL = set(
    "們來這國會個時發當後萬與東車長門問開關電話語說讀點對還進遠過樣學實現經濟應該為數屬體麼兩內從產業讓認機動華區"
    "邏輯嚴謹導詞稱種義議論據處質網統標準級結構總織線給續練縮聯興舉寫農運達適選鐵錄鐘銀陸際隨險難靜韓頭題顯風飛馬驗黨齊龍"
)

# Filtering happens twice, because the two levels are answering different questions.
#
# A document is traditional or it is not, and the markers above are common enough that a genuinely
# traditional one spends several percent of its characters on them. Discarding a document on a
# single marker throws away most of Wikipedia: simplified articles quote traditional titles and
# names constantly, and requiring zero markers kept only about a fifth of the corpus.
TRADITIONAL_SHARE = 0.005

# Within a document that passed, a fragment carrying any marker at all is the quoted traditional
# name itself, so it is dropped outright. Fragments run a handful of characters, which is why this
# test cannot be the one that judges the document.


def traditional_share(text):
    return sum(ch in TRADITIONAL for ch in text) / max(1, len(text))


def is_traditional_document(text):
    return traditional_share(text) > TRADITIONAL_SHARE


ATTEMPTS = 5


def fetch_once(url, tmp):
    """One transfer attempt, resuming from whatever is already in `tmp`. Returns (bytes on disk, expected total)."""
    done = os.path.getsize(tmp) if os.path.exists(tmp) else 0
    # Wikimedia refuses the default urllib agent with 403; their policy requires a descriptive one.
    headers = {"User-Agent": USER_AGENT}
    if done:
        headers["Range"] = f"bytes={done}-"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request) as response:
        # A server that ignores Range answers 200 with the whole body. Appending that to what is
        # already on disk would produce a corrupt file that still satisfies a length check, so the
        # partial file is discarded instead.
        if done and response.status != 206:
            done = 0
        total = done + int(response.headers.get("content-length") or 0)
        reported = done
        with open(tmp, "ab" if done else "wb") as out:
            while chunk := response.read(1 << 20):
                out.write(chunk)
                done += len(chunk)
                if done - reported >= 1 << 26:
                    reported = done
                    print(f"  {100 * done / total:.0f}%" if total else f"  {done >> 20} MiB", file=sys.stderr)
    return done, total


def download(url, path):
    """Fetch to `path` unless it is already there, resuming and retrying until the whole body arrives."""
    if os.path.exists(path):
        print(f"cached {path}", file=sys.stderr)
        return path
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".part"
    print(f"downloading {url}", file=sys.stderr)
    # A multi-gigabyte transfer gets cut short often enough that it has to be treated as normal.
    # urllib reports a truncated body as a clean end of stream, so without comparing what arrived
    # against the advertised length the result is a short file that still decompresses, and it
    # then reads as a smaller corpus rather than as a failure.
    for attempt in range(1, ATTEMPTS + 1):
        try:
            done, total = fetch_once(url, tmp)
        except (urllib.error.URLError, ConnectionError, TimeoutError) as error:
            print(f"  attempt {attempt} failed: {error}", file=sys.stderr)
            continue
        if not total or done >= total:
            os.replace(tmp, path)
            return path
        print(f"  attempt {attempt} short by {(total - done) >> 20} MiB", file=sys.stderr)
    raise IOError(f"{url}: incomplete after {ATTEMPTS} attempts")


def segment(text):
    """Yield runs of Chinese characters, split at every other character and clipped to MAX_LINE."""
    for match in KEEP.finditer(text):
        run = match.group()
        for start in range(0, len(run), MAX_LINE):
            piece = run[start : start + MAX_LINE]
            if len(piece) >= MIN_LINE and not TRADITIONAL.intersection(piece):
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
# `pages-articles` is articles plus templates, file descriptions and meta-pages. Only namespace 0
# is prose; the rest is interface strings and boilerplate repeated across thousands of pages.
NAMESPACE = re.compile(rb"<ns>(\d+)</ns>")
ARTICLE_NAMESPACE = b"0"
# Enough to hold a page header, so that an <ns> element is never separated from the <text> it
# describes when the two straddle a read boundary.
CARRY = 4096


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
    article = False
    with bz2.open(path, "rb") as handle:
        while chunk := handle.read(1 << 22):
            buffer += chunk
            while True:
                if not capturing:
                    match = TEXT_OPEN.search(buffer)
                    if not match:
                        buffer = buffer[-CARRY:]
                        break
                    namespaces = NAMESPACE.findall(buffer[: match.start()])
                    if namespaces:
                        article = namespaces[-1] == ARTICLE_NAMESPACE
                    buffer = buffer[match.end() :]
                    capturing = True
                end = buffer.find(TEXT_CLOSE)
                if end < 0:
                    break
                body = buffer[:end].decode("utf-8", "replace")
                buffer = buffer[end + len(TEXT_CLOSE) :]
                capturing = False
                if not article:
                    continue
                stripped = strip_wikitext(body)
                if is_traditional_document(stripped):
                    continue
                for line in segment(stripped):
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
                utterance = str(turn).replace(" ", "")
                if is_traditional_document(utterance):
                    continue
                for line in segment(utterance):
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
