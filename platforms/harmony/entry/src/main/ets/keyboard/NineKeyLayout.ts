/**
 * Display labels and Engine inputs for the quanpin nine-key grid, ported from
 * platforms/android/java/app/msime/client/NineKeyLayout.java.
 *
 * The grid is data, not behaviour: which character each key sends is the Engine's contract, and the
 * labels are what the Apple hosts print for the same keys.
 */
export interface NineKey {
  readonly label: string;
  /** The ASCII character handed to the Engine, not the label. */
  readonly input: string;
  readonly description: string;
}

function key(label: string, input: string, description: string): NineKey {
  return { label: label, input: input, description: description };
}

const ROWS: NineKey[][] = [
  [key('分词', '\'', '拼音分词'), key('ABC', '2', '2 ABC'), key('DEF', '3', '3 DEF')],
  [key('GHI', '4', '4 GHI'), key('JKL', '5', '5 JKL'), key('MNO', '6', '6 MNO')],
  [key('PQRS', '7', '7 PQRS'), key('TUV', '8', '8 TUV'), key('WXYZ', '9', '9 WXYZ')]
];

const PUNCTUATION: string[] = ['，', '。', '？', '！'];

export class NineKeyLayout {
  static rows(): NineKey[][] {
    return ROWS;
  }

  static punctuation(): string[] {
    return PUNCTUATION;
  }
}
