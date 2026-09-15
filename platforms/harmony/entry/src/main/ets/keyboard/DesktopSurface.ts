/**
 * What the candidate window is showing, where there are no key faces to open a surface from.
 *
 * A phone reaches the emoji panel and the keyboard itself by tapping them; a 2in1 has only the
 * toolbar, so the same window carries whichever of them was asked for. One at a time, because there
 * is one window: asking for the open one closes it rather than stacking a second.
 */
export enum DesktopSurface {
  /** Candidates, which is what the window is for when nothing else was asked for. */
  NONE,
  EMOJI,
  /** The soft keyboard, on a machine that has its own — for the characters a physical one lacks. */
  SCREEN_KEYBOARD
}
