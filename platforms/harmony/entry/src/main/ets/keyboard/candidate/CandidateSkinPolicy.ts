/**
 * Candidate skins are a separate shared preference from the touch-keyboard skins. Harmony does
 * not ship the Windows CSS skin renderer, so these stable built-in ids map to the closest native
 * palette while all explicit candidate colours still win over the palette below.
 */
export class CandidateSkinPolicy {
  /** Auxiliary code and translations inherit the selected row's text colour, like the Windows CSS. */
  static rowDetailColor(highlighted: boolean, textColor: string, selectedTextColor: string): string {
    return highlighted ? selectedTextColor : textColor;
  }

  static harmonySkin(candidateSkin: string | null | undefined,
                     externalBase: string | null | undefined = null): string {
    switch (candidateSkin) {
      case 'fluent':
        return 'porcelain';
      case 'wechat':
        return 'forest';
      case 'graphite':
        return 'blueprint';
      case 'willow_green':
        return 'forest';
      default:
        if (externalBase !== null && externalBase !== undefined && externalBase !== candidateSkin) {
          return CandidateSkinPolicy.harmonySkin(externalBase, null);
        }
        return 'forest';
    }
  }

  static showSelectedBar(candidateSkin: string | null | undefined,
                         externalValue: boolean | null | undefined = null): boolean {
    if (externalValue !== null && externalValue !== undefined) {
      return externalValue;
    }
    return candidateSkin !== 'wechat' && candidateSkin !== 'graphite';
  }
}
