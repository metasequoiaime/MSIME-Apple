/**
 * Shared preference gate for the mode badge shown after a Chinese/English switch.
 *
 * The shared schema serialises `input_mode_hud` as a plain boolean that defaults to on, so absence
 * means a document written before the field existed rather than a user who turned the badge off.
 */
export class InputModeHudPolicy {
  /** Only an explicit no hides it; anything else keeps the shared default-on behaviour. */
  static enabled(value: unknown): boolean {
    return value !== false;
  }
}
