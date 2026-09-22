export enum BackspaceHoldAction {
  DELETE = "delete",
  CANCEL_COMPOSITION = "cancel-composition",
}

/** The first repeat of a held Delete must not cross from preedit into committed editor text. */
export class BackspaceHoldPolicy {
  static firstRepeat(composing: boolean): BackspaceHoldAction {
    return composing ? BackspaceHoldAction.CANCEL_COMPOSITION : BackspaceHoldAction.DELETE;
  }

  /** An unhandled Engine backspace belongs to the editor under the input method. */
  static deletesEditor(engineHandled: boolean): boolean {
    return !engineHandled;
  }
}
