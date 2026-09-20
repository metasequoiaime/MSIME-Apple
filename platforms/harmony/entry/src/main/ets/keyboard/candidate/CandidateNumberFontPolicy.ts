/**
 * How large the number beside a candidate is drawn.
 *
 * The source states it as a ratio — `.num { font-size: 0.8em }` in every candidate stylesheet — so
 * the number keeps its proportion to the candidate at any size the user picks. This host had a
 * fixed subtraction with a floor instead, which agrees with nothing: at the shared default of 18 it
 * draws 10 where the source draws 14.4, and the two diverge in both directions as the size moves,
 * because a constant offset is not a ratio.
 *
 * Only the number is decided here. The auxiliary code, the badge and the offline gloss use the
 * same subtraction in this host, and the source's horizontal template has no rule for any of them —
 * there is nothing to copy, and inventing a ratio for them would be making the appearance up rather
 * than matching it.
 */

/** `.num { font-size: 0.8em }`, from the candidate stylesheets the source renders. */
const NUMBER_RATIO: number = 0.8;

export class CandidateNumberFontPolicy {
  /**
   * The number's size for a given candidate size, rounded to whole units as ArkUI lays out in.
   *
   * The shared document validates the candidate size to 12..=32, so the result lands in 10..=26
   * without needing a floor of its own. A document that somehow carried a smaller size would still
   * not produce a zero or negative size here, which is the only thing a floor would have been
   * protecting against.
   */
  static size(candidateFontSize: number): number {
    if (!Number.isFinite(candidateFontSize) || candidateFontSize <= 0) {
      return 1;
    }
    return Math.max(1, Math.round(candidateFontSize * NUMBER_RATIO));
  }
}
