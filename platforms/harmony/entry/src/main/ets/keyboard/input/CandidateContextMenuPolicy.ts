/**
 * Which pointer gesture opens the candidate management menu.
 *
 * The menu itself already exists here; only one of the two ways into it did. A touch host opens it
 * with a long press, which is what this host implemented, and the source opens it with a right
 * click on the candidate window — it has no touch screen to long-press on. A 2in1 has both kinds of
 * pointer, so it needs both gestures: reaching a context menu by holding the left mouse button down
 * on a candidate is not a gesture anyone would guess at, and it is the only one that worked here.
 *
 * Not gated on the form factor. A mouse attached to a phone is still a mouse, and a right click
 * means the same thing wherever one arrives; the long press is left exactly as it was, so nothing a
 * touch user already knows stops working.
 *
 * The press opens it, not the release. Acting on both would open the menu and immediately act again
 * on the entry under the cursor.
 */

/** Mirrors `MouseButton` from the ArkUI enums, which is not importable into a plain .ts policy. */
export enum PointerButton {
  LEFT = 0,
  RIGHT = 1,
  MIDDLE = 2,
  BACK = 3,
  FORWARD = 4,
  NONE = 5,
}

/** Mirrors `MouseAction`. */
export enum PointerAction {
  PRESS = 0,
  RELEASE = 1,
  MOVE = 2,
  HOVER = 3,
}

export class CandidateContextMenuPolicy {
  /**
   * Whether this mouse event should open the management menu for the candidate under the cursor.
   *
   * Every other button is left alone rather than treated as "not the right button and therefore
   * harmless": the middle button pastes on some systems and the side buttons navigate, and a
   * candidate window that swallowed them would be taking away a gesture it never offered.
   */
  static opens(button: PointerButton, action: PointerAction): boolean {
    return button === PointerButton.RIGHT && action === PointerAction.PRESS;
  }
}
