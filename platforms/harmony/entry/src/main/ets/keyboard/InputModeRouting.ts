/**
 * When a key on a real keyboard means "switch mode", from the shared `keybindings` preferences.
 *
 * Four bindings, each of which the user can turn off. Three switch between Chinese and English and one, Ctrl+Shift+F, switches between simplified and traditional output, as the Windows host's `IsCharacterSetShortcut` does; which of them are live is the document's business, not this file's, so the settings page and the keyboard cannot disagree about what is bound.
 *
 * Three more come from the Windows baseline and are fixed there, so they are fixed here: Ctrl+Shift+E for the English candidate mode (`IsEnglishModeToggleKey`), Ctrl+Shift+Space for halfwidth/fullwidth and Ctrl+. for the punctuation set. Turning off the Shift tap says nothing about any of them.
 *
 * Two of them are a modifier pressed and released with nothing in between, which no single event can
 * decide: Shift+A begins exactly the same way as a solitary Shift. The press only arms it and the
 * release fires it, and any key or competing modifier arriving in between disarms it. A modifier
 * held longer than the interval below is being used for something else — selecting with the mouse,
 * holding a capital — and must not switch anyone's mode out from under them. Ported from the rule in
 * platforms/macos/src/InputModeRouting.h.
 *
 * Pure decision, no side effects, so it can be tested without a device.
 */

const KEYCODE_SPACE: number = 2050;
const KEYCODE_E: number = 2021;
const KEYCODE_F: number = 2022;
const KEYCODE_PERIOD: number = 2044;
const KEYCODE_SHIFT_LEFT: number = 2047;
const KEYCODE_SHIFT_RIGHT: number = 2048;
const KEYCODE_CTRL_LEFT: number = 2072;
const KEYCODE_CTRL_RIGHT: number = 2073;

/** A modifier held longer than this is doing something else. Milliseconds, as macOS spells 0.5s. */
const SOLITARY_INTERVAL_MS: number = 500;

/** The shared keybindings, as the preference document carries them. */
export interface ModeBindings {
  readonly switchLanguageShift: boolean;
  readonly switchLanguageCtrl: boolean;
  readonly switchLanguageCtrlAltSpace: boolean;
  readonly toggleCharacterSetCtrlShiftF: boolean;
}

export const DEFAULT_MODE_BINDINGS: ModeBindings = {
  switchLanguageShift: true,
  switchLanguageCtrl: false,
  switchLanguageCtrlAltSpace: true,
  toggleCharacterSetCtrlShiftF: true,
};

export interface ModeKey {
  readonly keyCode: number;
  readonly down: boolean;
  readonly shiftKey: boolean;
  readonly ctrlKey: boolean;
  readonly altKey: boolean;
  readonly logoKey: boolean;
  /** Milliseconds on any monotonic clock; only differences are used. */
  readonly timestamp: number;
}

export enum ModeGesture {
  NONE,
  /** Chinese becomes English and back. */
  SWITCH_LANGUAGE,
  /** Simplified output becomes traditional and back; the Windows Ctrl+Shift+F binding. */
  TOGGLE_CHARACTER_SET,
  /** Halfwidth ASCII becomes its fullwidth twin and back; the Windows Ctrl+Shift+Space binding. */
  TOGGLE_WIDTH,
  /** Chinese punctuation becomes ASCII and back; the Windows Ctrl+. binding. */
  TOGGLE_PUNCTUATION,
  /** Letters spell English words from the candidate list instead of Chinese, and back; the Windows Ctrl+Shift+E binding. */
  ENGLISH_CANDIDATES,
}

function isShift(keyCode: number): boolean {
  return keyCode === KEYCODE_SHIFT_LEFT || keyCode === KEYCODE_SHIFT_RIGHT;
}

function isCtrl(keyCode: number): boolean {
  return keyCode === KEYCODE_CTRL_LEFT || keyCode === KEYCODE_CTRL_RIGHT;
}

/**
 * The whole decision, including the half a single event cannot make.
 *
 * Feed it every key. It answers with the gesture that key completed, which for the solitary
 * modifiers is only ever the release.
 */
export class InputModeRouting {
  private bindings: ModeBindings = DEFAULT_MODE_BINDINGS;
  private armedShift: number = -1;
  private armedCtrl: number = -1;

  /** The document is authoritative and may be re-read at any time. */
  use(bindings: ModeBindings): void {
    this.bindings = bindings;
    this.disarm();
  }

  /** Focus changes and mode switches both end whatever gesture was in progress. */
  disarm(): void {
    this.armedShift = -1;
    this.armedCtrl = -1;
  }

  accept(key: ModeKey): ModeGesture {
    // The chords are decided on the press, before the solitary tracking sees the key, because a
    // chord's own modifier would otherwise look like the start of a tap.
    if (
      key.down &&
      this.bindings.switchLanguageCtrlAltSpace &&
      key.keyCode === KEYCODE_SPACE &&
      key.ctrlKey &&
      key.altKey &&
      !key.logoKey
    ) {
      this.disarm();
      return ModeGesture.SWITCH_LANGUAGE;
    }
    if (
      key.down &&
      this.bindings.toggleCharacterSetCtrlShiftF &&
      key.keyCode === KEYCODE_F &&
      key.ctrlKey &&
      key.shiftKey &&
      !key.altKey &&
      !key.logoKey
    ) {
      this.disarm();
      return ModeGesture.TOGGLE_CHARACTER_SET;
    }
    // Three chords from the Windows baseline, which the Linux host also answers. None of them is
    // one of the four the settings page can turn off: Windows binds them fixed, and a user who
    // turned Shift off has said nothing about Ctrl+Shift+E.
    if (
      key.down &&
      key.keyCode === KEYCODE_E &&
      key.ctrlKey &&
      key.shiftKey &&
      !key.altKey &&
      !key.logoKey
    ) {
      this.disarm();
      return ModeGesture.ENGLISH_CANDIDATES;
    }
    if (
      key.down &&
      key.keyCode === KEYCODE_SPACE &&
      key.ctrlKey &&
      key.shiftKey &&
      !key.altKey &&
      !key.logoKey
    ) {
      this.disarm();
      return ModeGesture.TOGGLE_WIDTH;
    }
    if (
      key.down &&
      key.keyCode === KEYCODE_PERIOD &&
      key.ctrlKey &&
      !key.shiftKey &&
      !key.altKey &&
      !key.logoKey
    ) {
      this.disarm();
      return ModeGesture.TOGGLE_PUNCTUATION;
    }
    if (isShift(key.keyCode)) {
      return this.solitary(key, true);
    }
    if (isCtrl(key.keyCode)) {
      return this.solitary(key, false);
    }
    // Any other key, down or up, means the modifiers being held are modifying it.
    this.disarm();
    return ModeGesture.NONE;
  }

  private solitary(key: ModeKey, shift: boolean): ModeGesture {
    const enabled: boolean = shift
      ? this.bindings.switchLanguageShift
      : this.bindings.switchLanguageCtrl;
    const armed: number = shift ? this.armedShift : this.armedCtrl;
    if (key.down) {
      // A second press while one is already down is not a tap of either, and the other modifier
      // arriving means whatever is being held is a chord rather than a tap.
      const rearmed: number = armed >= 0 ? -1 : key.timestamp;
      if (shift) {
        this.armedShift = rearmed;
        this.armedCtrl = -1;
      } else {
        this.armedCtrl = rearmed;
        this.armedShift = -1;
      }
      return ModeGesture.NONE;
    }
    if (shift) {
      this.armedShift = -1;
    } else {
      this.armedCtrl = -1;
    }
    return enabled && armed >= 0 && key.timestamp - armed <= SOLITARY_INTERVAL_MS
      ? ModeGesture.SWITCH_LANGUAGE
      : ModeGesture.NONE;
  }
}
