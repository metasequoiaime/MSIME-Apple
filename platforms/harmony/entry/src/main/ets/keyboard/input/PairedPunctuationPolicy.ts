/** Host-side completion for punctuation pairs that the Engine opens one mark at a time. */
export interface PairedPunctuationCompletion {
  readonly opening: number;
  readonly openingMark: string;
  readonly closing: string;
}

const COMPLETIONS: PairedPunctuationCompletion[] = [
  { opening: 0x22, openingMark: '“', closing: '”' },
  { opening: 0x27, openingMark: '‘', closing: '’' },
  { opening: 0x28, openingMark: '（', closing: '）' },
  { opening: 0x3c, openingMark: '《', closing: '》' },
  { opening: 0x3c, openingMark: '〈', closing: '〉' },
  { opening: 0x5b, openingMark: '【', closing: '】' }
];

export class PairedPunctuationPolicy {
  /** Return a closing mark only when the Engine commit ends in a known opening mark. */
  static completion(commit: string | null | undefined,
                    enabled: boolean): PairedPunctuationCompletion | null {
    if (!enabled || typeof commit !== 'string' || commit.length === 0) return null;
    for (const completion of COMPLETIONS) {
      if (commit.endsWith(completion.openingMark)) return completion;
    }
    return null;
  }
}
