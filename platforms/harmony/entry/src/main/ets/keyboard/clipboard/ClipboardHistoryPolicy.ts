/**
 * Privacy and size bounds for text-only clipboard history entries, ported from
 * platforms/android/java/app/msime/client/ClipboardHistoryPolicy.java.
 *
 * The byte bound is measured in UTF-8, which is what the store writes.
 */
import { utf8Length } from '../Utf8';

const MAX_CHARS: number = 10000;
const MAX_BYTES: number = 40000;

export class ClipboardHistoryPolicy {
  static readonly LIMIT: number = 50;
  static readonly MAX_CHARS: number = MAX_CHARS;
  static readonly MAX_BYTES: number = MAX_BYTES;

  static acceptable(text: string | null): boolean {
    return text !== null && text.trim().length > 0 && text.length <= MAX_CHARS
      && utf8Length(text) <= MAX_BYTES;
  }
}
