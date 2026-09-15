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
                       heightAdjustmentVp: number = 0): number {
    const strip: number =
      KeyboardMetrics.COMPOSITION_ROW_HEIGHT_VP + KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP;
    const keys: number = KeyboardMetrics.ROW_HEIGHT_VP * KeyboardMetrics.KEY_ROWS
      + heightAdjustmentVp;
    // One gap between the strip and the first key row, and one between each pair of key rows.
    const gaps: number = (rowSpacingTenths / 10) * KeyboardMetrics.KEY_ROWS;
    return strip + keys + gaps + KeyboardMetrics.ROOT_VERTICAL_PADDING_VP * 2;
  }
}
