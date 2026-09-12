// Fixed source: MSIME-Apple@11c950a63ec57656cd78b3f75aa621c293bfe453,
// platforms/ios/SharedUI/CustomKeyboardSkin.swift and KeyboardSkinCollection.swift.
export type TouchSkinKeyShape = "rounded" | "capsule" | "ticket" | "pebble";
export type TouchSkinKeyMaterial = "flat" | "raised" | "glass" | "paper";

export type TouchKeyboardSkinDesign = {
  background: number;
  keyBackground: number;
  keyForeground: number;
  accent: number;
  actionBackground: number;
  cornerRadius: number;
  borderWidth: number;
  shadow: number;
  pattern: 0 | 1 | 2 | 3;
  monospaced: boolean;
  keyShape?: TouchSkinKeyShape;
  keyMaterial?: TouchSkinKeyMaterial;
  keyOpacity?: number;
  gradientEnd?: number;
  gradientHorizontal?: boolean;
  patternOpacity?: number;
  customBorderColor?: number;
  /** Base64-encoded bounded image bytes, matching Swift JSONEncoder Data. */
  photo?: string;
  photoShade?: number;
  photoPosition?: number;
};

export const defaultTouchKeyboardSkinDesign: TouchKeyboardSkinDesign = {
  background: 0xE8F0EB,
  keyBackground: 0xFFFFFF,
  keyForeground: 0x17251D,
  accent: 0x185C47,
  actionBackground: 0x185C47,
  cornerRadius: 8,
  borderWidth: 0,
  shadow: 0,
  pattern: 0,
  monospaced: false,
};

const skin = (patch: Partial<TouchKeyboardSkinDesign>): TouchKeyboardSkinDesign => ({
  ...defaultTouchKeyboardSkinDesign,
  ...patch,
});

export const touchKeyboardSkinTemplates: { title: string; design: TouchKeyboardSkinDesign }[] = [
  { title: "苔庭晨雾", design: skin({ background: 0xE0E9DF, keyBackground: 0xF7FAF3, keyForeground: 0x243F32, accent: 0x214D3A, actionBackground: 0x2F6047, cornerRadius: 12, borderWidth: .5, shadow: .1, pattern: 3, gradientEnd: 0xC6D9CA, gradientHorizontal: true, patternOpacity: .035, customBorderColor: 0xB8CDBE }) },
  { title: "竹影青瓷", design: skin({ background: 0xD9E8E2, keyBackground: 0xF5F8EE, keyForeground: 0x243F38, accent: 0x265443, actionBackground: 0x265443, cornerRadius: 4, borderWidth: 1, shadow: .04, gradientEnd: 0xEBF2E7, gradientHorizontal: true, patternOpacity: 0, customBorderColor: 0x94B4A3 }) },
  { title: "月下银砂", design: skin({ background: 0x181F2B, keyBackground: 0x303E4F, keyForeground: 0xEFF5FC, accent: 0xCEE0F3, actionBackground: 0xCADBEC, cornerRadius: 10, borderWidth: .5, shadow: .08, pattern: 1, gradientEnd: 0x283645, gradientHorizontal: true, patternOpacity: .07, customBorderColor: 0x6F8399 }) },
  { title: "黑金刻度", design: skin({ background: 0x191B19, keyBackground: 0x292D29, keyForeground: 0xEFE9D5, accent: 0xE1CC91, actionBackground: 0xDAC486, cornerRadius: 3, borderWidth: .75, pattern: 2, monospaced: true, gradientEnd: 0x202720, gradientHorizontal: true, patternOpacity: .04, customBorderColor: 0x8D8058 }) },
  { title: "樱雪糯米", design: skin({ background: 0xF4DFE5, keyBackground: 0xFFF8F6, keyForeground: 0x503449, accent: 0x733E58, actionBackground: 0x904D69, cornerRadius: 18, shadow: .14, pattern: 3, gradientEnd: 0xE7E2F2, gradientHorizontal: true, patternOpacity: .04, customBorderColor: 0xDFBBC9 }) },
  { title: "落日陶土", design: skin({ background: 0xEAD4C4, keyBackground: 0xFFF4DF, keyForeground: 0x56382C, accent: 0x733F2B, actionBackground: 0x9A4E32, cornerRadius: 7, borderWidth: .75, shadow: .18, pattern: 1, gradientEnd: 0xF3E4D1, gradientHorizontal: true, patternOpacity: .05, customBorderColor: 0xCBA78D }) },
  { title: "冰川薄荷", design: skin({ background: 0xD9EBEA, keyBackground: 0xF5FFFF, keyForeground: 0x203E4B, accent: 0x275360, actionBackground: 0x34717C, cornerRadius: 14, borderWidth: .5, shadow: .06, pattern: 3, gradientEnd: 0xDDE7F4, gradientHorizontal: true, patternOpacity: .035, customBorderColor: 0xC0DCDB }) },
  { title: "奶咖手账", design: skin({ background: 0xD9CFC0, keyBackground: 0xF6EFE2, keyForeground: 0x453B31, accent: 0x5A4630, actionBackground: 0x65523B, cornerRadius: 5, borderWidth: 1, shadow: .2, pattern: 2, monospaced: true, gradientEnd: 0xE8DFD0, gradientHorizontal: true, patternOpacity: .06, customBorderColor: 0xB09B83 }) },
  { title: "水杉留白", design: skin({}) },
  { title: "复古纸感", design: skin({ background: 0xE3D6BD, keyBackground: 0xFFF5DF, keyForeground: 0x382A1C, accent: 0x53391F, actionBackground: 0x53391F, cornerRadius: 4, borderWidth: 1, shadow: .3, monospaced: true, pattern: 1, keyShape: "ticket", keyMaterial: "paper" }) },
  { title: "紫夜星光", design: skin({ background: 0x151022, gradientEnd: 0x30224A, keyBackground: 0x291E40, keyForeground: 0xFFFFFF, accent: 0xD4BBFF, actionBackground: 0x69469B, borderWidth: 1, customBorderColor: 0xA987E8, pattern: 1, keyShape: "rounded", keyMaterial: "glass" }) },
  { title: "奶油桃桃", design: skin({ background: 0xFFE0D0, gradientEnd: 0xF9D6E5, keyBackground: 0xFFF8EE, keyForeground: 0x51283A, accent: 0x84334F, actionBackground: 0x84334F, cornerRadius: 18, shadow: .15, pattern: 3, keyShape: "pebble", keyMaterial: "raised" }) },
  { title: "海盐渐变", design: skin({ background: 0xDCEAF8, gradientEnd: 0xDDEFE9, gradientHorizontal: true, accent: 0x224E75, actionBackground: 0x224E75, borderWidth: .5 }) },
  { title: "工程蓝图", design: skin({ background: 0x102438, keyBackground: 0x17354F, accent: 0xA2D8FA, actionBackground: 0x285D84, cornerRadius: 2, borderWidth: 1, monospaced: true, pattern: 2, customBorderColor: 0x548CAA, keyForeground: 0xFFFFFF, keyShape: "rounded", keyMaterial: "glass" }) },
];

export const touchKeyboardBackgroundPresets: { start: number; end?: number; title: string }[] = [
  { start: 0xFFFFFF, title: "纯白" }, { start: 0xDFE2EB, title: "雾灰" },
  { start: 0x171717, title: "曜黑" }, { start: 0xFFD5DB, title: "樱粉" },
  { start: 0xAEE3F3, title: "晴空" }, { start: 0xC6E9A7, title: "嫩绿" },
  { start: 0x160A3F, end: 0xA747DF, title: "紫夜渐变" },
  { start: 0xC5F5FF, end: 0xFAD8F6, title: "极光渐变" },
  { start: 0x185C47, end: 0x80BFA8, title: "森林渐变" },
];

export function skinColor(value: number): string {
  return `#${Math.max(0, Math.min(0xFFFFFF, Math.round(value))).toString(16).padStart(6, "0")}`;
}

export function skinLuminance(rgb: number): number {
  const channel = (shift: number) => {
    const value = ((rgb >> shift) & 255) / 255;
    return value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
  };
  return .2126 * channel(16) + .7152 * channel(8) + .0722 * channel(0);
}

export function skinContrast(first: number, second: number): number {
  const a = skinLuminance(first), b = skinLuminance(second);
  return (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
}

export function readableSkinText(background: number): number {
  return skinLuminance(background) > .179 ? 0 : 0xFFFFFF;
}

export function hasReadableSkinText(design: TouchKeyboardSkinDesign): boolean {
  return skinContrast(design.keyForeground, design.keyBackground) >= 4.5
    && skinContrast(design.accent, design.background) >= 4.5
    && skinContrast(design.accent, design.keyBackground) >= 4.5
    && (design.gradientEnd === undefined || skinContrast(design.accent, design.gradientEnd) >= 4.5);
}

export function normalizeTouchKeyboardSkinDesign(value: TouchKeyboardSkinDesign): TouchKeyboardSkinDesign {
  const color = (entry: number) => Math.round(entry) & 0xFFFFFF;
  const clamp = (entry: number, min: number, max: number, fallback: number) => Number.isFinite(entry) ? Math.min(max, Math.max(min, entry)) : fallback;
  return {
    ...value,
    background: color(value.background), keyBackground: color(value.keyBackground),
    keyForeground: color(value.keyForeground), accent: color(value.accent),
    actionBackground: color(value.actionBackground),
    cornerRadius: clamp(value.cornerRadius, 0, 20, 8), borderWidth: clamp(value.borderWidth, 0, 2, 0),
    shadow: clamp(value.shadow, 0, .4, 0), pattern: value.pattern >= 0 && value.pattern <= 3 ? value.pattern : 0,
    keyOpacity: value.keyOpacity === undefined ? undefined : clamp(value.keyOpacity, .25, 1, 1),
    gradientEnd: value.gradientEnd === undefined ? undefined : color(value.gradientEnd),
    patternOpacity: value.patternOpacity === undefined ? undefined : clamp(value.patternOpacity, 0, .5, .15),
    customBorderColor: value.customBorderColor === undefined ? undefined : color(value.customBorderColor),
    photoShade: value.photoShade === undefined ? undefined : clamp(value.photoShade, 0, .8, .25),
    photoPosition: value.photoPosition === undefined ? undefined : clamp(value.photoPosition, 0, 1, .5),
  };
}
