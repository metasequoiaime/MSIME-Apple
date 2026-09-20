import type { Preferences } from "../index";
import { SkinCandidatePreview } from "../skin/skin-candidate-preview";
import { candidateFontSize, candidateFontStyle } from "./candidate-font-size";
import { candidateTextStyle } from "./candidate-text-color";
import { candidateFamilyStyle } from "./candidate-font-family";
import { ExternalAppearancePreview } from "../skin/external-appearance-preview";
import type { SkinCatalog } from "../skin/external-skins";
import type { SkinImageReader } from "../skin/skin-image";
import { useCandidatePreviewTheme } from "./candidate-preview-theme";
import { useResolvedCandidateFonts, type FontFamilyResolver } from "./resolved-candidate-fonts";
import * as settings from "../settings/settings-style";

export function AppearanceCandidatePreview({
  preferences: storedPreferences,
  scan,
  readImage,
  resolveFonts,
  active = true,
  revision = 0,
}: {
  preferences: Preferences;
  scan?: () => Promise<SkinCatalog>;
  readImage?: SkinImageReader;
  resolveFonts?: FontFamilyResolver;
  active?: boolean;
  revision?: number;
}) {
  const preferences = useResolvedCandidateFonts(
    storedPreferences,
    active ? resolveFonts : undefined,
  );
  const skin = preferences.candidate_skin ?? "willow_green";
  const theme = useCandidatePreviewTheme(preferences.theme, preferences.candidate_theme);
  const builtin = ["fluent", "wechat", "graphite", "willow_green"].includes(skin);
  const schemeHelpcode =
    preferences.scheme === "quanpin"
      ? preferences.quanpin_helpcode
      : preferences.shuangpin_helpcode;
  const helpcode =
    (preferences.scheme === "quanpin" || preferences.scheme === "shuangpin") &&
    (schemeHelpcode?.enabled ?? true) &&
    (schemeHelpcode?.show_in_candidate_window ?? true);
  return (
    <section className="section" aria-label="候选窗口预览">
      <div className="section-header">
        <span className="section-title">
          候选窗口预览<small>固定样例随当前设置草稿变化，不代表实际输入候选。</small>
        </span>
      </div>
      {builtin ? (
        <div
          data-skin-preview=""
          className={`${settings.skinCardPreview} appearance-candidate-preview skin-${skin}`}
          data-preview-theme={theme}
          data-font-size={candidateFontSize(preferences.candidate_font_size)}
          style={{
            ...candidateFontStyle(preferences),
            ...candidateTextStyle(
              preferences.candidate_text_color,
              preferences.candidate_number_color,
              preferences.candidate_accent_color,
              preferences.candidate_selected_color,
              preferences.candidate_hover_color,
              preferences.candidate_surface_color,
              preferences.candidate_border_color,
            ),
            ...candidateFamilyStyle(preferences),
          }}
          aria-hidden="true"
        >
          <div className={settings.skinPreviewStage} data-skin-stage="">
            <SkinCandidatePreview
              orientation={preferences.candidate_layout ?? "vertical"}
              count={preferences.candidate_page_size}
              preedit={preferences.candidate_preedit_style !== "empty"}
              helpcode={helpcode}
            />
          </div>
        </div>
      ) : (
        <ExternalAppearancePreview
          preferences={preferences}
          theme={theme}
          scan={scan}
          readImage={readImage}
          active={active}
          revision={revision}
          helpcode={helpcode}
        />
      )}
    </section>
  );
}
