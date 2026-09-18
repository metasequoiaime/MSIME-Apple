export interface HandwritingPoint {
  x: number;
  y: number;
}

export interface HandwritingStroke {
  points: HandwritingPoint[];
}

/** Bounds shared by the keyboard canvas and the OCR snapshot. */
export const HANDWRITING_CANVAS_SIZE: number = 420;
export const HANDWRITING_MAX_STROKES: number = 16;
export const HANDWRITING_MAX_POINTS: number = 256;
export const HANDWRITING_MAX_CANDIDATES: number = 8;

export class HandwritingStrokePolicy {
  static point(x: number, y: number): HandwritingPoint {
    return {
      x: Math.min(HANDWRITING_CANVAS_SIZE, Math.max(0, Number.isFinite(x) ? x : 0)),
      y: Math.min(HANDWRITING_CANVAS_SIZE, Math.max(0, Number.isFinite(y) ? y : 0))
    };
  }

  static canRecognize(strokes: HandwritingStroke[]): boolean {
    return strokes.length > 0 && strokes.length <= HANDWRITING_MAX_STROKES
      && strokes.every((stroke: HandwritingStroke): boolean =>
        stroke.points.length > 0 && stroke.points.length <= HANDWRITING_MAX_POINTS);
  }

  static candidates(value: string, limit: number = HANDWRITING_MAX_CANDIDATES): string[] {
    const output: string[] = [];
    for (const character of Array.from(value.replace(/[\u0000-\u001f\u007f]/g, ''))) {
      if (/\s/u.test(character) || output.includes(character)) {
        continue;
      }
      output.push(character);
      if (output.length >= limit) {
        break;
      }
    }
    return output;
  }
}
