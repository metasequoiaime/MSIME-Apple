import { DesktopSurface } from "./DesktopSurface";

/** The native face that a voice shortcut opens on each Harmony form factor. */
export class SurfaceRoutingPolicy {
  static voiceSurface(desktop: boolean): DesktopSurface | null {
    return desktop ? DesktopSurface.VOICE : null;
  }

  /**
   * Whether the candidate strip carries handwriting results rather than the Engine's candidates.
   *
   * A phone draws the pad when the scheme's touch layout is handwriting. A 2in1 draws it in two cases: the toolbar's pad, whatever the scheme, and the screen keyboard of a handwriting scheme. Anywhere else the strip belongs to the physical keys, and results left from a pad that has closed must not sit on it.
   */
  static showsHandwritingCandidates(
    desktop: boolean,
    surface: DesktopSurface,
    handwritingScheme: boolean,
  ): boolean {
    if (!desktop) {
      return handwritingScheme;
    }
    return (
      surface === DesktopSurface.HANDWRITING ||
      (surface === DesktopSurface.SCREEN_KEYBOARD && handwritingScheme)
    );
  }

  /** Closing the voice face, by any route, ends the recording it was showing; nothing else would stop it. */
  static endsVoice(previous: DesktopSurface, next: DesktopSurface): boolean {
    return previous === DesktopSurface.VOICE && next !== DesktopSurface.VOICE;
  }

  /** Closing the pad drops its ink: the next time it opens is for another character. */
  static endsHandwriting(previous: DesktopSurface, next: DesktopSurface): boolean {
    return previous === DesktopSurface.HANDWRITING && next !== DesktopSurface.HANDWRITING;
  }
}
