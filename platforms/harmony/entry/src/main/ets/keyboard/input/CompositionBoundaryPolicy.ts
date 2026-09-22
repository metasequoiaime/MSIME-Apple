export enum CompositionBoundaryAction {
  NONE = "none",
  COMMIT_RAW = "commit-raw",
  FINISH_COMPOSITION = "finish-composition",
}

export enum CompositionBoundary {
  MODE_SWITCH = "mode-switch",
  DEACTIVATE = "deactivate",
}

/** How a mode or panel boundary preserves text already entered into the current scheme. */
export class CompositionBoundaryPolicy {
  static action(
    composing: boolean,
    japanese: boolean,
    boundary: CompositionBoundary,
  ): CompositionBoundaryAction {
    if (!composing) {
      return CompositionBoundaryAction.NONE;
    }
    if (boundary === CompositionBoundary.DEACTIVATE || japanese) {
      return CompositionBoundaryAction.FINISH_COMPOSITION;
    }
    return CompositionBoundaryAction.COMMIT_RAW;
  }
}
