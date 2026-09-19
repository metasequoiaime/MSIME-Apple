/** Shared preference gate for the private clipboard-history feature. */
export class ClipboardHistoryPreferencePolicy {
  /** Missing and malformed values are deliberately treated as disabled. */
  static enabled(value: unknown): boolean {
    return value === true;
  }

  static canReadOrWrite(enabled: boolean): boolean {
    return enabled;
  }

  /** A disabled preference always requires cleanup, including on a fresh keyboard start. */
  static shouldClearHistory(enabled: boolean): boolean {
    return !enabled;
  }
}
