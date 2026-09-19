import { utf8Length } from '../Utf8';

/** The Engine joins dictionary senses with either the Chinese or ASCII semicolon. */
export class TranslationSensePolicy {
  static readonly MAX_SENSES: number = 9;
  static readonly MAX_SENSE_BYTES: number = 4096;

  static split(gloss: string | null | undefined): string[] {
    if (typeof gloss !== 'string' || gloss.trim().length === 0) return [];
    const result: string[] = [];
    for (const value of gloss.split(/[;；]/u)) {
      const sense: string = value.trim();
      if (sense.length === 0 || utf8Length(sense) > TranslationSensePolicy.MAX_SENSE_BYTES) continue;
      if (!result.includes(sense)) result.push(sense);
      if (result.length === TranslationSensePolicy.MAX_SENSES) break;
    }
    return result;
  }
}
