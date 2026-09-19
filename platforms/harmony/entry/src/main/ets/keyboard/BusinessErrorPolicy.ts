/**
 * Telling a failed AsyncCallback from a successful one.
 *
 * OHOS passes a `BusinessError` to every AsyncCallback, on success as well as on failure, and on
 * success it carries `code: 0`. So `if (error)` is always true — the object is there either way —
 * and a callback written that way reports a failure every single time.
 *
 * Both places this host used that shape were wrong in ways that matter. The settings page logged
 * "would not load" on every successful load, which then made a real load failure indistinguishable
 * from the noise. Handwriting recognition took the failure branch before it ever looked at the
 * snapshot, so it answered 无法读取手写画布 on every stroke and never recognised anything.
 */
export class BusinessErrorPolicy {
  /** Whether an AsyncCallback's first argument describes an actual failure. */
  static failed(error: Object | null | undefined): boolean {
    if (error === null || error === undefined) {
      return false;
    }
    const code: Object | undefined = (error as Record<string, Object>).code;
    // A missing code is not a success: a plain Error thrown into the callback has none.
    return typeof code !== "number" || (code as number) !== 0;
  }

  /** What to say about it, without pretending a code-less error had one. */
  static describe(error: Object | null | undefined): string {
    if (error === null || error === undefined) {
      return "unknown error";
    }
    const record: Record<string, Object> = error as Record<string, Object>;
    const code: Object | undefined = record.code;
    const message: Object | undefined = record.message;
    const text: string = message === undefined ? "" : String(message);
    return code === undefined
      ? text.length > 0
        ? text
        : "unknown error"
      : `code ${String(code)}${text.length > 0 ? ": " + text : ""}`;
  }
}
