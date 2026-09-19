/**
 * The Windows voice shortcuts, on a machine that has the keys for them.
 *
 * Windows binds five: a right Alt held to record, two more hold chords, Space to lock a recording
 * so releasing the hold key no longer ends it, Ctrl+F9 to start and stop — including ending a locked
 * one — and Escape to throw the recording away. The Linux host answers the same set from the same
 * `voice_input.hotkey_*` preferences. This host showed all five switches in its settings page and
 * honoured none of them.
 *
 * Hold is the part a single event cannot decide, so the press and the release are two answers: the
 * press starts recording and the release ends it, unless Space locked it in between. Every decision
 * also depends on whether anything is being recorded right now, which the caller knows and this does
 * not, so it is passed in rather than tracked here.
 *
 * Claiming too much is the failure that matters. Space and Escape mean something else entirely when
 * nothing is recording — selecting a candidate, abandoning a composition — so neither is claimed
 * then, and the caller is told so.
 */

/** The subset of a hardware key event this decision needs. */
export interface VoiceKey {
  readonly keyCode: number;
  readonly down: boolean;
  readonly ctrlKey: boolean;
  readonly altKey: boolean;
  readonly shiftKey: boolean;
  readonly logoKey: boolean;
}

/** The five shared switches, as `voice_input` carries them. */
export interface VoiceHotkeyBindings {
  readonly ralt: boolean;
  readonly ctrlWin: boolean;
  readonly rctrlRalt: boolean;
  readonly holdSpaceLock: boolean;
  readonly ctrlF9: boolean;
}

export const DEFAULT_VOICE_HOTKEY_BINDINGS: VoiceHotkeyBindings = {
  ralt: true, ctrlWin: false, rctrlRalt: false, holdSpaceLock: true, ctrlF9: true
};

export enum VoiceHotkeyAction {
  /** Not ours; the key belongs to whoever would have had it. */
  NONE,
  /** Begin recording. */
  START,
  /** End recording and recognize what was said. */
  STOP,
  /** Keep recording after the hold key is released. */
  LOCK,
  /** Throw the recording away without recognizing it. */
  CANCEL
}

const KEYCODE_ALT_RIGHT: number = 2046;
const KEYCODE_SPACE: number = 2050;
const KEYCODE_ESCAPE: number = 2070;
const KEYCODE_CTRL_RIGHT: number = 2073;
const KEYCODE_META_LEFT: number = 2076;
const KEYCODE_META_RIGHT: number = 2077;
const KEYCODE_F9: number = 2098;

export class VoiceHotkeyPolicy {
  private bindings: VoiceHotkeyBindings = DEFAULT_VOICE_HOTKEY_BINDINGS;
  /** Which key is being held to record, or 0. Also what the matching release has to be. */
  private holdKey: number = 0;
  private locked: boolean = false;

  /** The document is authoritative and may be re-read at any time. */
  use(bindings: VoiceHotkeyBindings): void {
    this.bindings = bindings;
    this.reset();
  }

  /** Focus changes and a finished recording both end whatever was in progress. */
  reset(): void {
    this.holdKey = 0;
    this.locked = false;
  }

  /** Whether the current recording will outlive the hold key, for the panel that says so. */
  isLocked(): boolean {
    return this.locked;
  }

  accept(key: VoiceKey, recording: boolean): VoiceHotkeyAction {
    if (key.down && this.bindings.ctrlF9 && key.keyCode === KEYCODE_F9
        && key.ctrlKey && !key.altKey && !key.shiftKey && !key.logoKey) {
      // The one binding that ends a locked recording, which is the whole reason it is a toggle.
      if (recording) {
        this.reset();
        return VoiceHotkeyAction.STOP;
      }
      return VoiceHotkeyAction.START;
    }
    if (recording && key.down && key.keyCode === KEYCODE_ESCAPE) {
      this.reset();
      return VoiceHotkeyAction.CANCEL;
    }
    if (recording && key.down && this.bindings.holdSpaceLock && key.keyCode === KEYCODE_SPACE
        && this.holdKey !== 0 && !this.locked) {
      this.locked = true;
      return VoiceHotkeyAction.LOCK;
    }
    const hold: number = this.holdBinding(key);
    if (hold !== 0 && key.down) {
      // A repeat of the key already held is the keyboard repeating, not a second request.
      if (this.holdKey !== 0) {
        return VoiceHotkeyAction.NONE;
      }
      if (recording) {
        return VoiceHotkeyAction.NONE;
      }
      this.holdKey = hold;
      this.locked = false;
      return VoiceHotkeyAction.START;
    }
    if (!key.down && this.holdKey !== 0 && key.keyCode === this.holdKey) {
      this.holdKey = 0;
      if (this.locked) {
        // Space said to keep going; the release is consumed so it does not reach the editor, but
        // the recording stands until Ctrl+F9 or Escape ends it.
        return VoiceHotkeyAction.NONE;
      }
      return recording ? VoiceHotkeyAction.STOP : VoiceHotkeyAction.NONE;
    }
    return VoiceHotkeyAction.NONE;
  }

  /**
   * Which hold binding this press is, or 0.
   *
   * The chords are tested before the bare key, because right Alt with Control held is the
   * RCtrl+RAlt binding rather than the RAlt one and would otherwise match whichever came first.
   */
  private holdBinding(key: VoiceKey): number {
    if (key.shiftKey) {
      return 0;
    }
    if (this.bindings.rctrlRalt && key.keyCode === KEYCODE_ALT_RIGHT
        && key.ctrlKey && !key.logoKey) {
      return KEYCODE_ALT_RIGHT;
    }
    if (this.bindings.ctrlWin
        && (key.keyCode === KEYCODE_META_LEFT || key.keyCode === KEYCODE_META_RIGHT)
        && key.ctrlKey && !key.altKey) {
      return key.keyCode;
    }
    if (this.bindings.ralt && key.keyCode === KEYCODE_ALT_RIGHT
        && !key.ctrlKey && !key.logoKey) {
      return KEYCODE_ALT_RIGHT;
    }
    // A right Control held for the RCtrl+RAlt chord is not itself a binding; the Alt completes it.
    if (key.keyCode === KEYCODE_CTRL_RIGHT) {
      return 0;
    }
    return 0;
  }
}
