/**
 * Estimates the width a desktop candidate panel needs before ArkUI has laid out its Text nodes.
 *
 * Harmony cannot synchronously measure a candidate row from the input-method ability, while the
 * ability must resize and place the panel before it is shown. The estimate intentionally favours
 * stable bounds over font-specific precision: wide code points use one em, Latin text uses a
 * half-em, and the result is clamped so a long provider annotation cannot cover the whole desktop.
 */
export interface CandidateWidthEntry {
  readonly text: string;
  readonly badge: string;
  readonly hint: string;
  readonly annotation: string;
}

export class CandidateWidthPolicy {
  static readonly MIN_WIDTH_VP: number = 280;
  static readonly MAX_WIDTH_VP: number = 720;
  private static readonly LATIN_EM: number = 0.58;
  private static readonly WIDE_EM: number = 1.0;
  private static readonly EXTRA_WIDTH_VP: number = 48;

  /** Approximate text extent without leaking platform font or layout dependencies into the host. */
  static textWidthVp(text: string, fontSize: number): number {
    if (fontSize <= 0) {
      throw new Error('Invalid candidate font size');
    }
    let ems: number = 0;
    for (const character of text) {
      const codePoint: number = character.codePointAt(0) ?? 0;
      ems += CandidateWidthPolicy.isWide(codePoint)
        ? CandidateWidthPolicy.WIDE_EM : CandidateWidthPolicy.LATIN_EM;
    }
    return ems * fontSize;
  }

  /** Return the clamped panel width for the current preedit and candidate page. */
  static widthVp(entries: CandidateWidthEntry[], editing: string, candidateFontSize: number,
                 preeditFontSize: number, minWidthVp: number = CandidateWidthPolicy.MIN_WIDTH_VP,
                 maxWidthVp: number = CandidateWidthPolicy.MAX_WIDTH_VP): number {
    if (candidateFontSize <= 0 || preeditFontSize <= 0 || minWidthVp < 0
        || maxWidthVp < minWidthVp) {
      throw new Error('Invalid candidate width dimensions');
    }
    let contentWidth: number = CandidateWidthPolicy.textWidthVp(editing, preeditFontSize);
    for (const entry of entries) {
      const suffix = entry.badge + entry.hint + entry.annotation;
      const candidateWidth = CandidateWidthPolicy.textWidthVp(entry.text, candidateFontSize)
        + CandidateWidthPolicy.textWidthVp(suffix, Math.max(12, candidateFontSize - 8));
      contentWidth = Math.max(contentWidth, candidateWidth);
    }
    const boundedMinimum: number = Math.max(CandidateWidthPolicy.MIN_WIDTH_VP,
      Math.min(maxWidthVp, minWidthVp));
    return Math.min(maxWidthVp,
      Math.max(boundedMinimum, Math.ceil(contentWidth + CandidateWidthPolicy.EXTRA_WIDTH_VP)));
  }

  private static isWide(codePoint: number): boolean {
    return (codePoint >= 0x1100 && codePoint <= 0x115f)
      || (codePoint >= 0x2e80 && codePoint <= 0xa4cf)
      || (codePoint >= 0xac00 && codePoint <= 0xd7ff)
      || (codePoint >= 0xf900 && codePoint <= 0xfaff)
      || (codePoint >= 0xfe10 && codePoint <= 0xfe6f)
      || (codePoint >= 0xff01 && codePoint <= 0xff60)
      || (codePoint >= 0x1f300 && codePoint <= 0x1faff);
  }
}
