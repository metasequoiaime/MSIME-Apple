/**
 * The family list the candidate panel draws with.
 *
 * ArkUI takes a CSS-style list and resolves it per glyph, which is what makes a separate English
 * font expressible here at all: naming it first means Latin comes from it and Han falls through to
 * the Chinese family behind it. That ordering is the shared rule — `resolved-candidate-fonts.ts`
 * composes the same sequence for the settings preview, and Android's `preferredFont()` picks the
 * English family ahead of the primary one for the same reason.
 *
 * An unset English font is not a name to skip past; it means the Chinese family answers for
 * everything, which is the single-family list this host has always built.
 */
const MAX_FAMILIES: number = 33;

export class CandidateFontFamilyPolicy {
  static families(primary: string, english: string | null, fallbacks: string[]): string {
    const families: string[] = [];
    CandidateFontFamilyPolicy.push(families, english);
    CandidateFontFamilyPolicy.push(families, primary);
    for (const fallback of fallbacks) {
      CandidateFontFamilyPolicy.push(families, fallback);
    }
    return families.join(', ');
  }

  /**
   * Names are what the settings page stores, and it validates them; this refuses a second time
   * because a list is being built for a text renderer, and a name carrying a comma would silently
   * become two families.
   */
  private static push(families: string[], name: string | null): void {
    if (name === null || families.length >= MAX_FAMILIES) {
      return;
    }
    const trimmed: string = name.trim();
    if (trimmed.length === 0 || trimmed.includes(',') || families.includes(trimmed)) {
      return;
    }
    families.push(trimmed);
  }
}
