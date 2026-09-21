import { KeyboardGeometry } from '../KeyboardGeometry';

export enum KeyboardLayoutDragAxis {
  UNDECIDED = 0,
  KEY_SPACING = 1,
  ROW_SPACING = 2
}

/** Pure drag arithmetic for the transparent, live keyboard-layout adjustment surface. */
export class KeyboardLayoutDragPolicy {
  // Apple uses eighteen screen points for one spacing point. Harmony stores tenths, so the same
  // physical gesture advances ten stored units per eighteen density-independent pixels.
  static readonly SPACING_DRAG_SCALE_VP: number = 18;

  static axis(offsetX: number, offsetY: number): KeyboardLayoutDragAxis {
    return Math.abs(offsetY) >= Math.abs(offsetX)
      ? KeyboardLayoutDragAxis.ROW_SPACING : KeyboardLayoutDragAxis.KEY_SPACING;
  }

  static keySpacing(baseTenths: number, offsetX: number): number {
    return KeyboardGeometry.keySpacing(Math.round(baseTenths
      + offsetX * 10 / KeyboardLayoutDragPolicy.SPACING_DRAG_SCALE_VP));
  }

  static rowSpacing(baseTenths: number, offsetY: number): number {
    return KeyboardGeometry.rowSpacing(Math.round(baseTenths
      + offsetY * 10 / KeyboardLayoutDragPolicy.SPACING_DRAG_SCALE_VP));
  }

  /** Upward screen movement is negative and therefore makes the keyboard taller. */
  static height(baseVp: number, offsetY: number): number {
    return KeyboardGeometry.heightAdjustment(Math.round(baseVp - offsetY));
  }
}
