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
  SELECT,
  /** Consume a disabled navigation binding without turning it into text. */
  IGNORED,
  NEXT_PAGE,
  PREVIOUS_PAGE,
  NEXT_CANDIDATE,
  PREVIOUS_CANDIDATE
}

export interface HardwareKeyDecision {
  readonly action: HardwareKeyAction;
  /** The character to compose with, for COMPOSE. */
  readonly character: number;
  /** Which candidate to take, for SELECT. */
  readonly index: number;
}

/** The shared Windows-compatible candidate navigation bindings. */
export interface HardwareNavigationPreferences {
  readonly minusEqual: boolean;
  readonly commaPeriod: boolean;
  readonly brackets: boolean;
  readonly tab: boolean;
  readonly pageUpDown: boolean;
  readonly arrows: boolean;
}

const KEYCODE_SPACE: number = 2050;
const KEYCODE_ENTER: number = 2054;
const KEYCODE_DEL: number = 2055;
const KEYCODE_ESCAPE: number = 2070;
const KEYCODE_NUMPAD_ENTER: number = 2119;
const KEYCODE_DPAD_UP: number = 2012;
const KEYCODE_DPAD_DOWN: number = 2013;
const KEYCODE_TAB: number = 2049;
const KEYCODE_COMMA: number = 2043;
const KEYCODE_PERIOD: number = 2044;
const KEYCODE_MINUS: number = 2057;
const KEYCODE_EQUALS: number = 2058;
const KEYCODE_LEFT_BRACKET: number = 2059;
const KEYCODE_RIGHT_BRACKET: number = 2060;
const KEYCODE_PAGE_UP: number = 2068;
const KEYCODE_PAGE_DOWN: number = 2069;

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
               releaseNumberRow: boolean = false,
               navigation: HardwareNavigationPreferences = {
                 minusEqual: true, commaPeriod: true, brackets: false,
                 tab: true, pageUpDown: true, arrows: true
               }): HardwareKeyDecision {
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
      const navigationDecision: HardwareKeyDecision | undefined =
        HardwareKeyRouter.navigation(key, navigation);
      if (navigationDecision !== undefined) {
        return navigationDecision;
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

  private static navigation(key: HardwareKey,
                            preferences: HardwareNavigationPreferences): HardwareKeyDecision | undefined {
    let previous: boolean = false;
    let enabled: boolean;
    if (key.keyCode === KEYCODE_DPAD_UP || key.keyCode === KEYCODE_DPAD_DOWN) {
      if (preferences.arrows) {
        return decision(key.keyCode === KEYCODE_DPAD_UP
          ? HardwareKeyAction.PREVIOUS_CANDIDATE : HardwareKeyAction.NEXT_CANDIDATE);
      }
      enabled = false;
    } else if (key.keyCode === KEYCODE_PAGE_UP || key.keyCode === KEYCODE_PAGE_DOWN) {
      previous = key.keyCode === KEYCODE_PAGE_UP;
      enabled = preferences.pageUpDown;
    } else if (key.keyCode === KEYCODE_TAB) {
      previous = key.shiftKey;
      enabled = preferences.tab;
    } else if (key.keyCode === KEYCODE_MINUS || key.keyCode === KEYCODE_EQUALS) {
      previous = key.keyCode === KEYCODE_MINUS;
      enabled = preferences.minusEqual;
    } else if (key.keyCode === KEYCODE_COMMA || key.keyCode === KEYCODE_PERIOD) {
      previous = key.keyCode === KEYCODE_COMMA;
      enabled = preferences.commaPeriod;
    } else if (key.keyCode === KEYCODE_LEFT_BRACKET || key.keyCode === KEYCODE_RIGHT_BRACKET) {
      previous = key.keyCode === KEYCODE_LEFT_BRACKET;
      enabled = preferences.brackets;
    } else {
      return undefined;
    }
    return decision(enabled ? (previous ? HardwareKeyAction.PREVIOUS_PAGE
      : HardwareKeyAction.NEXT_PAGE) : HardwareKeyAction.IGNORED);
  }
}
