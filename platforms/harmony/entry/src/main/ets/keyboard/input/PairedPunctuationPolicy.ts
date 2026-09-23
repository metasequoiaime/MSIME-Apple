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
  /**
   * With pairing on, every quote press opens a fresh pair, as the reference's `KeyHandler.cpp` does. The Engine alternates the quote keys (“ then ”) because a host without pairing needs that, but a host that supplies the closing half itself never sends the press that would have produced it, so the next quote would otherwise arrive as a lone ”. A closing quote at the end of the commit is therefore rewritten to the opening one before the pair is completed; with pairing off the commit is left to the Engine's alternation.
   */
  static reopenQuote(commit: string | null | undefined, ascii: number,
                     enabled: boolean): string | null | undefined {
    if (!enabled || typeof commit !== 'string') return commit;
    if (ascii === 0x22 && commit.endsWith('”')) return commit.slice(0, -1) + '“';
    if (ascii === 0x27 && commit.endsWith('’')) return commit.slice(0, -1) + '‘';
    return commit;
  }

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
