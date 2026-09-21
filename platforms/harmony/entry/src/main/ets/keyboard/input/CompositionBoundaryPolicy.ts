export enum CompositionBoundaryAction {
  NONE = 'none',
  COMMIT_RAW = 'commit-raw',
  FINISH_COMPOSITION = 'finish-composition'
}

/** How a mode or panel boundary preserves text already entered into the current scheme. */
export class CompositionBoundaryPolicy {
  static action(composing: boolean, japanese: boolean): CompositionBoundaryAction {
    if (!composing) {
      return CompositionBoundaryAction.NONE;
    }
    return japanese
      ? CompositionBoundaryAction.FINISH_COMPOSITION : CompositionBoundaryAction.COMMIT_RAW;
  }
}
