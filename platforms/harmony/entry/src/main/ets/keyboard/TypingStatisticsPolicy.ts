/** Source labels shared by the native aggregate typing-statistics store. */
export class TypingStatisticsPolicy {
  static source(scheme: string, profile: string, english: boolean, nineKey: boolean,
                localMode: string): string {
    if (localMode === 'temporary_japanese') return 'japanese';
    if (localMode !== 'none' && localMode.length > 0) return 'local';
    if (english) return 'english';
    if (scheme === 'quanpin') return nineKey ? 'nineKey' : 'quanpin';
    if (scheme === 'wubi') return 'wubi';
    if (scheme === 'japanese') return 'japanese';
    if (scheme === 'shuangpin') {
      if (profile === 'ziranma') return 'ziranma';
      if (profile === 'microsoft') return 'microsoft';
      if (profile === 'shoudao') return 'shoudao';
      return 'shuangpin';
    }
    return 'unknown';
  }

  static day(date: Date): string {
    return `${String(date.getFullYear()).padStart(4, '0')}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }
}
