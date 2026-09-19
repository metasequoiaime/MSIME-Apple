export type CandidateAnchor = [number, number, number];

/** Keeps a desktop candidate panel beside the first caret of a composition when requested. */
export class CandidateAnchorPolicy {
  static position(followCursor: boolean, anchor: CandidateAnchor | undefined,
                  current: CandidateAnchor): CandidateAnchor {
    if (!followCursor && anchor !== undefined) {
      return anchor;
    }
    return current;
  }
}
