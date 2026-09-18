/**
 * What to do with a key that came from a real keyboard.
 *
 * On a phone every keystroke is a tap on a key this app drew, so it arrives already decided. On a
 * 2in1 the keys belong to the machine and reach the input method as hardware events, which have to
 * be claimed one at a time: anything not claimed is delivered to the application as if no input
 * method were running.
 *
 * Claiming too much is the failure that matters. An input method that swallows every key makes
 * shortcuts, arrows and passwords stop working, so the rule here is to claim a key only when there
 * is a composition it belongs to, or when it is the letter that would start one.
 *
 * Pure decision, no side effects, so it can be tested without a device or a session.
 */

/** The subset of the multimodal key event this decision needs. */
export interface HardwareKey {
  readonly keyCode: number;
  /** Resolved by the system, so shift and caps lock are already applied. */
  readonly unicodeChar: number;
  readonly ctrlKey: boolean;
  readonly altKey: boolean;
  readonly logoKey: boolean;
  readonly shiftKey: boolean;
}

/** What the host should do with the key. Anything but Release is also a claim on the key. */
export enum HardwareKeyAction {
  /** Not ours: hand it to the application untouched. */
  RELEASE,
  /** A letter or digit for the Engine to spell with. */
  COMPOSE,
  /** Take back the last letter of the composition. */
  BACKSPACE,
  /** Throw the composition away. */
  CANCEL,
  /** Commit the highlighted candidate. */
  COMMIT,
  /** Commit the letters as typed, without choosing a candidate. */
  COMMIT_RAW,
  /** Choose the candidate at `index`. */
  SELECT
}

export interface HardwareKeyDecision {
  readonly action: HardwareKeyAction;
  /** The character to compose with, for COMPOSE. */
  readonly character: number;
  /** Which candidate to take, for SELECT. */
  readonly index: number;
}

const KEYCODE_SPACE: number = 2050;
const KEYCODE_ENTER: number = 2054;
const KEYCODE_DEL: number = 2055;
const KEYCODE_ESCAPE: number = 2070;
const KEYCODE_NUMPAD_ENTER: number = 2119;

const RELEASE: HardwareKeyDecision = {
  action: HardwareKeyAction.RELEASE, character: 0, index: 0
};

function decision(action: HardwareKeyAction, character: number = 0,
                  index: number = 0): HardwareKeyDecision {
  return { action: action, character: character, index: index };
}

export class HardwareKeyRouter {
  /**
   * @param composing whether the Engine is holding a composition right now
   * @param chinese whether the Engine would spell with a letter rather than pass it through
   */
  static route(key: HardwareKey, composing: boolean, chinese: boolean,
               releaseNumberRow: boolean = false): HardwareKeyDecision {
    // A modifier means the key is part of a shortcut, which belongs to the application even mid
    // composition. Shift is not one of those: it is how capitals and helpcodes are typed.
    if (key.ctrlKey || key.altKey || key.logoKey) {
      return RELEASE;
    }
    if (composing) {
      if (key.keyCode === KEYCODE_DEL) {
        return decision(HardwareKeyAction.BACKSPACE);
      }
      if (key.keyCode === KEYCODE_ESCAPE) {
        return decision(HardwareKeyAction.CANCEL);
      }
      if (key.keyCode === KEYCODE_SPACE) {
        return decision(HardwareKeyAction.COMMIT);
      }
      if (key.keyCode === KEYCODE_ENTER || key.keyCode === KEYCODE_NUMPAD_ENTER) {
        // Enter on an open composition means "these letters, as I typed them" — the same thing the
        // 重输-adjacent raw commit means on the touch keyboard. The editor's own return action is
        // what Enter does when nothing is being composed, and that is the untouched path below.
        return decision(HardwareKeyAction.COMMIT_RAW);
      }
      // 1 through 9 pick a candidate off the strip while something is being spelled, which is what
      // the number row is for on every desktop input method.
      if (key.unicodeChar >= 0x31 && key.unicodeChar <= 0x39) {
        if (releaseNumberRow) {
          return RELEASE;
        }
        return decision(HardwareKeyAction.SELECT, 0, key.unicodeChar - 0x31);
      }
    }
    // Only letters start a composition. A digit or a punctuation mark on an empty composition is
    // just that character, and the application can insert it without us in the way.
    const letter: boolean = (key.unicodeChar >= 0x61 && key.unicodeChar <= 0x7a)
      || (key.unicodeChar >= 0x41 && key.unicodeChar <= 0x5a);
    if (!letter) {
      return RELEASE;
    }
    // English mode spells nothing the application could not spell itself, so its letters are left
    // alone; the Engine is only worth interrupting for when it turns letters into something else.
    if (!composing && !chinese) {
      return RELEASE;
    }
    return decision(HardwareKeyAction.COMPOSE, key.unicodeChar);
  }
}
