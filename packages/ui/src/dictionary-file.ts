// Dictionary exports in the wild are not all UTF-8: Windows tools still write
// UTF-16 with a BOM and GB18030. Ported from the shipped settings page so an
// imported file reads the same here.
function decodeUtf8(bytes: Uint8Array, fatal: boolean): string {
  return new TextDecoder("utf-8", { fatal }).decode(bytes);
}

export function decodeDictionaryBytes(bytes: Uint8Array): string {
  if (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    return decodeUtf8(bytes.subarray(3), true);
  }
  if (bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xfe) {
    return new TextDecoder("utf-16le").decode(bytes.subarray(2));
  }
  if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) {
    return new TextDecoder("utf-16be").decode(bytes.subarray(2));
  }
  try {
    return decodeUtf8(bytes, true);
  } catch {
    // A legacy encoding is more likely than a corrupt file; replacement
    // characters are the last resort rather than the first.
    for (const label of ["gb18030", "gbk"]) {
      try {
        return new TextDecoder(label).decode(bytes);
      } catch {
        continue;
      }
    }
    return decodeUtf8(bytes, false);
  }
}

export async function readDictionaryFile(file: File): Promise<string> {
  return decodeDictionaryBytes(new Uint8Array(await file.arrayBuffer()));
}

export const DICTIONARY_PAGE_SIZE = 100;

/// Status line for one page of results, matching the shipped pager.
export function dictionaryPageStatus(offset: number, count: number, hasMore: boolean): string {
  if (!count) return "没有更多结果";
  return `第 ${offset + 1}–${offset + count} 条${hasMore ? "，后面还有结果" : ""}`;
}
