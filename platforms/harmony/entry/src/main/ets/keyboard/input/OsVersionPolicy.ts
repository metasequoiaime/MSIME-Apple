/**
 * The OS release, as the feedback report should carry it.
 *
 * The shared feedback page attaches the operating system version so a report says which release it
 * came from. A host that cannot supply one is not left with a blank: the page falls back to naming
 * the platform and pasting the web view's user agent. That fallback is what this host was doing —
 * a report from HarmonyOS said `平台：harmony` and then quoted a browser engine string, which
 * identifies the WebView rather than the system anyone would need to reproduce the problem on.
 *
 * `deviceInfo.osFullName` is formatted `<name>-<major>.<minor>.<feature>.<build>`. The page prints
 * it after the platform's own name, so the leading product name is dropped: `HarmonyOS 6.0.1.115`
 * rather than `HarmonyOS OpenHarmony-6.0.1.115`.
 *
 * Nothing is invented. This string goes into a report a user files, so it reports what the system
 * says or nothing at all — the same rule the macOS host applies to the value it reads out of
 * `SystemVersion.plist`.
 */

/** Long enough for any release string, short enough that a stray value cannot fill a report. */
const MAX_VERSION_CHARACTERS = 64;

export class OsVersionPolicy {
  /**
   * The release to attach, or null when what the system reported is not one.
   *
   * A value with no digit in it is not a version however it is formatted, and returning it would
   * put a word where a release number belongs. Null is the honest answer, and the page already
   * knows what to do with it.
   */
  static release(osFullName: string | undefined): string | null {
    if (typeof osFullName !== "string") return null;
    const trimmed = osFullName.trim();
    if (trimmed.length === 0 || trimmed.length > MAX_VERSION_CHARACTERS) return null;
    // eslint-disable-next-line no-control-regex
    if (/[\u0000-\u001f\u007f]/.test(trimmed)) return null;
    // The product name before the first hyphen is dropped because the page prints the platform's
    // own name in front of this. A value with no hyphen is taken whole: it is already the version.
    const separator = trimmed.indexOf("-");
    const version = separator < 0 ? trimmed : trimmed.slice(separator + 1).trim();
    if (version.length === 0) return null;
    return /[0-9]/.test(version) ? version : null;
  }
}
