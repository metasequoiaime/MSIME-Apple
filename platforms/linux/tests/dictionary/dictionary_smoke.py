"""Isolated synthetic dictionary requests through the Linux executable."""
import ctypes
import json
import os
import pathlib
import subprocess
import sys
import tempfile

if os.environ.get("MSIME_ISOLATED_LINUX_TEST") != "1":
    sys.exit("Run only in the dedicated Linux test container")

binary, library, resources = sys.argv[1:]
host = ctypes.CDLL(library)
for name in ("msime_client_prepare_host", "msime_client_create"):
    function = getattr(host, name)
    function.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
    function.restype = ctypes.c_void_p
host.msime_client_destroy.argtypes = [ctypes.c_uint64]
host.msime_client_destroy.restype = ctypes.c_void_p
host.msime_client_string_free.argtypes = [ctypes.c_void_p]


def decode(pointer):
    assert pointer, "Missing native response"
    try:
        return json.loads(ctypes.string_at(pointer))
    finally:
        host.msime_client_string_free(pointer)


def native(name, document):
    encoded = json.dumps(document).encode()
    result = decode(getattr(host, name)(encoded, len(encoded)))
    assert result["ok"], f"Native fixture setup failed: {result.get('error')}"
    return result["value"]


with tempfile.TemporaryDirectory(prefix="msime-dictionary-cli-") as directory:
    options = native("msime_client_prepare_host", {
        "resources": resources, "state_root": directory,
    })

    def request(action, success=True):
        encoded = json.dumps({"options": options, "action": action}).encode()
        result = subprocess.run([binary], input=encoded, capture_output=True, timeout=20)
        assert result.returncode == (0 if success else 1), "Wrong management exit status"
        assert not result.stderr, "Unexpected management stderr"
        document = json.loads(result.stdout)
        assert document["ok"] == success, "Wrong management result"
        return document.get("value") if success else document.get("error")

    def listing(offset=0, limit=100, **search):
        return request({"operation": "list", "offset": offset, "limit": limit, **search})

    def edit(previous, replacement, identifier, success=True):
        return request({"operation": "edit", "previous": previous,
                        "replacement": replacement, "request_id": identifier}, success)

    assert listing()["entries"] == [], "Fixture was not empty"
    entries = [
        {"kind": "pinyin", "key": "ce'shi'ci", "value": "测试词", "weight": 12345},
        {"kind": "wubi", "key": "aaaa", "value": "测试", "weight": 12345},
        {"kind": "quick_phrase", "key": "fixture", "value": "测试短语", "weight": 12345},
        {"kind": "english", "key": "fixture", "value": "fixture", "weight": 12345},
    ]
    session = native("msime_client_create", options)["session"]
    edit(None, entries[0], "busy-fixture", False)
    assert listing()["entries"] == [], "Busy edit changed the dictionary"
    assert decode(host.msime_client_destroy(session))["ok"], "Cannot close fixture session"
    for index, entry in enumerate(entries):
        edit(None, entry, f"add-fixture-{index}")
        edit(None, entry, f"add-fixture-{index}")
    page = listing(0, 2)
    remainder = listing(2, 2)
    assert page["has_more"] and not remainder["has_more"], "Wrong dictionary pagination"
    assert len(page["entries"] + remainder["entries"]) == 4, "Retry duplicated entries"
    previous = entries[2]
    replacement = dict(previous, value="测试替换")
    edit(previous, replacement, "replace-fixture")
    edit(previous, None, "stale-fixture", False)
    assert dict(replacement, source="user") in listing()["entries"], "Stale edit changed replacement"
    for index, entry in enumerate([entries[0], entries[1], replacement, entries[3]]):
        edit(entry, None, f"delete-fixture-{index}")
    assert listing()["entries"] == [], "Delete did not persist"

    # Full pinyin typed without separators is cut into syllables on save and still found by an unseparated or partial search; an abbreviation is refused with the rule it broke rather than a generic failure.
    typed = {"kind": "pinyin", "key": "nihao", "value": "你好", "weight": 12345}
    stored = dict(typed, key="ni'hao")
    edit(None, typed, "add-unseparated")
    listed = dict(stored, source="user")
    for query in ["nihao", "nih", "NiHao", "ni hao", "ni'hao"]:
        found = listing(kind="pinyin", query=query)["entries"]
        # A search also finds the bundled words under the prefix; the user's own word leads them.
        assert found and found[0] == listed, f"Pinyin search missed the stored key: {query}"
    assert listed not in listing(kind="pinyin", query="hao")["entries"], "Search is not a prefix"
    refused = edit(None, dict(typed, key="nhao"), "add-abbreviated", False)
    assert refused.startswith("invalid dictionary entry: "), "Refusal lost its reason"
    assert "nhao" not in refused and "你好" not in refused, "Refusal echoed the entry"
    assert listing()["entries"] == [listed], "Refused edit changed the dictionary"
    edit(stored, None, "delete-unseparated")
    assert listing()["entries"] == [], "Delete did not persist"

    # A bundled word is found by its code, can be re-weighted - which the pinyin export then carries - or deleted, and nothing else about it can change.
    def bundled_row(key, value):
        rows = listing(kind="pinyin", query=key)["entries"]
        return next((row for row in rows if row["key"] == key and row["value"] == value), None)

    def pinyin_export():
        return request({"operation": "export", "kind": "pinyin", "format": "windows",
                        "offset": 0, "limit": 1000})["text"].splitlines()

    word = next(row for row in listing(kind="pinyin", query="nihao")["entries"]
                if row["source"] == "bundled" and len(row["value"]) > 1)
    weight = 7 if word["weight"] != 7 else 8
    edit(word, dict(word, weight=weight), "reweight-bundled")
    reweighted = dict(word, weight=weight)
    assert bundled_row(word["key"], word["value"]) == reweighted, "Bundled weight did not persist"
    assert f"{word['key']}\t{word['value']}\t{weight}" in pinyin_export(), "Export lost the weight"
    edit(word, dict(word, weight=weight + 1), "stale-bundled", False)
    refused = edit(reweighted, dict(reweighted, value="改动"), "rename-bundled", False)
    assert refused == "bundled dictionary entry is read-only", "Bundled rename was not refused"
    assert listing()["entries"] == [], "A bundled edit became a user word"
    edit(reweighted, None, "delete-bundled")
    assert bundled_row(word["key"], word["value"]) is None, "Bundled delete did not persist"
    assert not any(line.startswith(f"{word['key']}\t{word['value']}\t")
                   for line in pinyin_export()), "Export kept a deleted bundled word"

for invalid, status in [(b"", 2), (b"x" * 65537, 2), (b"{", 1)]:
    result = subprocess.run([binary], input=invalid, capture_output=True, timeout=10)
    assert result.returncode == status and not result.stderr, "Invalid request boundary failed"
print("Linux dictionary CLI list/edit/retry/busy/bounds/pinyin-search/bundled-entry acceptance passed")
