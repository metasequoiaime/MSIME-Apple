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

/**
 * Which toolbar action a shortcut stands in for. Mirrors `ToolbarButton`, which lives in a file
 * this one must not import: the layout module reaches ArkUI types, and this policy is plain
 * TypeScript so it can be tested without a device.
 */
export enum PanelSurfaceAction {
  NONE = -1,
  SCREEN_KEYBOARD = 5,
}

export class PanelShortcutPolicy {
  /**
   * Which panel a key asks for, if any.
   *
   * Decided on the press. The release of a chord that has already acted must not act again, and it
   * is still claimed by the caller so the bare `K` never reaches the editor.
   */
  static shortcut(key: PanelShortcutKey, desktop: boolean = true): PanelShortcut {
    if (!desktop) {
      return PanelShortcut.NONE;
    }
    if (key.keyCode !== KEYCODE_K) {
      return PanelShortcut.NONE;
    }
    if (!key.ctrlKey || !key.shiftKey || !key.logoKey || key.altKey) {
      return PanelShortcut.NONE;
    }
    return key.down ? PanelShortcut.SCREEN_KEYBOARD : PanelShortcut.NONE;
  }

  /**
   * The toolbar action a shortcut asks for.
   *
   * A shortcut and a toolbar button that open the same surface must go through the same entry, or
   * they do different things. They did: the chord called the host's window helper directly, which
   * shows and sizes a panel but never tells the view which surface is open, so the keyboard was
   * never drawn and the window was sized around the candidate strip that was still there. On a 2in1
   * that is the whole feature — a thin empty bar where a keyboard was asked for.
   *
   * Naming the action here rather than at the call site is what makes that testable: the mapping is
   * a value, and a test can hold it against the button the toolbar uses.
   */
  static action(shortcut: PanelShortcut): PanelSurfaceAction {
    return shortcut === PanelShortcut.SCREEN_KEYBOARD
      ? PanelSurfaceAction.SCREEN_KEYBOARD
      : PanelSurfaceAction.NONE;
  }

  /**
   * Whether the key belongs to a panel chord at all, press or release.
   *
   * The release carries the same modifiers as the press, and letting it through would deliver a
   * stray `K` to the editor after the panel had already opened.
   */
  static claims(key: PanelShortcutKey, desktop: boolean = true): boolean {
    if (!desktop) {
      return false;
    }
    return key.keyCode === KEYCODE_K && key.ctrlKey && key.shiftKey && key.logoKey && !key.altKey;
  }
}
