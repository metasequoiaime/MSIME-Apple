import type { Preferences } from "./index";
import { SkinCandidatePreview } from "./skin-candidate-preview";

export function AppearanceCandidatePreview({ preferences }: { preferences: Preferences }) {
  const skin = preferences.candidate_skin ?? "fluent";
  const builtin = ["fluent", "wechat", "graphite", "willow_green"].includes(skin);
  const helpcode = preferences.scheme === "quanpin" ? preferences.quanpin_helpcode?.enabled ?? true :
    preferences.scheme === "shuangpin" ? preferences.shuangpin_helpcode?.enabled ?? true : false;
  return <section className="section" aria-label="候选窗口预览">
    <div className="section-header"><span className="section-title">候选窗口预览<small>固定样例随当前设置草稿变化，不代表实际输入候选。</small></span></div>
    {builtin ? <div className={`skin-card-preview appearance-candidate-preview skin-${skin}`} data-preview-theme="dark"
      data-font-size={preferences.candidate_font_size ?? 18} aria-hidden="true">
      <div className="skin-preview-stage"><SkinCandidatePreview orientation={preferences.candidate_layout ?? "vertical"}
        count={preferences.candidate_page_size} preedit={preferences.candidate_preedit_style !== "empty"} helpcode={helpcode} /></div>
    </div> : <p className="skin-intro">外部皮肤请在“皮肤”页查看预览；此处暂不预览外部皮肤。</p>}
  </section>;
}
