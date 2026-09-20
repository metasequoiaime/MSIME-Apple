/**
 * How the offline gloss beside a candidate is drawn.
 *
 * The source states it in every skin's vertical stylesheet, identically:
 *
 *   .cand-translation { margin-left: 0.65em; font-size: 0.78em; opacity: 0.62; }
 *
 * A ratio, a gap and a transparency — none of which this host had. It drew the translation with the
 * same fixed subtraction the rest of the secondary text uses, which is not a ratio and diverges
 * from the source at every size, and with no transparency at all, so a gloss carried the same
 * weight on the row as the candidate it is glossing.
 *
 * The Engine's own annotation shares this slot here but has no rule in either the horizontal or the
 * vertical stylesheet, so it keeps what it had. Styling it from this rule would be assuming the
 * source meant the same thing for both, and the source does not say so.
 */

/** `.cand-translation { font-size: 0.78em }`. */
const TRANSLATION_RATIO: number = 0.78;
/** `.cand-translation { opacity: 0.62 }`. */
export const TRANSLATION_OPACITY: number = 0.62;
/** `.cand-translation { margin-left: 0.65em }`, in units of the candidate size. */
const TRANSLATION_GAP_RATIO: number = 0.65;

export class CandidateTranslationStyle {
  /** The gloss size for a given candidate size, rounded to the whole units ArkUI lays out in. */
  static fontSize(candidateFontSize: number): number {
    if (!Number.isFinite(candidateFontSize) || candidateFontSize <= 0) {
      return 1;
    }
    return Math.max(1, Math.round(candidateFontSize * TRANSLATION_RATIO));
  }

  /**
   * The gap between the candidate and its gloss.
   *
   * `em` in `margin-left` resolves against the element's own computed font size, not the parent's —
   * only `font-size` itself looks upwards. The gloss is already 0.78 of the row, so the gap the
   * source draws is 0.65 of that, not 0.65 of the candidate.
   */
  static gap(candidateFontSize: number): number {
    if (!Number.isFinite(candidateFontSize) || candidateFontSize <= 0) {
      return 0;
    }
    return Math.max(0, Math.round(candidateFontSize * TRANSLATION_RATIO * TRANSLATION_GAP_RATIO));
  }
}
