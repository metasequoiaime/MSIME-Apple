/**
 * Candidate skins are a separate shared preference from the touch-keyboard skins.
 *
 * Harmony does not ship the Windows CSS skin renderer, and for a while that was taken to mean the
 * four source skins had to be approximated onto the touch-keyboard palettes. Not rendering someone
 * else's CSS does not require inventing someone else's colours: the upstream stylesheets are
 * carried in this repository under `packages/ui/src/upstream/candidate-themes/skins`, so each skin
 * can be drawn natively in its own colours instead of the nearest available ones.
 *
 * The approximation also collided. 微信绿 and 杨柳青 both landed on `forest`, which made two of the
 * four skins pixel-identical — `#07c160` and `#58b980` are not close, and one of the four was
 * effectively missing. Each id now resolves to itself and to a palette taken from its own
 * stylesheet; explicit candidate colours still win over the palette, as they always did.
 */
export class CandidateSkinPolicy {
  /**
   * The colour a candidate pinned to this position is drawn in.
   *
   * The source marks it with one fixed blue of its own (`CandidateViewHtml` in
   * `server/src/window/candidate_view_model.h` wraps the item in `color:#379AD3`), deliberately not
   * the selected-row colour: being pinned and being the current selection are different states and
   * a user has to be able to tell them apart. Drawing both in the skin's accent, as this panel did,
   * made them identical on every skin whose accent is also its selection colour.
   */
  static readonly FIXED_POSITION_COLOR = "#379AD3";

  /** The text colour for a candidate row, given whether it is selected and whether it is pinned. */
  static rowTextColor(
    highlighted: boolean,
    fixedPosition: boolean,
    textColor: string,
    selectedTextColor: string,
  ): string {
    if (fixedPosition) return CandidateSkinPolicy.FIXED_POSITION_COLOR;
    return highlighted ? selectedTextColor : textColor;
  }

  /** Auxiliary code and translations inherit the selected row's text colour, like the Windows CSS. */
  static rowDetailColor(
    highlighted: boolean,
    textColor: string,
    selectedTextColor: string,
  ): string {
    return highlighted ? selectedTextColor : textColor;
  }

  static harmonySkin(
    candidateSkin: string | null | undefined,
    externalBase: string | null | undefined = null,
  ): string {
    switch (candidateSkin) {
      case "fluent":
      case "wechat":
      case "graphite":
      case "willow_green":
        // Each has a palette of its own in KeyboardSkin, built from its own upstream stylesheet.
        return candidateSkin;
      default:
        if (externalBase !== null && externalBase !== undefined && externalBase !== candidateSkin) {
          return CandidateSkinPolicy.harmonySkin(externalBase, null);
        }
        return "forest";
    }
  }

  static showSelectedBar(
    candidateSkin: string | null | undefined,
    externalValue: boolean | null | undefined = null,
  ): boolean {
    if (externalValue !== null && externalValue !== undefined) {
      return externalValue;
    }
    return candidateSkin !== "wechat" && candidateSkin !== "graphite";
  }
}
