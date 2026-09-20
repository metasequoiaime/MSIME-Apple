/**
 * Where a picked skin folder is allowed to land.
 *
 * The source lets a user drop a skin into the client's skin folder and offers a button that opens
 * it. That button exists on this host too and was permanently disabled, because the folder lives in
 * the application sandbox where no file manager can reach it — the catalog scans it and reads from
 * it, and nobody could put anything in.
 *
 * A picker replaces the folder: the user chooses a skin folder wherever it actually is, and it is
 * copied in. The goal is the source's; only the mechanism is this platform's, because this platform
 * has no user-visible folder to open.
 *
 * The name comes from a folder the user chose, which means it comes from outside. A skin called
 * `../../engine` would write over the staged dictionary, and one called `.` or `..` would mean the
 * skins root itself, so the name is checked here rather than trusted because it looks like a folder
 * name.
 */

/** Long enough for any real skin, short enough that the path stays within the filesystem's limit. */
const MAX_NAME_LENGTH: number = 64;

export class SkinImportPolicy {
  /**
   * The folder name to import under, or null when the pick cannot be used.
   *
   * A separator of either kind is refused outright rather than stripped: a name that has to be
   * rewritten before it is safe is not a name the user recognises, and silently importing
   * `a/b` as `ab` would leave them looking for something that is not there.
   */
  static destinationName(picked: string | null | undefined): string | null {
    if (picked === null || picked === undefined) {
      return null;
    }
    const name: string = picked.trim();
    if (name.length === 0 || name.length > MAX_NAME_LENGTH) {
      return null;
    }
    if (name === "." || name === "..") {
      return null;
    }
    if (name.includes("/") || name.includes("\\")) {
      return null;
    }
    for (const character of name) {
      const code: number = character.codePointAt(0) ?? 0;
      // Control characters reach a log, a settings page and a filename; none of them want one.
      if (code < 0x20 || code === 0x7f) {
        return null;
      }
    }
    return name;
  }

  /**
   * The last path segment of a picked URI, which is the folder the user chose.
   *
   * Written against the segment rather than the whole URI because the rest of it — the scheme, the
   * provider, the encoded path — is the picker's business and differs between providers.
   */
  static pickedName(uri: string | null | undefined): string | null {
    if (uri === null || uri === undefined) {
      return null;
    }
    const withoutQuery: string = uri.split("?")[0];
    const trimmed: string = withoutQuery.endsWith("/")
      ? withoutQuery.substring(0, withoutQuery.length - 1)
      : withoutQuery;
    const segments: string[] = trimmed.split("/");
    const last: string | undefined = segments[segments.length - 1];
    if (last === undefined) {
      return null;
    }
    let decoded: string = last;
    try {
      decoded = decodeURIComponent(last);
    } catch (error) {
      // A malformed escape is not worth failing the import over; the raw segment still has to pass
      // destinationName, which is where anything dangerous is refused.
      decoded = last;
    }
    return SkinImportPolicy.destinationName(decoded);
  }
}
