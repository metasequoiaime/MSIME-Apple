/**
 * What a screen reader says for each key, which is not what the key face says.
 *
 * A key face is as short as it can be and often not a word at all: `⇧`, `123`, `，`, `中`. Read
 * aloud those are nothing, a number, a comma and a character with no context. The source names
 * every one of them, and the names are deliberately about what the key *does* rather than what it
 * shows — `中` reads as 切换中英文, not as the character 中.
 *
 * Several of these labels were already ported into this host: `LetterKeyFacePolicy`,
 * `EnglishLetterCaseState`, `JapaneseVariantPolicy` and `CandidateGlossPolicy` each compute one.
 * They had no callers outside their own tests, because nothing in the view ever attached them —
 * the labels existed and the keyboard said nothing. This file adds the names those four did not
 * cover, and the view now attaches all of them.
 */

/** Ported from the source's key construction, where each of these is an `accessibilityLabel`. */
export class KeyAccessibilityPolicy {
  /** A symbol read as a symbol: the glyph alone is often not pronounceable. */
  static symbol(face: string): string {
    return face.length === 0 ? "符号" : `符号 ${face}`;
  }

  static delete(): string {
    return "删除";
  }

  /**
   * The space bar, which says what it will do rather than what it is.
   *
   * Mid-composition it selects the highlighted candidate, and the source reads it that way — a
   * user who cannot see the candidate row has no other way to know the key has changed meaning.
   */
  static space(composing: boolean): string {
    return composing ? "选定" : "空格";
  }

  /** The return key, read as whatever it is about to do. The face already carries that word. */
  static returnKey(face: string): string {
    return face.length === 0 ? "换行" : face;
  }

  /** Never the mode it is in: a label that read 中 would be the character, not the action. */
  static language(): string {
    return "切换中英文";
  }

  /** The layout toggle, in whichever direction it is pointing. */
  static layoutToggle(showingSymbols: boolean): string {
    return showingSymbols ? "切换到所选输入方案" : "切换到数字和符号";
  }

  /** The comma key, whose long press opens the punctuation list. */
  static punctuation(): string {
    return "常用标点";
  }

  static symbolPanel(): string {
    return "符号面板";
  }

  static scheme(): string {
    return "选择输入方案";
  }

  static skin(): string {
    return "切换皮肤";
  }

  static tools(): string {
    return "更多快捷设置";
  }

  // The rest of the shortcut bar. Each says what the button does rather than what it looks like,
  // as the keys above do; the reply entry is conditional on its scheme but follows the same rule.
  static emoji(): string {
    return "表情与符号";
  }

  static voice(): string {
    return "语音输入";
  }

  static reply(): string {
    return "生成高情商回复";
  }

  static geometry(): string {
    return "键盘大小与间距";
  }

  static dismiss(): string {
    return "收起键盘";
  }

  /**
   * One candidate, numbered as it is shown.
   *
   * The number is part of the label because it is how the user selects it on a hardware keyboard
   * and how the row is described in the source. `hint` is the spelling still to be typed, which
   * turns "this word" into "this word, if you keep going" — the difference between a candidate
   * that commits now and one that does not.
   */
  static candidate(number: number, display: string, hint: string, suffix: string): string {
    const base =
      hint.length === 0
        ? `候选词 ${number}：${display}`
        : `候选词 ${number}：${display}，还需输入 ${hint}`;
    return base + suffix;
  }
}
