/**
 * Lifecycle and presentation rules for optional offline candidate glosses, ported from
 * platforms/android/java/app/msime/client/CandidateGlossPolicy.java.
 *
 * A gloss arrives asynchronously, so the token says which session, generation and epoch asked for it.
 * Anything stale is dropped rather than painted onto whatever is on screen now.
 */
import { utf8Length } from '../Utf8';

const MAX_ENTRY_BYTES: number = 4096;

export interface GlossToken {
  readonly session: number;
  readonly generation: number;
  readonly epoch: number;
}

export class CandidateGlossPolicy {
  static token(session: number, generation: number, epoch: number): GlossToken {
    if (session <= 0 || generation < 0 || epoch < 0) {
      throw new Error('Invalid candidate gloss token');
    }
    return { session: session, generation: generation, epoch: epoch };
  }

  static isCurrent(token: GlossToken, currentSession: number, currentGeneration: number,
                   currentEpoch: number): boolean {
    return token.session === currentSession && token.generation === currentGeneration
      && token.epoch === currentEpoch;
  }

  /** Engine annotations, for example Wubi codes, occupy the shared hint slot first. */
  static annotation(engineAnnotation: string | null, translation: string | null,
                    glossEnabled: boolean): string {
    if (engineAnnotation !== null && engineAnnotation.length > 0) {
      return engineAnnotation;
    }
    return glossEnabled && CandidateGlossPolicy.bounded(translation) && translation !== null
      ? translation : '';
  }

  static accessibilitySuffix(engineAnnotation: string | null, translation: string | null,
                             glossEnabled: boolean): string {
    if (engineAnnotation !== null && engineAnnotation.length > 0) {
      return '，提示：' + engineAnnotation;
    }
    const gloss: string =
      CandidateGlossPolicy.annotation(engineAnnotation, translation, glossEnabled);
    return gloss.length === 0 ? '' : '，英文释义：' + gloss;
  }

  private static bounded(value: string | null): boolean {
    return value !== null && value.length > 0 && utf8Length(value) <= MAX_ENTRY_BYTES;
  }
}
