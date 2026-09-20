/**
 * The keyboard chord that opens a shared panel.
 *
 * Windows binds `Ctrl+Shift+Win+K` to the on-screen keyboard — the surface that exists precisely
 * because a physical keyboard has no key for what the user wants to type. A 2in1 has the same
 * surface and the same problem, and could reach it only by finding the toolbar with a pointing
 * device: the one input the user is trying to avoid.
 *
 * It was left unbound because Windows receives this on a global maintenance hook, which a keyboard
 * extension has no equivalent of — the extension sees keys only while it is attached to an editor.
 * That turns out not to matter here. The panel inserts into the focused editor, so an editor is the
 * precondition for the panel being useful at all, not a restriction on when the chord may fire.
 *
 * `Super` is `logoKey` on HarmonyOS. Every modifier is required rather than merely present: a chord
 * that fires on a superset would swallow a key combination the editor was meant to receive, and
 * a shortcut that eats other shortcuts is worse than one that is missing.
 */

const KEYCODE_K: number = 2027;

export interface PanelShortcutKey {
  readonly keyCode: number;
  readonly down: boolean;
  readonly ctrlKey: boolean;
  readonly shiftKey: boolean;
  readonly altKey: boolean;
  readonly logoKey: boolean;
}

export enum PanelShortcut {
  NONE,
  /** The soft keyboard, for the characters a physical keyboard lacks. */
  SCREEN_KEYBOARD,
}

export class PanelShortcutPolicy {
  /**
   * Which panel a key asks for, if any.
   *
   * Decided on the press. The release of a chord that has already acted must not act again, and it
   * is still claimed by the caller so the bare `K` never reaches the editor.
   */
  static shortcut(key: PanelShortcutKey): PanelShortcut {
    if (key.keyCode !== KEYCODE_K) {
      return PanelShortcut.NONE;
    }
    if (!key.ctrlKey || !key.shiftKey || !key.logoKey || key.altKey) {
      return PanelShortcut.NONE;
    }
    return key.down ? PanelShortcut.SCREEN_KEYBOARD : PanelShortcut.NONE;
  }

  /**
   * Whether the key belongs to a panel chord at all, press or release.
   *
   * The release carries the same modifiers as the press, and letting it through would deliver a
   * stray `K` to the editor after the panel had already opened.
   */
  static claims(key: PanelShortcutKey): boolean {
    return key.keyCode === KEYCODE_K && key.ctrlKey && key.shiftKey && key.logoKey && !key.altKey;
  }
}
