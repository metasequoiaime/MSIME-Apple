/**
 * Availability of the Japanese post-kana variant key, ported from
 * platforms/android/java/app/msime/client/JapaneseVariantPolicy.java.
 */
export class JapaneseVariantPolicy {
  static enabled(japaneseNineKey: boolean, symbols: boolean, composing: boolean): boolean {
    return japaneseNineKey && !symbols && composing;
  }

  static accessibilityLabel(enabled: boolean): string {
    return enabled ? '小假名、浊音、半浊音' : '小假名、浊音、半浊音；请先输入假名';
  }
}
