import { DesktopSurface } from './DesktopSurface';

/** The native face that a voice shortcut opens on each Harmony form factor. */
export class SurfaceRoutingPolicy {
  static voiceSurface(desktop: boolean): DesktopSurface | null {
    return desktop ? DesktopSurface.VOICE : null;
  }
}
