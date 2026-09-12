import { validFontFamily, type CandidateFontPreferences } from "./candidate-font-family";

export function CandidateFontControls({ value, onChange }: { value: CandidateFontPreferences; onChange: (patch: CandidateFontPreferences) => void }) {
  const fonts = value.candidate_fallback_fonts ?? [];
  const move = (index: number, delta: number) => {
    const next = [...fonts];
    [next[index], next[index + delta]] = [next[index + delta], next[index]];
    onChange({ candidate_fallback_fonts: next });
  };
  return <>
    <div className="section"><label className="section-header"><span className="section-title">候选窗主字体</span>
      <input aria-label="候选窗主字体" autoComplete="off" spellCheck={false} value={value.candidate_font_family ?? "Segoe UI"}
        aria-invalid={!validFontFamily(value.candidate_font_family ?? "Segoe UI")} onChange={event => onChange({ candidate_font_family: event.target.value })} />
    </label></div>
    <div className="section"><div className="section-header"><span className="section-title">候选窗补充字体<small>主字体缺字时依次回落，最后使用系统字体。最多 32 项；暂未接入系统字体列表，请输入完整字体名。</small></span></div>
      <div className="candidate-fallback-list" role="group" aria-label="补充字体回落顺序">{fonts.map((font, index) => <div className="candidate-fallback-row" key={index}>
        <input aria-label={`补充字体 ${index + 1}`} autoComplete="off" spellCheck={false} value={font} aria-invalid={!validFontFamily(font)}
          onChange={event => onChange({ candidate_fallback_fonts: fonts.map((item, position) => position === index ? event.target.value : item) })} />
        <button type="button" className="secondary" aria-label={`上移补充字体 ${index + 1}`} disabled={index === 0} onClick={() => move(index, -1)}>↑</button>
        <button type="button" className="secondary" aria-label={`下移补充字体 ${index + 1}`} disabled={index === fonts.length - 1} onClick={() => move(index, 1)}>↓</button>
        <button type="button" className="secondary" aria-label={`移除补充字体 ${index + 1}`} onClick={() => onChange({ candidate_fallback_fonts: fonts.filter((_, position) => position !== index) })}>移除</button>
      </div>)}</div>
      <button type="button" className="secondary" disabled={fonts.length >= 32 || fonts.some(font => !validFontFamily(font))} onClick={() => onChange({ candidate_fallback_fonts: [...fonts, ""] })}>添加补充字体</button>
    </div>
  </>;
}
