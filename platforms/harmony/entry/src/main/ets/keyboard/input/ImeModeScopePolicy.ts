/**
 * Whether the Chinese/English state is remembered per application or shared by all of them.
 *
 * Ported from the rule the macOS host follows in `AppearancePreferences.mm`: the scope is read when
 * an editor is activated and never mid-composition, an application nobody has typed in yet starts at
 * `default_ime_mode`, and the remembered value is only what the user chose. An editor that demands
 * Latin — a password field, an address field — is not a choice and is not recorded, or one password
 * box would leave every later visit to that application in English.
 *
 * The map lives for as long as the keyboard process does and is never written to disk. It would be a
 * record of which applications the user types in, which is not something a preference file needs to
 * carry, and the cost of forgetting it is one keypress after the keyboard restarts.
 */
const MAX_APPLICATIONS: number = 64;
const MAX_IDENTIFIER_LENGTH: number = 256;

export class ImeModeScopePolicy {
  private modes: Map<string, boolean> = new Map<string, boolean>();
  private global: boolean | undefined = undefined;
  private active: string | null = null;
  private sharing: boolean = false;

  /**
   * Begin typing in an editor.
   *
   * The scope is captured here rather than read on each keypress, so changing the setting takes
   * effect at the next editor instead of halfway through a word.
   */
  activate(identifier: string | null, scope: string | null): void {
    this.active = ImeModeScopePolicy.identity(identifier);
    this.sharing = scope === 'global';
  }

  /** Nothing is being typed into; the next activation decides again. */
  deactivate(): void {
    this.active = null;
  }

  /** The mode this editor should open in, or the shared default where nothing is remembered. */
  mode(defaultEnglish: boolean): boolean {
    if (this.active === null) {
      return defaultEnglish;
    }
    const remembered: boolean | undefined =
      this.sharing ? this.global : this.modes.get(this.active);
    return remembered === undefined ? defaultEnglish : remembered;
  }

  /** Record a mode the user asked for. Editor-driven Latin must not come through here. */
  remember(english: boolean): void {
    if (this.active === null) {
      return;
    }
    if (this.sharing) {
      this.global = english;
      return;
    }
    // Re-inserting moves the key to the end, which is what makes the eviction below drop the
    // application that has gone longest without being typed in rather than an arbitrary one.
    this.modes.delete(this.active);
    this.modes.set(this.active, english);
    while (this.modes.size > MAX_APPLICATIONS) {
      const oldest: string | undefined = this.modes.keys().next().value;
      if (oldest === undefined) {
        return;
      }
      this.modes.delete(oldest);
    }
  }

  /** How many applications are remembered, for the regression that checks the bound holds. */
  size(): number {
    return this.modes.size;
  }

  /**
   * An editor with no bundle name has no identity to remember a mode against, and neither has one
   * whose name is implausible enough to be a defect rather than an application.
   */
  private static identity(identifier: string | null): string | null {
    if (identifier === null) {
      return null;
    }
    const trimmed: string = identifier.trim();
    return trimmed.length === 0 || trimmed.length > MAX_IDENTIFIER_LENGTH ? null : trimmed;
  }
}
