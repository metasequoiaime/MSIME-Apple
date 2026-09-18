import { useEffect, useState } from "react";
import { KeyboardPanel, type PanelClient, type SettingsClient, type Snapshot, type TouchKeyboardSkin, type TouchKeyboardSkinDesign } from "@msime/ui";
import { useCandidatePreviewTheme } from "../../../packages/ui/src/candidate/candidate-preview-theme";
import { invoke, isTauri } from "@tauri-apps/api/core";

type ThemeClient = Pick<SettingsClient, "load" | "onPreferencesChanged" | "host">;

export function DesktopKeyboard({ client, preferences }: { client: PanelClient; preferences: ThemeClient }) {
  const [platform, setPlatform] = useState<string | undefined>(preferences.host?.platform);
  useEffect(() => {
    let active = true;
    if (preferences.host?.platform) setPlatform(preferences.host.platform);
    else if (isTauri()) void invoke<{ platform: string }>("host_capabilities")
      .then(host => { if (active) setPlatform(host.platform); }).catch(() => {});
    return () => { active = false; };
  }, [preferences.host?.platform]);
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  useEffect(() => {
    let active = true;
    let latestRevision = -1;
    let unsubscribe: (() => void) | undefined;
    setSnapshot(null);
    const apply = (value: Snapshot) => {
      if (!active || value.revision <= latestRevision) return;
      latestRevision = value.revision;
      setSnapshot(value);
    };
    const start = async () => {
      // Subscribe before loading so a concurrent save cannot fall between them.
      try {
        const stop = await preferences.onPreferencesChanged?.(apply);
        if (!active) { stop?.(); return; }
        unsubscribe = stop;
      } catch { /* Initial loading still works when event subscription is unavailable. */ }
      if (!active) return;
      try { apply(await preferences.load()); } catch { /* Retain the last valid theme; default is dark. */ }
    };
    void start();
    return () => { active = false; unsubscribe?.(); };
  }, [preferences]);
  const theme = useCandidatePreviewTheme(snapshot?.preferences.theme, snapshot?.preferences.screen_keyboard_theme);
  const layout = snapshot?.preferences.touch_keyboard_layout === "nine_key" ? "nine_key" : "twenty_six_key";
  const keySpacingTenths = snapshot?.preferences.touch_key_spacing_tenths ?? 60;
  const rowSpacingTenths = snapshot?.preferences.touch_row_spacing_tenths ?? 70;
  const skin = snapshot?.preferences.touch_keyboard_skin ?? "forest";
  const customDesign = snapshot?.preferences.custom_touch_keyboard_skin;
  // macOS voice submission belongs to the native IMK session. A standalone
  // Tauri keyboard does not own that session, so exposing this button would
  // only lead to an unusable voice panel; the native input-method toolbar and
  // shortcut remain the supported entry points.
  const voiceShortcut = platform !== undefined && platform !== "macos" && snapshot?.preferences.touch_voice_shortcut === true;
  return <KeyboardPanel client={client} platform={platform} theme={theme} layout={layout} keySpacingTenths={keySpacingTenths} rowSpacingTenths={rowSpacingTenths} voiceShortcut={voiceShortcut} skin={skin as TouchKeyboardSkin} customDesign={customDesign as TouchKeyboardSkinDesign | undefined} />;
}
