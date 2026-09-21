/**
 * The touch keyboard's measurements, taken from the iOS extension in
 * platforms/ios/KeyboardExtension/Sources/KeyboardViewController.swift so the two keyboards are laid
 * out the same way.
 *
 * They live here rather than in the view because the extension ability has to size the panel before
 * the view exists, and a panel that disagrees with its content either clips the bottom row or leaves
 * a band of empty space under it.
 */
export class KeyboardMetrics {
  static readonly ROOT_HORIZONTAL_PADDING_VP: number = 5;
  static readonly ROOT_VERTICAL_PADDING_VP: number = 7;
  static readonly ROW_SPACING_VP: number = 7;
  static readonly KEY_SPACING_VP: number = 6;
  static readonly KEY_CORNER_VP: number = 8;
  static readonly KEY_FONT_SIZE: number = 20;
  static readonly SMALL_KEY_FONT_SIZE: number = 15;
  static readonly LANGUAGE_FONT_SIZE: number = 13;
  static readonly MODIFIER_WIDTH_VP: number = 44;
  static readonly RETURN_WIDTH_VP: number = 59;
  static readonly LANGUAGE_WIDTH_VP: number = 34;
  static readonly LAYOUT_TOGGLE_WIDTH_VP: number = 48;
  static readonly ROW_HEIGHT_VP: number = 44;
  static readonly KEY_ROWS: number = 4;

  static readonly COMPOSITION_ROW_HEIGHT_VP: number = 28;
  static readonly CANDIDATE_ROW_HEIGHT_VP: number = 40;
  /** One caption-sized line reserved before an asynchronous candidate gloss arrives. */
  static readonly CANDIDATE_GLOSS_LINE_HEIGHT_VP: number = 14;
  static readonly CANDIDATE_FONT_SIZE: number = 20;
  static readonly CANDIDATE_PADDING_VP: number = 12;
  static readonly STRIP_CORNER_VP: number = 12;

  /**
   * Everything the view stacks vertically, including the gaps between the pieces.
   *
   * The two spacings and the height adjustment come from the user's settings, clamped by
   * KeyboardGeometry. They are passed in rather than read here so this stays a pure calculation the
   * ability and the view can both do and agree on.
   */
  static totalHeightVp(rowSpacingTenths: number = KeyboardMetrics.ROW_SPACING_VP * 10,
                       heightAdjustmentVp: number = 0, glossRows: number = 0,
                       candidateFontSize: number = KeyboardMetrics.CANDIDATE_FONT_SIZE): number {
    const strip: number =
      KeyboardMetrics.COMPOSITION_ROW_HEIGHT_VP + KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP
      + KeyboardMetrics.glossHeightVp(glossRows, candidateFontSize);
    const keys: number = KeyboardMetrics.ROW_HEIGHT_VP * KeyboardMetrics.KEY_ROWS
      + heightAdjustmentVp;
    // One gap between the strip and the first key row, and one between each pair of key rows.
    const gaps: number = (rowSpacingTenths / 10) * KeyboardMetrics.KEY_ROWS;
    return strip + keys + gaps + KeyboardMetrics.ROOT_VERTICAL_PADDING_VP * 2;
  }

  /**
   * How wide a candidate window is, where the panel is not the width of the screen.
   *
   * Fallback width before the first Engine view arrives. The host replaces it with the bounded
   * CandidateWidthPolicy estimate once candidates are available.
   */
  static readonly CANDIDATE_WINDOW_WIDTH_VP: number = 420;
  /** Clear of the caret's own line, so the window sits under the text rather than on it. */
  static readonly CANDIDATE_WINDOW_GAP_VP: number = 4;

  /**
   * The strip on its own, which is the whole panel where the machine has its own keys.
   *
   * No key rows and therefore none of the gaps between them: what is left is the composition line,
   * the candidate line and the padding that frames them.
   */
  static candidateHeightVp(layout: string = 'horizontal', candidateCount: number = 0,
                           showPreedit: boolean = true,
                           decorationTopVp: number = 0, glossRows: number = 0,
                           candidateFontSize: number = KeyboardMetrics.CANDIDATE_FONT_SIZE): number {
    const rows: number = layout === 'vertical'
      ? Math.max(1, Math.min(9, candidateCount)) : 1;
    const decoration: number = Number.isFinite(decorationTopVp) && decorationTopVp > 0
      ? Math.min(512, decorationTopVp) : 0;
    return decoration + (showPreedit ? KeyboardMetrics.COMPOSITION_ROW_HEIGHT_VP : 0)
      + KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP * rows
      + (layout === 'vertical' ? 0 : KeyboardMetrics.glossHeightVp(glossRows, candidateFontSize))
      + KeyboardMetrics.ROOT_VERTICAL_PADDING_VP * 2;
  }

  static glossHeightVp(rows: number,
                       candidateFontSize: number = KeyboardMetrics.CANDIDATE_FONT_SIZE): number {
    if (!Number.isFinite(rows)) return 0;
    const font: number = Number.isFinite(candidateFontSize) ? Math.max(1, candidateFontSize) : 1;
    const line: number = Math.max(KeyboardMetrics.CANDIDATE_GLOSS_LINE_HEIGHT_VP,
      Math.ceil(font * 0.78));
    return Math.max(0, Math.floor(rows)) * line;
  }
}
