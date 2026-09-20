/**
 * Whether the settings window should open on the welcome flow instead of the settings page.
 *
 * A keyboard nobody has enabled is not a keyboard, and on HarmonyOS enabling one is two trips into
 * system screens the user has no reason to know about: turn the input method on, then pick it as
 * the current one. Android and iOS already walk people through exactly this with the shared welcome
 * flow; this host dropped them straight into a settings page for a keyboard that could not type.
 *
 * Two separate facts decide it, because they fail separately and the user fixes them in different
 * screens: the input method has to be enabled at all, and it has to be the one in use. Being
 * enabled but not current is the state someone lands in after doing half the setup, and it is worth
 * finishing the flow rather than showing settings that appear to have had no effect.
 */

/** What the framework reports, mirroring `inputMethod.EnabledState`. */
export enum ImeEnabledState {
  DISABLED = 0,
  BASIC_MODE = 1,
  FULL_EXPERIENCE_MODE = 2,
}

export interface OnboardingState {
  /** The framework's enablement answer, or null when it could not be asked. */
  readonly enabled: ImeEnabledState | null;
  /** The bundle currently serving input, or an empty string when it could not be read. */
  readonly currentBundle: string;
  /** This keyboard's own bundle. */
  readonly ownBundle: string;
}

export class OnboardingStatePolicy {
  /**
   * Whether setup still has a step left in it.
   *
   * An unanswerable query is not treated as "needs onboarding". Someone who has been typing with
   * this keyboard for a month should not be sent back to a welcome screen because one system call
   * failed; the settings page is the safe thing to show when the answer is unknown, since it is
   * reachable from the welcome flow but not the other way round.
   */
  static required(state: OnboardingState): boolean {
    if (state.enabled === null) {
      return false;
    }
    if (state.enabled === ImeEnabledState.DISABLED) {
      return true;
    }
    // Either name being unreadable makes the comparison meaningless, and an unreadable own name
    // would otherwise compare unequal to every keyboard including this one.
    if (state.currentBundle.length === 0 || state.ownBundle.length === 0) {
      return false;
    }
    return state.currentBundle !== state.ownBundle;
  }

  /**
   * Which step the flow is on, for the log line that says why the window opened where it did.
   *
   * Setup that goes wrong here goes wrong silently — a keyboard that is enabled but not selected
   * looks exactly like one that is not installed — so the reason is recorded rather than inferred
   * afterwards from which screen appeared.
   */
  static describe(state: OnboardingState): string {
    if (state.enabled === null) {
      return "setup state unknown, opening settings";
    }
    if (state.enabled === ImeEnabledState.DISABLED) {
      return "not enabled, opening welcome flow";
    }
    if (state.currentBundle.length === 0 || state.ownBundle.length === 0) {
      return "enabled, keyboard identity unknown, opening settings";
    }
    if (state.currentBundle !== state.ownBundle) {
      return "enabled but not current, opening welcome flow";
    }
    return "enabled and current, opening settings";
  }
}
