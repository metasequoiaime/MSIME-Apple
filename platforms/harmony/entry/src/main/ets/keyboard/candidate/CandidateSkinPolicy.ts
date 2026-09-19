/**
 * Candidate skins are a separate shared preference from the touch-keyboard skins. Harmony does
 * not ship the Windows CSS skin renderer, so these stable built-in ids map to the closest native
 * palette while all explicit candidate colours still win over the palette below.
 */
export class CandidateSkinPolicy {
  static harmonySkin(candidateSkin: string | null | undefined): string {
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
        return 'forest';
    }
  }

  static showSelectedBar(candidateSkin: string | null | undefined): boolean {
    return candidateSkin !== 'wechat' && candidateSkin !== 'graphite';
  }
}
