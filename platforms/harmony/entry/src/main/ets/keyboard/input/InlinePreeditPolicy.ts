/**
 * What the 2in1 shows of a composition inside the document, from the shared `tsf_preedit_style`.
 *
 * Windows draws the spelling inline through TSF (`raw` letters, segmented `pinyin`, or nothing), and the Linux hosts read the same field for their inline preedit. HarmonyOS offers the equivalent as preview text (`InputClient.setPreviewText`), which an editor may or may not support. A phone keeps the spelling in the strip above its keys, a touch layout with no candidate window next to the caret, so the setting is a desktop one here.
 */
/** One of `raw`, `pinyin` or `empty`, as the shared preference spells them. */
export type InlinePreeditStyle = string;

export class InlinePreeditPolicy {
  /** Anything unknown falls back to the shipped default, as the Windows and Linux readers do. */
  static style(value: string | null | undefined): InlinePreeditStyle {
    return value === "pinyin" || value === "empty" ? value : "raw";
  }

  /**
   * The preview text for one Engine view; empty means none should be shown.
   *
   * A held phrase piece leads the spelling, as the candidate window draws it, so the characters already picked stay visible in the document instead of vanishing until the phrase is committed.
   */
  static text(
    style: InlinePreeditStyle,
    desktop: boolean,
    supported: boolean,
    editing: string,
    preedit: string,
    phrasePrefix: string,
  ): string {
    if (!desktop || !supported || style === "empty" || editing.length === 0) return "";
    const spelling: string = style === "pinyin" && preedit.length > 0 ? preedit : editing;
    return phrasePrefix + spelling;
  }

  /**
   * The document text before the composition, given what the editor reports before the caret.
   *
   * An editor that counts preview text as its content reports the spelling as the text before the caret; a punctuation key deciding on the preceding character must see what the user wrote, not the letters of the composition it is about to replace.
   */
  static beforePreview(forward: string, preview: string): string {
    return preview.length > 0 && forward.endsWith(preview)
      ? forward.substring(0, forward.length - preview.length)
      : forward;
  }
}
