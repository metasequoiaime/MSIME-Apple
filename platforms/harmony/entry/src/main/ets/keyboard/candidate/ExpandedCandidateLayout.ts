/** Width shared by expanded-candidate row allocation and the actual ArkUI cell. */
export class ExpandedCandidateLayout {
  static width(text: string, index: number, fontSize: number, horizontalPadding: number,
               availableWidth: number): number {
    const font: number = Number.isFinite(fontSize) ? Math.max(1, fontSize) : 1;
    const padding: number = Number.isFinite(horizontalPadding)
      ? Math.max(0, horizontalPadding) : 0;
    const number: string = `${Math.max(0, Math.floor(index)) + 1}`;
    const numberFont: number = Math.max(10, font - 8);
    const natural: number = Array.from(text).length * font
      + Array.from(number).length * numberFont + 4 + padding * 2;
    if (!Number.isFinite(availableWidth) || availableWidth <= 0) {
      return Math.ceil(natural);
    }
    return Math.ceil(Math.min(natural, availableWidth));
  }
}
