import { useEffect, useId, useRef, useState, type CSSProperties } from "react";
import { SkinCandidatePreview } from "./skin-candidate-preview";
import { SkinToolbarPreview } from "./skin-toolbar-preview";
import { useSkinImage, type SkinImageReader } from "./skin-image";
import { installSkinPalette } from "./skin-palette";
import { useToolbarCss, type ToolbarCssReader } from "./use-toolbar-css";

type Palette = Partial<Record<"accent" | "selected" | "hover" | "surface" | "border" | "text" | "number", string | null>> & { showSelectedBar?: boolean | null };
export type ExternalSkin = {
  id: string; name: string; version: string; base: string;
  author: string | null; description: string | null;
  layouts: string[]; themes: string[];
  minWidthDip: number; decorationTopDip: number; decorationWidthDip: number;
  toolbarStylesheet: string | null; preview: string | null;
  candidate: { dark: Palette; light: Palette };
};
export type SkinCatalog = { directory: string; packages: ExternalSkin[]; issues: { folder: string; reason: string }[] };

function dimension(value: number, maximum: number): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= maximum ? value : 0;
}

// Same plain colour notations as the fixed Windows upstream. Never interpolate
// arbitrary manifest strings into stylesheet rules or load URLs from a palette.
const colorPattern = /^(#[0-9a-f]{3,4}|#[0-9a-f]{6}|#[0-9a-f]{8}|rgb\(\s*\d{1,3}\s*(,|\s)\s*\d{1,3}\s*(,|\s)\s*\d{1,3}\s*\)|rgba\(\s*\d{1,3}\s*(,|\s)\s*\d{1,3}\s*(,|\s)\s*\d{1,3}\s*(,|\/)\s*(0|1|0?\.\d+|\d{1,3}%)\s*\))$/i;
function paletteCss(scope: string, palette: Palette): string[] {
  const rules: [keyof Palette, string, string][] = [
    ["accent", ".cursor", "background"], ["accent", ".first::before", "background"],
    ["selected", ".first", "background-color"], ["hover", ".cand:not(.first):hover", "background-color"],
    ["surface", ".container", "background"], ["border", ".container", "border-color"],
    ["text", ".container", "color"],
  ];
  const css = rules.map(([key, selector, property]) => {
    const value = palette[key];
    return typeof value === "string" && colorPattern.test(value.trim())
      ? `.${scope} ${selector}{${property}:${value.trim()} !important}` : "";
  }).filter(Boolean);
  if (palette.showSelectedBar === false) css.push(`.${scope} .first::before{display:none !important}`);
  return css;
}

function ExternalSkinCard({ skin, selected, layout, onSelect, readImage, readToolbarCss, revision }: {
  skin: ExternalSkin; selected: string; layout: string; onSelect: (id: string) => void; readImage?: SkinImageReader; readToolbarCss?: ToolbarCssReader; revision: number;
}) {
  const [override, setOverride] = useState<"dark" | "light" | null>(null);
  const theme = override ?? (skin.themes.includes("dark") ? "dark" : "light");
  const scope = `external-preview-${useId().replace(/[^a-zA-Z0-9_-]/g, "")}`;
  const toolbarState = useToolbarCss(readToolbarCss, skin.id, skin.toolbarStylesheet, revision, scope, readImage);
  const [paletteFailed, setPaletteFailed] = useState(false);
  useEffect(() => {
    try {
      const remove = installSkinPalette([...paletteCss(scope, skin.candidate.dark), ...(theme === "light" ? paletteCss(scope, skin.candidate.light) : [])]);
      setPaletteFailed(false);
      return remove;
    } catch { setPaletteFailed(true); }
  }, [scope, skin.candidate, theme]);
  // Current settings host uses the dark product theme. Preview overrides must
  // not change runtime compatibility or the selected preference.
  const compatible = skin.layouts.includes(layout) && skin.themes.includes("dark");
  const base = ["fluent", "wechat", "graphite", "willow_green"].includes(skin.base) ? skin.base : "fluent";
  const top = dimension(skin.decorationTopDip, 500);
  const width = dimension(skin.decorationWidthDip, 1000);
  const decorated = top > 0 && width > 0;
  const image = useSkinImage(readImage, skin.id, decorated ? skin.preview : null, revision);
  const [decodeFailed, setDecodeFailed] = useState(false);
  useEffect(() => setDecodeFailed(false), [image]);
  const geometry = {
    "--msime-skin-min-width": `${dimension(skin.minWidthDip, 1000)}px`,
    "--msime-skin-decoration-top": `${decorated ? top : 0}px`,
    "--msime-skin-decoration-width": `${decorated ? width : 0}px`,
  } as CSSProperties;
  return <article aria-label={skin.name} className={`skin-card${selected === skin.id ? " selected" : ""}${decorated ? " external-skin-decorated" : ""}`}>
    <div className="skin-card-header">
      <div className="skin-card-body">
        <span className="skin-card-title">{skin.name}</span>
        <span className="external-skin-meta">{[skin.id, skin.version && `v${skin.version}`, skin.author].filter(Boolean).join(" · ")}</span>
        <span className="skin-card-description">{compatible ? (skin.description || `基于 ${skin.base}`) : `当前布局或明暗模式不受支持（${skin.layouts.join("/")}，${skin.themes.join("/")}）`}</span>
      </div>
      <div className="skin-card-actions">
        <button type="button" role="switch" aria-label={skin.name} aria-checked={selected === skin.id} disabled={!compatible} className="skin-selection-switch" onClick={() => onSelect(skin.id)}><span /></button>
        <button type="button" className="skin-preview-switch" onClick={() => setOverride(theme === "dark" ? "light" : "dark")}>{theme === "dark" ? "预览浅色" : "预览深色"}</button>
      </div>
    </div>
    <div className={`skin-card-preview skin-${base} ${scope}${theme === "light" ? " theme-light" : ""}`} style={geometry} data-preview-theme={theme} aria-hidden="true">
      <div className="skin-preview-stage"><SkinCandidatePreview orientation="horizontal" decorated={decorated} image={decodeFailed ? undefined : image?.url} onImageError={() => setDecodeFailed(true)} /></div>
      <div className="skin-preview-stage"><SkinCandidatePreview orientation="vertical" decorated={decorated} image={decodeFailed ? undefined : image?.url} onImageError={() => setDecodeFailed(true)} /></div>
      <div className="skin-preview-stage"><SkinToolbarPreview /></div>
    </div>
    {paletteFailed && <p role="status" className="skin-card-description external-skin-resource-note">当前浏览器无法应用皮肤配色，保留基础预览。</p>}
    {(image?.failed || decodeFailed) && <p role="status" className="skin-card-description external-skin-resource-note">皮肤图片加载失败，保留基础预览。可刷新皮肤重试。</p>}
    {skin.preview && decorated && !readImage && <p className="skin-card-description external-skin-resource-note">当前宿主不支持皮肤图片预览。</p>}
    {skin.toolbarStylesheet && !readToolbarCss && <p className="skin-card-description external-skin-resource-note">当前宿主不支持外部工具栏样式。</p>}
    {toolbarState === "failed" && <p role="status">工具栏样式加载失败，保留基础预览。可刷新皮肤重试。</p>}
    {toolbarState === "partial" && <p role="status">已应用工具栏基础样式；关联资源及部分规则尚未支持。</p>}
  </article>;
}

export function ExternalSkins({ scan, openDirectory, readImage, readToolbarCss, selected, layout, onSelect }: {
  scan?: () => Promise<SkinCatalog>; openDirectory?: () => Promise<void>; readImage?: SkinImageReader; readToolbarCss?: ToolbarCssReader; selected: string; layout: string; onSelect: (id: string) => void;
}) {
  const [catalog, setCatalog] = useState<SkinCatalog | null>(null);
  const [revision, setRevision] = useState(0);
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);
  const generation = useRef(0);
  const pending = useRef(false);
  const [opening, setOpening] = useState(false);
  const [openFailed, setOpenFailed] = useState(false);
  const openGeneration = useRef(0);
  const openPending = useRef(false);
  useEffect(() => {
    openGeneration.current++;
    openPending.current = false;
    setOpening(false); setOpenFailed(false);
    return () => { openGeneration.current++; openPending.current = false; };
  }, [openDirectory]);
  async function openFolder() {
    if (!openDirectory || openPending.current) return;
    openPending.current = true;
    const current = ++openGeneration.current;
    setOpening(true); setOpenFailed(false);
    try { await openDirectory(); }
    catch { if (current === openGeneration.current) setOpenFailed(true); }
    finally {
      if (current === openGeneration.current) { openPending.current = false; setOpening(false); }
    }
  }
  useEffect(() => {
    generation.current++;
    pending.current = false;
    setCatalog(null); setBusy(false); setFailed(false);
    return () => { generation.current++; pending.current = false; };
  }, [scan]);
  async function refresh() {
    if (!scan || pending.current) return;
    pending.current = true;
    const current = ++generation.current;
    setBusy(true); setFailed(false);
    try {
      const result = await scan();
      if (current === generation.current) { setCatalog(result); setRevision(value => value + 1); }
    } catch {
      if (current === generation.current) setFailed(true);
    } finally {
      if (current === generation.current) { pending.current = false; setBusy(false); }
    }
  }
  return <section aria-label="外部皮肤" className="external-skins">
    <div className="external-skin-heading">
      <div><div className="section-title">外部皮肤</div><p className="skin-card-description">把包含 skin.toml 的皮肤文件夹复制到下面的目录，然后刷新。</p><code className="external-skin-directory">{catalog?.directory || "扫描后显示客户端皮肤目录"}</code></div>
      <div className="external-skin-actions">
        <button type="button" className="skin-preview-switch" disabled={!openDirectory || opening} onClick={() => void openFolder()}>{opening ? "正在打开…" : "打开目录"}</button>
        <button type="button" className="skin-preview-switch" disabled={!scan || busy} onClick={() => void refresh()}>{busy ? "正在扫描…" : "刷新皮肤"}</button>
      </div>
    </div>
    {openFailed && <p role="alert">无法打开皮肤目录，请重试。</p>}
    {failed && <p role="alert">读取皮肤目录失败，请重试。{catalog && "仍显示上次扫描结果。"}</p>}
    <div role="status">{!scan ? "当前宿主不支持扫描外部皮肤。" : busy ? "正在读取皮肤目录。" : !catalog ? "尚未扫描。点击“刷新皮肤”读取皮肤目录。" : !catalog.packages.length ? "没有发现外部皮肤。" : ""}</div>
    <div className="skin-grid">{catalog?.packages.map(skin => <ExternalSkinCard key={skin.id} skin={skin} selected={selected} layout={layout} onSelect={onSelect} readImage={readImage} readToolbarCss={readToolbarCss} revision={revision} />)}</div>
    {!!catalog?.issues.length && <details className="external-skin-diagnostics"><summary>已忽略 {catalog.issues.length} 个无效皮肤目录</summary><ul>{catalog.issues.map((issue, index) => <li key={index}>{issue.folder}：{issue.reason}</li>)}</ul></details>}
  </section>;
}
