import { describe, expect, it } from "vitest";
import { DICTIONARY_PAGE_SIZE, decodeDictionaryBytes, dictionaryPageStatus } from "../../../packages/ui/src/dictionary-file";

const utf8 = (text: string) => new TextEncoder().encode(text);

describe("dictionary file decoding", () => {
  it("reads plain UTF-8 without a marker", () => {
    expect(decodeDictionaryBytes(utf8("nihao\t你好\t100000"))).toBe("nihao\t你好\t100000");
  });

  it("drops the UTF-8 byte order mark instead of leaking it into the first key", () => {
    const bytes = new Uint8Array([0xef, 0xbb, 0xbf, ...utf8("ni\t你")]);
    expect(decodeDictionaryBytes(bytes)).toBe("ni\t你");
  });

  it("reads the UTF-16 files Windows dictionary tools still write", () => {
    const little = new Uint8Array([0xff, 0xfe, 0x60, 0x4f, 0x7d, 0x59]);
    expect(decodeDictionaryBytes(little)).toBe("你好");
    const big = new Uint8Array([0xfe, 0xff, 0x4f, 0x60, 0x59, 0x7d]);
    expect(decodeDictionaryBytes(big)).toBe("你好");
  });

  it("falls back to GB18030 rather than replacement characters", () => {
    // "你好" in GB18030, which is not valid UTF-8.
    const bytes = new Uint8Array([0xc4, 0xe3, 0xba, 0xc3]);
    expect(decodeDictionaryBytes(bytes)).toBe("你好");
  });
});

describe("dictionary pagination status", () => {
  it("reports the range and whether more results follow", () => {
    expect(dictionaryPageStatus(0, DICTIONARY_PAGE_SIZE, true)).toBe("第 1–100 条，后面还有结果");
    expect(dictionaryPageStatus(100, 20, false)).toBe("第 101–120 条");
  });

  it("says so when a page came back empty", () => {
    expect(dictionaryPageStatus(0, 0, false)).toBe("没有更多结果");
    expect(dictionaryPageStatus(300, 0, true)).toBe("没有更多结果");
  });
});
