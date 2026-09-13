import { createVoiceRecognitionClient } from "./voice-recognition-client";
import { StrictMode, useEffect, useState, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { invoke, isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { CloudCandidatesPanel, CloudClipboardPanel, CloudDictionaryCatalogPanel, CloudDictionaryPanel, EmojiPanel, HandwritingPanel, KeyboardPanel, VoicePanel, SettingsPage, WelcomeFlowPage, useCandidatePreviewTheme, type AiSkinProposal, type CloudClipboardAction, type CloudClipboardPanelClient, type CloudDictionaryAction, type CloudDictionaryEntry, type CloudDictionaryPanelClient, type CommunitySkin, type CommunitySkinDownload, type CommunitySkinPage, type CommunityResource, type CommunityResourceApplication, type CommunityResourcePage, type EmojiCatalogGroup, type EmojiPanelClient, type HostCapabilities, type TypingStatisticsClient, type PanelClient, type VoicePanelClient, type SettingsClient, type Snapshot, type DictionaryClient, type DictionaryEntry, type LocalDictionaryKind, type LocalDictionaryFormat, type OnboardingActions, type OnboardingInputScheme } from "@msime/ui";
import "@msime/ui/styles.css";
import { subscribeWindowState } from "./window-state";
import { discoverFontReader } from "./system-font-client";
import { DesktopKeyboard } from "./desktop-keyboard";

const dictionary: DictionaryClient = {
  list: (offset, limit) => invoke("dictionary_request", { action: { operation: "list", offset, limit } }),
  edit: (previous: DictionaryEntry | null, replacement: DictionaryEntry | null, request_id: string) => invoke("dictionary_request", { action: { operation: "edit", previous, replacement, request_id } }).then(() => undefined),
  import: (kind: LocalDictionaryKind, format: LocalDictionaryFormat, text: string, request_id: string) => invoke("dictionary_request", { action: { operation: "import", kind, format, text, request_id } }),
  ...(/\bAndroid\b/i.test(navigator.userAgent) ? {
    importPersonal: (text: string, request_id: string) => invoke("dictionary_request", { action: { operation: "import_personal", text, request_id } }),
  } : {}),
  export: (kind: LocalDictionaryKind, format: Exclude<LocalDictionaryFormat, "rime" | "hans">, offset: number, limit: number) => invoke("dictionary_request", { action: { operation: "export", kind, format, offset, limit } }),
  retry: request_id => invoke("dictionary_request", { action: { operation: "retry", request_id } }).then(() => undefined),
  dismissFailure: request_id => invoke("dictionary_request", { action: { operation: "dismiss_failure", request_id } }).then(() => undefined),
};
const typingStatistics: TypingStatisticsClient = {
  load: () => invoke("load_typing_statistics"),
  setEnabled: (enabled: boolean) => invoke("set_typing_statistics_enabled", { enabled }),
  reset: () => invoke("reset_typing_statistics"),
};
const client: SettingsClient = {
  scanSkinCatalog: () => invoke("scan_skin_catalog"),
  readSkinToolbarCss: id => invoke("read_skin_toolbar_stylesheet", { id }),
  readSkinImage: (id, relative) => invoke("read_skin_image", { id, relative }),
  readSkinFont: (id, relative) => invoke("read_skin_font", { id, relative }),
  openSkinDirectory: () => invoke("open_skin_directory"),
  load: () => {
    if (!isTauri()) return Promise.reject(new Error("请通过客户端应用打开设置。浏览器预览不会写入本地配置。"));
    return invoke<Snapshot>("load_preferences");
  },
  save: (expectedRevision, preferences) => invoke<Snapshot>("save_preferences", { expectedRevision, preferences }),
  onPreferencesChanged: listener => listen<Snapshot>("preferences-changed", event => listener(event.payload)),
  openExternalUrl: url => invoke("open_external_url", { url }),
  copyText: text => invoke("copy_text", { text }),
  openScreenKeyboard: () => invoke("open_keyboard_panel"),
  openHandwriting: () => invoke("open_handwriting_panel"),
  listVoiceCaptureDevices: () => invoke("list_voice_capture_devices"),
  openVoice: () => invoke("open_voice_panel"),
  openCloudClipboard: () => invoke("open_cloud_clipboard_panel"),
  openCloudDictionary: () => invoke("open_cloud_dictionary_panel"),
  restartInputMethod: () => invoke("restart_input_method"),
  windowControl: async action => {
    const window = getCurrentWindow();
    if (action === "minimize") return window.minimize();
    if (action === "close") return window.close();
    if (action === "restore") return window.unmaximize();
    return window.maximize();
  },
  beginWindowDrag: () => getCurrentWindow().startDragging(),
  resizeWindow: edge => getCurrentWindow().startResizeDragging({
    n: "North", s: "South", e: "East", w: "West",
    ne: "NorthEast", nw: "NorthWest", se: "SouthEast", sw: "SouthWest",
  }[edge] as Parameters<ReturnType<typeof getCurrentWindow>["startResizeDragging"]>[0]),
  onWindowStateChanged: (listener, onError) => subscribeWindowState(getCurrentWindow(), listener, onError),
  clipboard: {
    clear: () => invoke("clear_clipboard_history"),
    list: () => invoke<string[]>("list_clipboard_history"),
    sync: () => invoke<string[]>("sync_clipboard_history"),
    copy: text => invoke("copy_text", { text }),
  },
  dictionary,
  ...(/\bAndroid\b/i.test(navigator.userAgent) ? { typingStatistics, fuzzyPinyin: true, touchKeyboardSchemes: true, customTouchKeyboardSkins: true, customSkinLibrary: {
    load: () => invoke("load_custom_skin_library"),
    mutate: action => invoke("mutate_custom_skin_library", { action }),
  }, account: {
    appIcon: {
      info: () => invoke("app_icon_info"),
      set: style => invoke("app_icon_set", { style }),
    },
    status: () => invoke("account_status"),
    providers: () => invoke("account_providers"),
    requestCode: (provider, target) => invoke("account_request_code", { provider, target }),
    login: (challengeId, code) => invoke("account_login", { challengeId, code }),
    profile: () => invoke("account_profile"),
    rename: displayName => invoke("account_rename", { displayName }),
    logout: all => invoke("account_logout", { all }),
    deleteAccount: () => invoke("account_delete"),
    clearExpired: () => invoke("account_forget"),
    settingsSync: {
      schema: () => invoke("account_preferences_schema"),
      load: () => invoke("account_preferences_load"),
      upload: () => invoke("account_preferences_upload"),
      apply: (userId, preferences) => invoke("account_preferences_apply", { userId, preferences }),
    },
  }, chat: {
    models: () => invoke("account_chat_models"),
    complete: (messages, model) => invoke<{ content: string }>("account_chat", { messages, model }).then(response => response.content),
  }, home: {
    openKeyboard: () => invoke("open_keyboard_panel"),
    openSystemKeyboardSettings: () => invoke("android_open_input_method_settings"),
    showInputMethodPicker: () => invoke("android_show_input_method_picker"),
  }, communitySkins: {
    list: (offset, search) => invoke<CommunitySkinPage>("community_skin_list", { offset, search }),
    detail: id => invoke<CommunitySkin>("community_skin_detail", { id }),
    download: (id, name) => invoke<CommunitySkinDownload>("community_skin_download", { id, name }),
    rate: (id, stars) => invoke("community_skin_rate", { id, stars }),
    publish: (id, name, description, design) => invoke("community_skin_publish", { id, name, description, design }),
    unpublish: id => invoke("community_skin_unpublish", { id }),
    finishTrial: (id, keep) => invoke("community_skin_finish_trial", { id, keep }),
  }, aiSkins: {
    generate: (requestId, prompt) => invoke<AiSkinProposal[]>("ai_skin_generate", { requestId, prompt }),
    cancel: requestId => invoke("ai_skin_cancel", { requestId }),
    onProgress: listener => listen<{ requestId: string; completed: number }>("ai-skin-progress", event => listener(event.payload)),
  }, communityResources: {
    list: (kind, scope, search, offset) => invoke<CommunityResourcePage>("community_resource_list", { kind, scope, search, offset }),
    detail: id => invoke<CommunityResource>("community_resource_detail", { id }),
    publish: (id, kind, name, description, content, revision) => invoke("community_resource_publish", { id, kind, name, description, content, revision }),
    apply: (id, resourceRevision) => invoke<CommunityResourceApplication>("community_resource_apply", { id, resourceRevision }),
    save: (id, saved) => invoke("community_resource_save", { id, saved }),
    rate: (id, stars) => invoke("community_resource_rate", { id, stars }),
    unpublish: id => invoke("community_resource_unpublish", { id }),
    storeReply: item => invoke("community_resource_store_reply", { item }),
    removeReply: id => invoke("community_resource_remove_reply", { id }),
  }, candidateEnglishGloss: true } : {}),
};
const panelClients: { keyboard: PanelClient; handwriting: PanelClient; voice: VoicePanelClient; cloudClipboard: CloudClipboardPanelClient; cloudDictionary: CloudDictionaryPanelClient; emoji: EmojiPanelClient } = {
  keyboard: {
    beginWindowDrag: () => getCurrentWindow().startDragging(),
    close: () => invoke("close_panel", { label: "keyboard-panel" }),
    openVoice: () => invoke("open_voice_panel"),
    rememberInputTarget: () => invoke("remember_input_target"),
    sendKey: request => invoke("send_key", { request }),
  },
  handwriting: {
    beginWindowDrag: () => getCurrentWindow().startDragging(),
    close: () => invoke("close_panel", { label: "handwriting-panel" }),
    rememberInputTarget: () => invoke("remember_input_target"),
    recognizeHandwriting: request => invoke("recognize_handwriting", { request }),
    submitHandwritingCandidate: candidate => invoke("submit_handwriting_candidate", { candidate }),
    copyHandwritingCandidate: text => invoke("copy_text", { text }),
  },
  voice: {
    maxSubmitBytes: 4096,
    beginWindowDrag: () => getCurrentWindow().startDragging(),
    close: () => invoke("close_panel", { label: "voice-panel" }),
    rememberInputTarget: () => invoke("remember_input_target"),
    loadVoiceLanguage: () => invoke<string>("voice_input_language"),
    ...createVoiceRecognitionClient(invoke, listener => listen<{ request_id: string; text: string; final: boolean; phase?: "recording" | "recognizing" | "polishing"; level?: number }>("voice-update", event => listener(event.payload))),
    sendText: text => invoke("send_text", { text }),
    sendVoiceText: text => invoke("send_voice_text", { text }),
    copyText: text => invoke("copy_text", { text }),
  },
  cloudClipboard: {
    close: () => invoke("close_panel", { label: "cloud-clipboard-panel" }),
    rememberInputTarget: () => invoke("remember_input_target"),
    sendText: text => invoke("send_text", { text }),
    copyText: text => invoke("copy_text", { text }),
    request: (action: CloudClipboardAction) => invoke("cloud_clipboard_request", { action }),
  },
  cloudDictionary: {
    close: () => invoke("close_panel", { label: "cloud-dictionary-panel" }),
    request: (action: CloudDictionaryAction) => invoke("cloud_dictionary_request", { action }),
    ...(/\bAndroid\b/i.test(navigator.userAgent) ? {
      downloadToLocal: async (entry: CloudDictionaryEntry) => {
        if (!dictionary.importPersonal) throw new Error("personal dictionary import is unavailable");
        const text = JSON.stringify({
          format: "msime-personal-dictionary",
          version: 1,
          entries: [{ kind: entry.kind === "quick" ? "quickPhrase" : entry.kind, key: entry.code, value: entry.word, weight: entry.weight }],
        });
        await dictionary.importPersonal(text, `ui-cloud-download-${Date.now()}`);
      },
    } : {}),
    snapshot: /\bAndroid\b/i.test(navigator.userAgent),
  },
  emoji: { close: () => invoke("close_panel", { label: "emoji-panel" }), rememberInputTarget: () => invoke("remember_input_target"), sendText: text => invoke("send_text", { text }), copyText: text => invoke("copy_text", { text }), loadCatalog: () => invoke<{ emoji: EmojiCatalogGroup[]; kaomoji: EmojiCatalogGroup[]; symbols: EmojiCatalogGroup[]; unavailable?: ("emoji" | "kaomoji" | "symbols")[] }>("load_emoji_catalog"), clipboard: {
    list: () => invoke<string[]>("list_clipboard_history"),
    isEnabled: async () => (await client.load()).preferences.clipboard_history ?? false,
    enable: async () => {
      const snapshot = await client.load();
      if (!snapshot.preferences.clipboard_history) {
        await client.save(snapshot.revision, { ...snapshot.preferences, clipboard_history: true });
      }
    },
    onChanged: async listener => {
      const stopHistory = await listen("clipboard-history-changed", () => listener());
      try {
        const stopPreferences = await listen("preferences-changed", () => listener());
        return () => { stopHistory(); stopPreferences(); };
      } catch (error) {
        stopHistory();
        throw error;
      }
    },
    remove: text => invoke("remove_clipboard_history", { text }),
    clear: () => invoke("clear_clipboard_history"),
    sync: () => invoke<string[]>("sync_clipboard_history"),
    copy: text => invoke("copy_text", { text }),
  } },
};
const panel = new URLSearchParams(window.location.search).get("panel");
function DesktopPanelTheme({ preferences, surface, children }: { preferences: Pick<SettingsClient, "load" | "onPreferencesChanged">; surface: "handwriting" | "voice" | "emoji"; children: (theme: "dark" | "light") => ReactNode }) {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  useEffect(() => {
    let active = true;
    let unsubscribe: (() => void) | undefined;
    let latestRevision = -1;
    const apply = (value: Snapshot) => {
      if (!active || value.revision <= latestRevision) return;
      latestRevision = value.revision;
      setSnapshot(value);
    };
    const start = async () => {
      try {
        const stop = await preferences.onPreferencesChanged?.(apply);
        if (!active) { stop?.(); return; }
        unsubscribe = stop;
      } catch { /* Initial loading still works when event subscription is unavailable. */ }
      if (active) {
        try { apply(await preferences.load()); } catch { /* Keep the dark panel default. */ }
      }
    };
    void start();
    return () => { active = false; unsubscribe?.(); };
  }, [preferences]);
  const surfaceTheme = surface === "handwriting" ? snapshot?.preferences.handwriting_theme : surface === "voice" ? snapshot?.preferences.voice_theme : snapshot?.preferences.emoji_theme;
  return children(useCandidatePreviewTheme(snapshot?.preferences.theme, surfaceTheme));
}
// The host reports what it supports. Typing statistics were previously gated on
// an Android user-agent match, which left the category dead on every desktop
// even though the commands were registered.
async function discoverHostCapabilities(): Promise<HostCapabilities | null> {
  if (!isTauri()) return null;
  try {
    return await invoke<HostCapabilities>("host_capabilities");
  } catch {
    return null; // A host without the command keeps its previous behaviour.
  }
}

function DesktopSettings() {
  const [settingsClient, setSettingsClient] = useState<SettingsClient | null>(null);
  const [bootstrapRequired, setBootstrapRequired] = useState<boolean | null>(null);
  const [mobilePanel, setMobilePanel] = useState<"cloud-clipboard" | "cloud-dictionary" | "cloud-dictionary-catalog" | "cloud-candidates" | null>(null);
  // The host menu entry that started this window names a section; resolve it
  // before mounting so the page never opens on one and then jumps.
  const [initialPage, setInitialPage] = useState<string | undefined>();
  useEffect(() => {
    let active = true;
    let unsubscribe: (() => void) | undefined;
    if (isTauri()) {
      void listen<string>("settings-route", event => {
        if (active) setInitialPage(event.payload || undefined);
      }).then(stop => {
        if (active) unsubscribe = stop;
        else stop();
      }).catch(() => {});
    }
    const requested = isTauri()
      ? invoke<string | null>("initial_settings_page").catch(() => null)
      : Promise.resolve(null);
    void Promise.all([discoverFontReader(isTauri(), invoke), requested, discoverHostCapabilities()]).then(async ([reader, page, host]) => {
      if (!active) return;
      const android = host?.platform === "android";
      const ready = !android || await invoke<boolean>("android_bootstrap_status").catch(() => false);
      if (!active) return;
      setBootstrapRequired(android && !ready);
      setInitialPage(page ?? undefined);
      const hosted: SettingsClient = host
        ? { ...client, host, ...(host.typing_statistics ? { typingStatistics } : {}), ...(host.fuzzy_pinyin ? { fuzzyPinyin: true } : {}) }
        : client;
      const mobileHosted = host?.platform === "android"
        ? {
          ...hosted,
          openCloudClipboard: async () => setMobilePanel("cloud-clipboard"),
          openCloudDictionary: async () => setMobilePanel("cloud-dictionary"),
        }
        : hosted;
      setSettingsClient(reader ? { ...mobileHosted, listFontFamilies: reader } : mobileHosted);
    });
    return () => { active = false; unsubscribe?.(); };
  }, []);
  const onboardingActions: OnboardingActions = {
    prepareResources: () => invoke("android_prepare_bootstrap").then(() => undefined),
    openSystemKeyboardSettings: () => invoke("android_open_input_method_settings").then(() => undefined),
    showInputMethodPicker: () => invoke("android_show_input_method_picker").then(() => undefined),
  };
  const completeOnboarding = async (scheme: OnboardingInputScheme) => {
    const snapshot = await client.load();
    const enabled = [...(snapshot.preferences.touch_keyboard_schemes?.enabled ?? [])];
    if (!enabled.includes(scheme)) enabled.push(scheme);
    await client.save(snapshot.revision, {
      ...snapshot.preferences,
      scheme: "quanpin",
      last_chinese_scheme: "quanpin",
      touch_keyboard_layout: scheme === "nine_key" ? "nine_key" : "twenty_six_key",
      touch_keyboard_schemes: {
        ...snapshot.preferences.touch_keyboard_schemes,
        enabled,
        selected: scheme,
      },
    });
    setBootstrapRequired(false);
  };
  // Mount once after discovery: replacing the client later would reload draft preferences.
  if (bootstrapRequired) return <WelcomeFlowPage actions={onboardingActions} onComplete={completeOnboarding} />;
  if (!settingsClient) return <p role="status">正在连接设置…</p>;
  if (mobilePanel === "cloud-clipboard") {
    return <CloudClipboardPanel client={{
      ...panelClients.cloudClipboard,
      rememberInputTarget: undefined,
      sendText: undefined,
      close: async () => setMobilePanel(null),
    }} />;
  }
  if (mobilePanel === "cloud-dictionary") {
    return <CloudDictionaryPanel client={{
      ...panelClients.cloudDictionary,
      openCatalog: async () => setMobilePanel("cloud-dictionary-catalog"),
      openCandidates: async () => setMobilePanel("cloud-candidates"),
      close: async () => setMobilePanel(null),
    }} />;
  }
  if (mobilePanel === "cloud-dictionary-catalog") {
    return <CloudDictionaryCatalogPanel client={{
      ...panelClients.cloudDictionary,
      back: async () => setMobilePanel("cloud-dictionary"),
      close: async () => setMobilePanel(null),
    }} />;
  }
  if (mobilePanel === "cloud-candidates") {
    return <CloudCandidatesPanel client={{
      ...panelClients.cloudDictionary,
      back: async () => setMobilePanel("cloud-dictionary"),
      close: async () => setMobilePanel(null),
    }} />;
  }
  return <SettingsPage key={initialPage ?? "default"} client={settingsClient} initialPage={initialPage} />
}
function DesktopEmojiPanel({ theme, initialPage = "home" }: { theme: "dark" | "light"; initialPage?: "home" | "clipboard" }) {
  const [emojiClient, setEmojiClient] = useState<EmojiPanelClient | null>(null);
  useEffect(() => {
    let active = true;
    const capability = isTauri()
      ? invoke<boolean>("supports_clipboard_paste").catch(() => false)
      : Promise.resolve(false);
    void capability.then(supported => {
      if (!active) return;
      setEmojiClient(supported ? {
        ...panelClients.emoji,
        clipboard: {
          ...panelClients.emoji.clipboard,
          paste: text => invoke<void>("paste_clipboard_text", { text }),
        },
      } : panelClients.emoji);
    });
    return () => { active = false; };
  }, []);
  return emojiClient ? <EmojiPanel client={emojiClient} theme={theme} initialPage={initialPage} />
    : <p role="status">正在连接面板…</p>;
}

const content = panel === "keyboard" ? <DesktopKeyboard client={panelClients.keyboard} preferences={client} />
  : panel === "handwriting" ? <DesktopPanelTheme preferences={client} surface="handwriting">{theme => <HandwritingPanel client={panelClients.handwriting} theme={theme} />}</DesktopPanelTheme>
  : panel === "voice" ? <DesktopPanelTheme preferences={client} surface="voice">{theme => <VoicePanel client={panelClients.voice} theme={theme} />}</DesktopPanelTheme>
  : panel === "cloud-clipboard" ? <CloudClipboardPanel client={panelClients.cloudClipboard} />
  : panel === "cloud-dictionary" ? <CloudDictionaryPanel client={panelClients.cloudDictionary} />
  : panel === "clipboard" ? <DesktopPanelTheme preferences={client} surface="emoji">{theme => <DesktopEmojiPanel theme={theme} initialPage="clipboard" />}</DesktopPanelTheme>
  : panel === "emoji" ? <DesktopPanelTheme preferences={client} surface="emoji">{theme => <DesktopEmojiPanel theme={theme} />}</DesktopPanelTheme>
  : <DesktopSettings />;
createRoot(document.getElementById("root")!).render(<StrictMode>{content}</StrictMode>);
