import { useState } from "react";
import { ScreenKeyboardPreview } from "./screen-keyboard-preview";
import {
  defaultTouchKeyboardSkinDesign, hasReadableSkinText, normalizeTouchKeyboardSkinDesign,
  readableSkinText, skinColor, skinContrast, touchKeyboardBackgroundPresets,
  touchKeyboardSkinTemplates, type TouchKeyboardSkinDesign, type TouchSkinKeyMaterial,
  type TouchSkinKeyShape,
} from "./touch-keyboard-skin-design";

type Category = "背景" | "按键" | "文本" | "设计";

function colorNumber(value: string): number {
  return Number.parseInt(value.slice(1), 16);
}

async function boundedPhoto(file: File): Promise<string> {
  if (!file.type.startsWith("image/") || file.size > 20_000_000) throw new Error("invalid image");
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = url;
    await new Promise<void>((resolve, reject) => {
      image.onload = () => resolve();
      image.onerror = () => reject(new Error("image decode failed"));
    });
    if (!image.naturalWidth || !image.naturalHeight) throw new Error("empty image");
    const scale = Math.min(1, 1024 / Math.max(image.naturalWidth, image.naturalHeight));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
    const context = canvas.getContext("2d");
    if (!context) throw new Error("canvas unavailable");
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    for (const quality of [.8, .6, .4, .2]) {
      const data = canvas.toDataURL("image/jpeg", quality).split(",")[1] ?? "";
      if (Math.floor(data.length * .75) <= 512_000) return data;
    }
    throw new Error("image too large");
  } finally {
    URL.revokeObjectURL(url);
  }
}

export function TouchKeyboardSkinEditor({ design, selected, theme, disabled, onChange, onUse, onClose }: {
  design: TouchKeyboardSkinDesign;
  selected: boolean;
  theme: "dark" | "light";
  disabled?: boolean;
  onChange: (design: TouchKeyboardSkinDesign) => void;
  onUse: () => void;
  onClose: () => void;
}) {
  const [category, setCategory] = useState<Category>("背景");
  const [undo, setUndo] = useState<TouchKeyboardSkinDesign[]>([]);
  const [redo, setRedo] = useState<TouchKeyboardSkinDesign[]>([]);
  const [photoError, setPhotoError] = useState("");
  const apply = (next: TouchKeyboardSkinDesign, record = true) => {
    const normalized = normalizeTouchKeyboardSkinDesign(next);
    if (JSON.stringify(normalized) === JSON.stringify(design)) return;
    if (record) {
      setUndo(items => [...items, design].slice(-30));
      setRedo([]);
    }
    onChange(normalized);
  };
  const patch = (value: Partial<TouchKeyboardSkinDesign>, record = true) => apply({ ...design, ...value }, record);
  const stepBack = () => {
    const next = undo.at(-1);
    if (!next) return;
    setUndo(items => items.slice(0, -1));
    setRedo(items => [...items, design].slice(-30));
    apply(next, false);
  };
  const stepForward = () => {
    const next = redo.at(-1);
    if (!next) return;
    setRedo(items => items.slice(0, -1));
    setUndo(items => [...items, design].slice(-30));
    apply(next, false);
  };
  const optimizeContrast = () => {
    const black = Math.min(skinContrast(0, design.background), skinContrast(0, design.keyBackground));
    const white = Math.min(skinContrast(0xFFFFFF, design.background), skinContrast(0xFFFFFF, design.keyBackground));
    patch({ keyForeground: readableSkinText(design.keyBackground), accent: black >= white ? 0 : 0xFFFFFF });
  };

  return <div className="touch-skin-editor" aria-label="自定义皮肤编辑器">
    <div className="touch-skin-editor-heading">
      <div><div className="section-title">自定义皮肤<small>Apple 同款当前设计字段；修改后使用页面底部“保存设置”写入共享配置</small></div></div>
      <button type="button" className="secondary" onClick={onClose}>完成</button>
    </div>
    <div className="touch-skin-editor-tabs" role="tablist" aria-label="皮肤编辑分类">
      {(["背景", "按键", "文本", "设计"] as Category[]).map(item => <button type="button" role="tab" aria-selected={category === item} className={category === item ? "selected" : ""} onClick={() => setCategory(item)} key={item}>{item}</button>)}
    </div>

    <div className="touch-skin-editor-controls">
      {category === "背景" && <>
        <div className="touch-skin-control-block"><div className="touch-skin-control-title">背景预设</div><div className="touch-skin-background-grid">
          {touchKeyboardBackgroundPresets.map(preset => <button type="button" aria-label={`背景预设 ${preset.title}`} onClick={() => patch({ photo: undefined, background: preset.start, gradientEnd: preset.end, gradientHorizontal: false })} key={preset.title} style={{ background: `linear-gradient(135deg, ${skinColor(preset.start)}, ${skinColor(preset.end ?? preset.start)})` }}><span>{preset.title}</span></button>)}
        </div></div>
        <div className="touch-skin-control-block touch-skin-form-grid">
          <label>背景起始色<input aria-label="背景起始色" type="color" value={skinColor(design.background)} onChange={event => patch({ background: colorNumber(event.target.value) })} /></label>
          <label className="touch-skin-check-label"><input aria-label="渐变背景" type="checkbox" checked={design.gradientEnd !== undefined} onChange={event => patch({ gradientEnd: event.target.checked ? design.background : undefined })} />渐变背景</label>
          {design.gradientEnd !== undefined && <><label>渐变结束色<input aria-label="渐变结束色" type="color" value={skinColor(design.gradientEnd)} onChange={event => patch({ gradientEnd: colorNumber(event.target.value) })} /></label><label className="touch-skin-check-label"><input aria-label="横向渐变" type="checkbox" checked={design.gradientHorizontal ?? false} onChange={event => patch({ gradientHorizontal: event.target.checked })} />横向渐变</label></>}
        </div>
        <div className="touch-skin-control-block"><div className="touch-skin-control-title">照片壁纸</div>
          <label className="secondary touch-skin-photo-button">{design.photo ? "更换照片" : "选择照片"}<input aria-label="选择皮肤照片" type="file" accept="image/*" onChange={event => { const file = event.target.files?.[0]; event.target.value = ""; if (!file) return; setPhotoError(""); void boundedPhoto(file).then(photo => patch({ photo })).catch(() => setPhotoError("无法读取或压缩这张照片，请换一张再试。")); }} /></label>
          {photoError && <p role="alert" className="touch-skin-warning">{photoError}</p>}
          {design.photo && <div className="touch-skin-form-grid"><label>照片位置 · {Math.round((design.photoPosition ?? .5) * 100)}%<input aria-label="照片位置" type="range" min="0" max="1" step=".01" value={design.photoPosition ?? .5} onChange={event => patch({ photoPosition: Number(event.target.value) })} /></label><label>压暗照片 · {Math.round((design.photoShade ?? .25) * 100)}%<input aria-label="压暗照片" type="range" min="0" max=".8" step=".01" value={design.photoShade ?? .25} onChange={event => patch({ photoShade: Number(event.target.value) })} /></label><button type="button" className="danger-text" onClick={() => patch({ photo: undefined })}>移除照片</button></div>}
        </div>
        <div className="touch-skin-control-block touch-skin-form-grid"><label>背景纹理<select aria-label="背景纹理" value={design.pattern} onChange={event => patch({ pattern: Number(event.target.value) as TouchKeyboardSkinDesign["pattern"] })}><option value="0">纯色</option><option value="1">网点</option><option value="2">网格</option><option value="3">波纹</option></select></label>{design.pattern !== 0 && <label>纹理强度 · {Math.round((design.patternOpacity ?? .15) * 100)}%<input aria-label="纹理强度" type="range" min="0" max=".5" step=".01" value={design.patternOpacity ?? .15} onChange={event => patch({ patternOpacity: Number(event.target.value) })} /></label>}</div>
      </>}

      {category === "按键" && <>
        <div className="touch-skin-control-block touch-skin-form-grid"><label>键帽颜色<input aria-label="键帽颜色" type="color" value={skinColor(design.keyBackground)} onChange={event => patch({ keyBackground: colorNumber(event.target.value) })} /></label><label>功能键颜色<input aria-label="功能键颜色" type="color" value={skinColor(design.actionBackground)} onChange={event => patch({ actionBackground: colorNumber(event.target.value) })} /></label></div>
        <div className="touch-skin-control-block touch-skin-form-grid">
          <label>键帽造型<select aria-label="键帽造型" value={design.keyShape ?? "rounded"} onChange={event => patch({ keyShape: event.target.value as TouchSkinKeyShape })}><option value="rounded">圆角</option><option value="capsule">胶囊</option><option value="ticket">票券</option><option value="pebble">卵石</option></select></label>
          <label>键帽材质<select aria-label="键帽材质" value={design.keyMaterial ?? "flat"} onChange={event => patch({ keyMaterial: event.target.value as TouchSkinKeyMaterial })}><option value="flat">哑光</option><option value="raised">立体</option><option value="glass">玻璃</option><option value="paper">纸张</option></select></label>
          <label>键帽不透明度 · {Math.round((design.keyOpacity ?? 1) * 100)}%<input aria-label="键帽不透明度" type="range" min=".25" max="1" step=".01" value={design.keyOpacity ?? 1} onChange={event => patch({ keyOpacity: Number(event.target.value) })} /></label>
          <label>圆角 · {Math.round(design.cornerRadius)}<input aria-label="自定义键帽圆角" type="range" min="0" max="20" step="1" value={design.cornerRadius} onChange={event => patch({ cornerRadius: Number(event.target.value) })} /></label>
          <label>边框 · {design.borderWidth.toFixed(1)}<input aria-label="自定义键帽边框" type="range" min="0" max="2" step=".5" value={design.borderWidth} onChange={event => patch({ borderWidth: Number(event.target.value) })} /></label>
          <label>阴影 · {Math.round(design.shadow * 100)}%<input aria-label="自定义键帽阴影" type="range" min="0" max=".4" step=".05" value={design.shadow} onChange={event => patch({ shadow: Number(event.target.value) })} /></label>
          <label>边框颜色<input aria-label="边框颜色" type="color" value={skinColor(design.customBorderColor ?? design.accent)} onChange={event => patch({ customBorderColor: colorNumber(event.target.value) })} /></label>
        </div>
      </>}

      {category === "文本" && <div className="touch-skin-control-block touch-skin-form-grid">
        <label className="touch-skin-check-label"><input aria-label="等宽字形" type="checkbox" checked={design.monospaced} onChange={event => patch({ monospaced: event.target.checked })} />等宽字形</label>
        <label>按键文字<input aria-label="按键文字" type="color" value={skinColor(design.keyForeground)} onChange={event => patch({ keyForeground: colorNumber(event.target.value) })} /></label>
        <label>提示与工具栏<input aria-label="提示与工具栏" type="color" value={skinColor(design.accent)} onChange={event => patch({ accent: colorNumber(event.target.value) })} /></label>
        {!hasReadableSkinText(design) && <p className="touch-skin-warning">部分文字与背景对比度偏低，建议调整配色。</p>}
        <button type="button" className="secondary" onClick={optimizeContrast}>优化文字对比度</button>
      </div>}

      {category === "设计" && <><div className="touch-skin-template-grid">{touchKeyboardSkinTemplates.map(template => <button type="button" aria-label={`皮肤模板 ${template.title}`} onClick={() => apply(template.design)} key={template.title} style={{ background: `linear-gradient(135deg, ${skinColor(template.design.background)}, ${skinColor(template.design.gradientEnd ?? template.design.background)})`, color: skinColor(template.design.accent) }}><ScreenKeyboardPreview theme={theme} skin="custom" customDesign={template.design} compact /><span>{template.title}</span></button>)}</div><button type="button" className="danger-text" onClick={() => apply(defaultTouchKeyboardSkinDesign)}>重置我的皮肤</button></>}
    </div>

    <div className="touch-skin-editor-preview">
      <div className="touch-skin-editor-actions"><button type="button" className="secondary" disabled={!undo.length || disabled} onClick={stepBack}>撤销设计</button><button type="button" className="secondary" disabled={!redo.length || disabled} onClick={stepForward}>重做</button><button type="button" className="primary" disabled={disabled || selected} onClick={onUse}>{selected ? "正在使用" : "使用皮肤"}</button></div>
      <ScreenKeyboardPreview theme={theme} skin="custom" customDesign={design} />
    </div>
  </div>;
}
