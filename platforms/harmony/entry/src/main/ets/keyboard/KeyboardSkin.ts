/**
 * Rendering values for the touch-keyboard skin preference, ported from
 * platforms/android/java/app/msime/client/KeyboardSkin.java.
 *
 * Eight built-in skins plus the user's custom design. Every colour is derived here rather than in the
 * drawing code, so the same values reach the keyboard, the preview and the settings card.
 */
import { CustomKeyboardSkin } from './CustomKeyboardSkin';

function clampChannel(value: number): number {
  return Math.round(Math.max(0, Math.min(1, value)) * 255);
}

/** Matches the Java String.format("#%02X%02X%02X", ...) exactly, including the upper case. */
function rgb(red: number, green: number, blue: number): string {
  return '#' + [clampChannel(red), clampChannel(green), clampChannel(blue)]
    .map((channel: number) => channel.toString(16).toUpperCase().padStart(2, '0')).join('');
}

/** Produces #AARRGGBB: the alpha byte is prefixed to an existing #RRGGBB. */
function alpha(colour: string, value: number): string {
  return '#' + clampChannel(value).toString(16).toUpperCase().padStart(2, '0') + colour.substring(1);
}

function adaptive(dark: boolean, light: string, darkValue: string): string {
  return dark ? darkValue : light;
}

function label(dark: boolean): string {
  return dark ? '#FFFFFF' : '#000000';
}

export class KeyboardSkin {
  readonly id: string;
  readonly title: string;
  readonly description: string;
  readonly dark: boolean;
  readonly background: string;
  readonly keyBackground: string;
  readonly keyForeground: string;
  readonly accent: string;
  readonly actionBackground: string;
  readonly actionForeground: string;
  readonly cornerRadius: number;
  readonly borderWidth: number;
  readonly borderColor: string;
  readonly shadowOpacity: number;
  readonly shadowRadius: number;
  readonly shadowOffset: number;
  readonly monospaced: boolean;
  readonly pattern: number;
  readonly keyShape: string;
  readonly keyMaterial: string;
  readonly keyOpacity: number;
  readonly gradientEnd: string | null;
  readonly gradientHorizontal: boolean;
  readonly patternOpacity: number;
  readonly photo: Uint8Array | null;
  readonly photoShade: number;
  readonly photoPosition: number;
  private readonly designKey: string;

  /**
   * A built-in skin passes design as null and takes the flat defaults; the custom skin passes the
   * user's design and takes everything from it. One constructor rather than two so no field can be
   * set on one path and forgotten on the other.
   */
  private constructor(id: string, title: string, description: string, dark: boolean,
      background: string, keyBackground: string, keyForeground: string, accent: string,
      actionBackground: string, cornerRadius: number, borderWidth: number, shadowOpacity: number,
      shadowRadius: number, shadowOffset: number, monospaced: boolean, pattern: number,
      design: CustomKeyboardSkin | null = null) {
    this.id = id;
    this.title = title;
    this.description = description;
    this.dark = dark;
    this.background = background;
    this.keyBackground = keyBackground;
    this.keyForeground = keyForeground;
    this.accent = accent;
    this.actionBackground = actionBackground;
    this.cornerRadius = cornerRadius;
    this.borderWidth = borderWidth;
    this.shadowOpacity = shadowOpacity;
    this.shadowRadius = shadowRadius;
    this.shadowOffset = shadowOffset;
    this.monospaced = monospaced;
    this.pattern = pattern;
    if (design === null) {
      this.actionForeground = '#FFFFFF';
      // Midnight carries a neon edge, so its border is far less transparent than the others.
      this.borderColor = alpha(accent, id === 'midnight' ? 0.65 : 0.28);
      this.keyShape = 'rounded';
      this.keyMaterial = 'flat';
      this.keyOpacity = 1;
      this.gradientEnd = null;
      this.gradientHorizontal = false;
      this.patternOpacity = 0.15;
      this.photo = null;
      this.photoShade = 0.25;
      this.photoPosition = 0.5;
      this.designKey = '';
    } else {
      this.actionForeground = design.actionForeground();
      this.borderColor = design.borderColor();
      this.keyShape = design.keyShape();
      this.keyMaterial = design.keyMaterial();
      this.keyOpacity = design.keyOpacity();
      this.gradientEnd = design.gradientEnd();
      this.gradientHorizontal = design.gradientHorizontal();
      this.patternOpacity = design.patternOpacity();
      this.photo = design.photo();
      this.photoShade = design.photoShade();
      this.photoPosition = design.photoPosition();
      this.designKey = design.key();
    }
  }

  private static fromDesign(design: CustomKeyboardSkin, dark: boolean): KeyboardSkin {
    return new KeyboardSkin('custom', '我的皮肤', '自由配色 · 自定义键帽', dark,
      design.background(), design.keyBackground(), design.keyForeground(), design.accent(),
      design.actionBackground(), design.cornerRadius(), design.borderWidth(), design.shadow(),
      2, 1, design.monospaced(), design.pattern(), design);
  }

  /** Keyboard theme wins, then the global theme, then whatever the system is doing. */
  static resolveDark(keyboardTheme: string, globalTheme: string, systemDark: boolean): boolean {
    if (keyboardTheme === 'dark') {
      return true;
    }
    if (keyboardTheme === 'light') {
      return false;
    }
    if (globalTheme === 'dark') {
      return true;
    }
    if (globalTheme === 'light') {
      return false;
    }
    return systemDark;
  }

  static from(value: string | null, dark: boolean = false,
              design: CustomKeyboardSkin | null = null): KeyboardSkin {
    const id: string = value === null ? '' : value;
    switch (id) {
      case 'custom':
        return KeyboardSkin.fromDesign(design === null ? CustomKeyboardSkin.defaults() : design, dark);
      case 'ocean':
        return new KeyboardSkin(id, '海盐蓝', '海盐浅蓝 · 轻盈平面', dark,
          adaptive(dark, rgb(.90, .94, .98), rgb(.09, .12, .17)),
          adaptive(dark, '#FFFFFF', rgb(.18, .22, .29)),
          label(dark), adaptive(dark, rgb(.12, .36, .64), rgb(.50, .74, .98)),
          adaptive(dark, rgb(.12, .36, .64), rgb(.16, .36, .62)), 8, 0, 0, 3, 2, false, 0);
      case 'rose':
        return new KeyboardSkin(id, '浅蔷薇', '柔和蔷薇 · 简洁圆角', dark,
          adaptive(dark, rgb(.98, .91, .94), rgb(.16, .10, .13)),
          adaptive(dark, '#FFFFFF', rgb(.27, .19, .23)),
          label(dark), adaptive(dark, rgb(.63, .25, .39), rgb(.96, .62, .74)),
          adaptive(dark, rgb(.63, .25, .39), rgb(.56, .23, .36)), 8, 0, 0, 3, 2, false, 0);
      case 'porcelain':
        return new KeyboardSkin(id, '素白瓷', '细线边框 · 克制直角', dark,
          adaptive(dark, rgb(.92, .93, .94), rgb(.10, .11, .13)),
          adaptive(dark, rgb(.99, .99, .99), rgb(.20, .21, .23)),
          label(dark), adaptive(dark, rgb(.20, .24, .28), rgb(.80, .84, .89)),
          adaptive(dark, rgb(.20, .24, .28), rgb(.27, .31, .36)), 3, .5, 0, 3, 2, false, 0);
      case 'typewriter':
        return new KeyboardSkin(id, '纸上时光', '暖纸网点 · 复古键帽', dark,
          adaptive(dark, rgb(.89, .84, .74), rgb(.15, .13, .10)),
          adaptive(dark, rgb(.99, .96, .88), rgb(.25, .22, .17)),
          label(dark), adaptive(dark, rgb(.37, .25, .15), rgb(.87, .72, .51)),
          adaptive(dark, rgb(.37, .25, .15), rgb(.40, .28, .18)), 5, 1, .30, 0, 3, true, 1);
      case 'candy':
        return new KeyboardSkin(id, '奶油桃桃', '奶油波纹 · 饱满圆角', dark,
          adaptive(dark, rgb(.99, .88, .82), rgb(.19, .12, .15)),
          adaptive(dark, rgb(1, .97, .93), rgb(.30, .20, .24)),
          label(dark), adaptive(dark, rgb(.58, .22, .32), rgb(1, .66, .73)),
          adaptive(dark, rgb(.58, .22, .32), rgb(.58, .22, .32)), 18, 0, .16, 3, 2, false, 3);
      case 'midnight':
        return new KeyboardSkin(id, '霓虹夜航', '紫色星点 · 霓虹描边', dark,
          rgb(.075, .06, .14), rgb(.16, .12, .25), '#FFFFFF', rgb(.78, .69, 1),
          rgb(.40, .23, .70), 10, 1, 0, 3, 2, false, 1);
      case 'blueprint':
        return new KeyboardSkin(id, '工程蓝图', '蓝图网格 · 等宽字形', dark,
          rgb(.055, .13, .22), rgb(.09, .20, .32), '#FFFFFF', rgb(.54, .84, 1),
          rgb(.12, .34, .54), 3, 1, 0, 3, 2, true, 2);
      default:
        return new KeyboardSkin('forest', '水杉绿', '清新留白 · 经典圆角', dark,
          adaptive(dark, rgb(.91, .94, .92), rgb(.09, .13, .11)),
          adaptive(dark, '#FFFFFF', rgb(.19, .24, .21)),
          label(dark), adaptive(dark, rgb(.094, .36, .28), rgb(.45, .80, .65)),
          adaptive(dark, rgb(.094, .36, .28), rgb(.12, .38, .29)), 8, 0, 0, 3, 2, false, 0);
    }
  }

  static readonly BUILT_IN_IDS: string[] = [
    'forest', 'ocean', 'rose', 'porcelain', 'typewriter', 'candy', 'midnight', 'blueprint'
  ];

  static builtIns(dark: boolean): KeyboardSkin[] {
    return KeyboardSkin.BUILT_IN_IDS.map((id: string) => KeyboardSkin.from(id, dark));
  }

  static choices(dark: boolean, design: CustomKeyboardSkin | null): KeyboardSkin[] {
    const skins: KeyboardSkin[] = KeyboardSkin.builtIns(dark);
    skins.push(KeyboardSkin.from('custom', dark, design));
    return skins;
  }

  /** Identity for caching a rendered skin, including the custom design it was built from. */
  key(): string {
    return this.id + ':' + this.dark + (this.designKey.length === 0 ? '' : ':' + this.designKey);
  }
}
