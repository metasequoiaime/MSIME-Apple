/**
 * How wide a candidate is while glosses are switched on, ported from
 * platforms/ios/KeyboardExtension/Sources/KeyboardKeyButton.swift.
 *
 * The width has to be independent of whether the gloss has arrived. The networked ones come back
 * over a few hundred milliseconds, one at a time; let them decide the width and each candidate
 * widens as its answer lands, pushing everything to its right along with it. The source states the
 * rule as: divide the visible strip into columns first, then fill the answers into the columns.
 *
 * Three columns, not four. At four a column is about seventy points, and a gloss like
 * "draft; draw up" has to be cut — and a gloss that is cut is a gloss that was not written.
 *
 * The candidate itself is never cut. A word wider than a column widens its own chip instead; the
 * column is a floor for a chip that carries a gloss, not a ceiling for the word.
 */
export class CandidateChipWidth {
  /**
   * Three across the visible strip.
   *
   * The count is the source's, and the comment above is its reason. It is a constant rather than a
   * setting because the reason is about how much text a gloss needs, not about taste.
   */
  static readonly GLOSS_COLUMNS: number = 3;

  /**
   * The text width of one column, once the gaps between chips and a chip's own padding are out.
   *
   * `visible` is the part of the strip the user can see — not the scrollable extent, which is as
   * long as the candidate list happens to be.
   */
  static column(visible: number, spacing: number, horizontalPadding: number): number {
    if (!Number.isFinite(visible) || visible <= 0) {
      return 0;
    }
    const columns: number = CandidateChipWidth.GLOSS_COLUMNS;
    const gaps: number = Math.max(0, spacing) * (columns - 1);
    const text: number = (visible - gaps) / columns - Math.max(0, horizontalPadding) * 2;
    return Math.max(0, text);
  }

  /**
   * The text width a chip gives its contents: the column when it carries a gloss, else the word.
   *
   * `hasGloss` rather than a gloss width, because the width must not depend on what came back —
   * a chip waiting for its answer is exactly as wide as one that has it.
   */
  static content(wordWidth: number, hasGloss: boolean, column: number): number {
    const word: number = Number.isFinite(wordWidth) ? Math.max(0, wordWidth) : 0;
    return hasGloss ? Math.max(word, Math.max(0, column)) : word;
  }

  /** The whole chip, padding included, rounded up to the whole units the layout works in. */
  static chip(
    wordWidth: number,
    hasGloss: boolean,
    column: number,
    horizontalPadding: number,
  ): number {
    return Math.ceil(
      CandidateChipWidth.content(wordWidth, hasGloss, column) + Math.max(0, horizontalPadding) * 2,
    );
  }
}
