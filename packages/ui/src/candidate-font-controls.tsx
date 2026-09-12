import { validFontFamily, type CandidateFontPreferences } from "./candidate-font-family";
import { useFontCatalog, type FontCatalogReader } from "./font-catalog";
import { FontFamilyInput } from "./font-family-input";

export function CandidateFontControls({ value, onChange, readFonts }: { value: CandidateFontPreferences; onChange: (patch: CandidateFontPreferences) => void; readFonts?: FontCatalogReader }) {
  const catalog = useFontCatalog(readFonts);
  const fonts = value.candidate_fallback_fonts ?? [];
  const move = (index: number, delta: number) => {
    const next = [...fonts];
    [next[index], next[index + delta]] = [next[index + delta], next[index]];
    onChange({ candidate_fallback_fonts: next });
  };
  return <>
    <div className="section"><div className="section-header"><span className="section-title">候选窗主字体</span>
      <FontFamilyInput label="候选窗主字体" value={value.candidate_font_family ?? "Segoe UI"} fonts={catalog.fonts} enabled={!!readFonts} ready={catalog.status === "ready"} request={catalog.request} onChange={font => onChange({ candidate_font_family: font })} />
    </div>
      <p role="status">{catalog.status === "unsupported" ? "当前宿主未接入系统字体列表，请输入完整字体名。" : catalog.status === "loading" ? "正在读取字体列表。" : catalog.status === "failed" ? "读取字体列表失败，可重试或手动输入。" : catalog.status === "ready" && !catalog.fonts.length ? "系统字体列表为空，可手动输入。" : ""}</p>
      {readFonts && <button type="button" className="secondary" disabled={catalog.status === "loading"} onClick={catalog.refresh}>刷新字体列表</button>}
    </div>
    <div className="section"><div className="section-header"><span className="section-title">候选窗补充字体<small>主字体缺字时依次回落，最后使用系统字体。最多 32 项。</small></span></div>
      <div className="candidate-fallback-list" role="group" aria-label="补充字体回落顺序">{fonts.map((font, index) => <div className="candidate-fallback-row" key={index}>
        <FontFamilyInput label={`补充字体 ${index + 1}`} value={font} fonts={catalog.fonts} enabled={!!readFonts} ready={catalog.status === "ready"} request={catalog.request} excluded={fonts.filter((_, position) => position !== index)}
          onChange={next => onChange({ candidate_fallback_fonts: fonts.map((item, position) => position === index ? next : item) })} />
        <button type="button" className="secondary" aria-label={`上移补充字体 ${index + 1}`} disabled={index === 0} onClick={() => move(index, -1)}>↑</button>
        <button type="button" className="secondary" aria-label={`下移补充字体 ${index + 1}`} disabled={index === fonts.length - 1} onClick={() => move(index, 1)}>↓</button>
        <button type="button" className="secondary" aria-label={`移除补充字体 ${index + 1}`} onClick={() => onChange({ candidate_fallback_fonts: fonts.filter((_, position) => position !== index) })}>移除</button>
      </div>)}</div>
      <button type="button" className="secondary" disabled={fonts.length >= 32 || fonts.some(font => !validFontFamily(font))} onClick={() => onChange({ candidate_fallback_fonts: [...fonts, ""] })}>添加补充字体</button>
    </div>
  </>;
}
