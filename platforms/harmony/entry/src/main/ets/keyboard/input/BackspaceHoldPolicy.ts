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

/**
 * A hardware Backspace held from inside a composition, which must stop at the composition's edge.
 *
 * The Windows host arms this on each fresh Backspace press that finds a composition, and claims every auto-repeat of that hold once the composition is gone (`_ApplyBackspaceHoldGuard`, `ShouldSuppressBackspaceRepeat`, issue #347). Without it, holding Backspace to clear a long preedit went on to delete the committed text before it. A HarmonyOS key event carries no repeat bit, so a repeat is a key-down with no key-up since the last one. Any other key-down ends the hold as well, because auto-repeat moves to the newest key and a key-up the system never delivered must not leave the guard armed.
 */
export class HardwareBackspaceGuard {
  private held: boolean = false;
  private armed: boolean = false;

  /** A Backspace key-down; true when it must be claimed even though nothing is left to delete. */
  down(composing: boolean): boolean {
    if (!this.held) {
      this.held = true;
      this.armed = composing;
      return false;
    }
    return this.armed && !composing;
  }

  /** The Backspace key-up; true when its hold was claimed, so the application does not see half a key. */
  up(composing: boolean): boolean {
    const claimed: boolean = this.held && this.armed && !composing;
    this.reset();
    return claimed;
  }

  reset(): void {
    this.held = false;
    this.armed = false;
  }
}
