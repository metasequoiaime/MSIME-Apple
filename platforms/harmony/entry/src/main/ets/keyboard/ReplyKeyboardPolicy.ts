import { utf8Length } from './Utf8';

export interface ReplyStyle { readonly id: string; readonly title: string; }
export interface ReplyRequest { readonly source: string; readonly style: string; readonly prompt: string; }

export class ReplyKeyboardPolicy {
  static readonly MAX_SOURCE_UTF8: number = 10000;
  static readonly MAX_RESULT_UTF8: number = 4096;
  static readonly MAX_RESULTS: number = 3;
  static readonly STYLES: ReplyStyle[] = [
    { id: '专属回复', title: '😁 专属回复' }, { id: '暖心关怀', title: '🥰 暖心关怀' },
    { id: '捧场王', title: '📣 捧场王' }, { id: '恋人', title: '😍 恋人' },
    { id: '幽默风趣', title: '🌪 幽默风趣' }, { id: '成熟稳重', title: '👔 成熟稳重' },
    { id: '土味情话', title: '💬 土味情话' }, { id: '高情商', title: '🤩 高情商' },
    { id: '委婉拒绝', title: '🙌 委婉拒绝' }
  ];
  static source(value: string): string | null {
    const trimmed: string = value.trim();
    if (trimmed.length === 0 || utf8Length(trimmed) > ReplyKeyboardPolicy.MAX_SOURCE_UTF8
      || ReplyKeyboardPolicy.hasControl(trimmed)) return null;
    return trimmed;
  }
  static request(source: string, style: string): ReplyRequest | null {
    const normalized: string | null = ReplyKeyboardPolicy.source(source);
    const selected: string = style.trim();
    if (normalized === null || selected.length === 0 || ReplyKeyboardPolicy.hasControl(selected)) return null;
    return { source: normalized, style: selected,
      prompt: `对方发来以下内容，请拟写一条${selected}风格的高情商回复。尊重对方且有边界，不编造事实、关系或承诺。只输出一条简短自然、可以直接发送的回复，不加标题、解释或引号。` };
  }
  static results(values: string[] | null): string[] {
    if (values === null) return [];
    const result: string[] = [];
    for (const value of values) {
      if (typeof value !== 'string' || value.trim().length === 0 || utf8Length(value) > ReplyKeyboardPolicy.MAX_RESULT_UTF8
        || ReplyKeyboardPolicy.hasControl(value)) continue;
      if (!result.includes(value)) result.push(value);
      if (result.length === ReplyKeyboardPolicy.MAX_RESULTS) break;
    }
    return result;
  }
  private static hasControl(value: string): boolean {
    for (const character of value) {
      const code: number = character.codePointAt(0) ?? 0;
      if (code <= 0x1f || (code >= 0x7f && code <= 0x9f)) return true;
    }
    return false;
  }
}
