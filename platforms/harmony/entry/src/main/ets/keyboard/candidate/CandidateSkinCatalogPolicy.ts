/** The palette tokens an external candidate skin may contribute to the native Harmony card. */
export interface CandidateSkinPaletteTokens {
  readonly accent?: string | null;
  readonly selected?: string | null;
  readonly hover?: string | null;
  readonly surface?: string | null;
  readonly border?: string | null;
  readonly text?: string | null;
  readonly number?: string | null;
  readonly showSelectedBar?: boolean | null;
}

export interface CandidateSkinPackage {
  readonly id: string;
  readonly base: string;
  readonly layouts: string[];
  readonly themes: string[];
  readonly minWidthDip: number;
  readonly candidate: {
    readonly dark: CandidateSkinPaletteTokens;
    readonly light: CandidateSkinPaletteTokens;
  };
}

/**
 * Resolves the safe, non-CSS part of a shared skin catalog for the ArkUI presenter.
 *
 * The Rust catalog scanner already bounds package ids, dimensions and token lengths. This policy
 * still treats every value as optional because a package may intentionally inherit part of its
 * base skin, and because Harmony must keep working with a catalog produced by an older host.
 */
export class CandidateSkinCatalogPolicy {
  /**
   * Keep manifest values inside the small CSS colour subset accepted by the
   * native presenters. ArkUI receives these strings directly, so an arbitrary
   * token (for example a declaration or url()) must never cross this boundary.
   */
  static color(value: string | null | undefined): string | null {
    if (value === null || value === undefined) {
      return null;
    }
    const color: string = value.trim();
    if (color === 'transparent') {
      return color;
    }
    if (/^#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{2})?$/.test(color)) {
      return color;
    }
    const rgb: RegExpMatchArray | null = color.match(
      /^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(?:\s*,\s*(0|1|0?\.\d+))?\s*\)$/);
    if (rgb !== null && Number(rgb[1]) <= 255 && Number(rgb[2]) <= 255
        && Number(rgb[3]) <= 255) {
      return color;
    }
    return null;
  }

  private static sanitizePalette(palette: CandidateSkinPaletteTokens): CandidateSkinPaletteTokens {
    return {
      accent: CandidateSkinCatalogPolicy.color(palette.accent),
      selected: CandidateSkinCatalogPolicy.color(palette.selected),
      hover: CandidateSkinCatalogPolicy.color(palette.hover),
      surface: CandidateSkinCatalogPolicy.color(palette.surface),
      border: CandidateSkinCatalogPolicy.color(palette.border),
      text: CandidateSkinCatalogPolicy.color(palette.text),
      number: CandidateSkinCatalogPolicy.color(palette.number),
      showSelectedBar: palette.showSelectedBar ?? null
    };
  }

  static package(packages: CandidateSkinPackage[], id: string): CandidateSkinPackage | null {
    for (const candidate of packages) {
      if (candidate.id === id) {
        return candidate;
      }
    }
    return null;
  }

  static palette(packages: CandidateSkinPackage[], id: string,
                 dark: boolean): CandidateSkinPaletteTokens | null {
    const candidate: CandidateSkinPackage | null = CandidateSkinCatalogPolicy.package(packages, id);
    if (candidate === null) {
      return null;
    }
    return CandidateSkinCatalogPolicy.sanitizePalette(
      dark ? candidate.candidate.dark : candidate.candidate.light);
  }

  static supports(packages: CandidateSkinPackage[], id: string, layout: string,
                  theme: string): boolean {
    const candidate: CandidateSkinPackage | null = CandidateSkinCatalogPolicy.package(packages, id);
    return candidate !== null && candidate.layouts.includes(layout) && candidate.themes.includes(theme);
  }

  static base(packages: CandidateSkinPackage[], id: string): string | null {
    const candidate: CandidateSkinPackage | null = CandidateSkinCatalogPolicy.package(packages, id);
    return candidate === null || candidate.base.length === 0 ? null : candidate.base;
  }

  static minWidthVp(packages: CandidateSkinPackage[], id: string): number | null {
    const candidate: CandidateSkinPackage | null = CandidateSkinCatalogPolicy.package(packages, id);
    if (candidate === null || !Number.isFinite(candidate.minWidthDip)
        || candidate.minWidthDip <= 0) {
      return null;
    }
    return candidate.minWidthDip;
  }

  static showSelectedBar(packages: CandidateSkinPackage[], id: string,
                         dark: boolean): boolean | null {
    const palette: CandidateSkinPaletteTokens | null = CandidateSkinCatalogPolicy.palette(
      packages, id, dark);
    return palette === null ? null : palette.showSelectedBar ?? null;
  }
}
