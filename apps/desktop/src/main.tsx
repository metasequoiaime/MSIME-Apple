import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { invoke, isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { CloudClipboardPanel, CloudDictionaryPanel, EmojiPanel, HandwritingPanel, KeyboardPanel, VoicePanel, SettingsPage, type CloudClipboardAction, type CloudClipboardPanelClient, type CloudDictionaryAction, type CloudDictionaryPanelClient, type EmojiCatalogGroup, type EmojiPanelClient, type PanelClient, type VoicePanelClient, type SettingsClient, type Snapshot, type DictionaryClient, type DictionaryEntry, type LocalDictionaryKind, type LocalDictionaryFormat } from "@msime/ui";
import "@msime/ui/styles.css";
import { subscribeWindowState } from "./window-state";
import { discoverFontReader } from "./system-font-client";
import { DesktopKeyboard } from "./desktop-keyboard";

const dictionary: DictionaryClient = {
  list: (offset, limit) => invoke("dictionary_request", { action: { operation: "list", offset, limit } }),
  edit: (previous: DictionaryEntry | null, replacement: DictionaryEntry | null, request_id: string) => invoke("dictionary_request", { action: { operation: "edit", previous, replacement, request_id } }).then(() => undefined),
  import: (kind: LocalDictionaryKind, format: LocalDictionaryFormat, text: string, request_id: string) => invoke("dictionary_request", { action: { operation: "import", kind, format, text, request_id } }),
  export: (kind: LocalDictionaryKind, format: Exclude<LocalDictionaryFormat, "rime" | "hans">, offset: number, limit: number) => invoke("dictionary_request", { action: { operation: "export", kind, format, offset, limit } }),
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
  openVoice: () => invoke("open_voice_panel"),
  openCloudClipboard: () => invoke("open_cloud_clipboard_panel"),
  openCloudDictionary: () => invoke("open_cloud_dictionary_panel"),
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
};
const panelClients: { keyboard: PanelClient; handwriting: PanelClient; voice: VoicePanelClient; cloudClipboard: CloudClipboardPanelClient; cloudDictionary: CloudDictionaryPanelClient; emoji: EmojiPanelClient } = {
  keyboard: {
    beginWindowDrag: () => getCurrentWindow().startDragging(),
    close: () => invoke("close_panel", { label: "keyboard-panel" }),
    rememberInputTarget: () => invoke("remember_input_target"),
    sendKey: request => invoke("send_key", { request }),
  },
  handwriting: {
    close: () => invoke("close_panel", { label: "handwriting-panel" }),
    rememberInputTarget: () => invoke("remember_input_target"),
    recognizeHandwriting: request => invoke("recognize_handwriting", { request }),
    submitHandwritingCandidate: candidate => invoke("submit_handwriting_candidate", { candidate }),
  },
  voice: {
    close: () => invoke("close_panel", { label: "voice-panel" }),
    rememberInputTarget: () => invoke("remember_input_target"),
    loadVoiceLanguage: () => invoke<string>("voice_input_language"),
    recognizeVoice: language => invoke<{ text: string }>("recognize_voice", { request: { language } }),
    onVoiceUpdate: listener => listen<{ text: string; final: boolean }>("voice-update", event => listener(event.payload)),
    cancelVoice: () => invoke("cancel_voice"),
    sendText: text => invoke("send_text", { text }),
    sendVoiceText: text => invoke("send_voice_text", { text }),
  },
  cloudClipboard: {
    close: () => invoke("close_panel", { label: "cloud-clipboard-panel" }),
    rememberInputTarget: () => invoke("remember_input_target"),
    sendText: text => invoke("send_text", { text }),
    request: (action: CloudClipboardAction) => invoke("cloud_clipboard_request", { action }),
  },
  cloudDictionary: {
    close: () => invoke("close_panel", { label: "cloud-dictionary-panel" }),
    request: (action: CloudDictionaryAction) => invoke("cloud_dictionary_request", { action }),
  },
  emoji: { close: () => invoke("close_panel", { label: "emoji-panel" }), rememberInputTarget: () => invoke("remember_input_target"), sendText: text => invoke("send_text", { text }), copyText: text => invoke("copy_text", { text }), loadCatalog: () => invoke<{ emoji: EmojiCatalogGroup[]; kaomoji: EmojiCatalogGroup[]; symbols: EmojiCatalogGroup[] }>("load_emoji_catalog"), clipboard: {
    list: () => invoke<string[]>("list_clipboard_history"),
    sync: () => invoke<string[]>("sync_clipboard_history"),
    copy: text => invoke("copy_text", { text }),
  } },
};
const panel = new URLSearchParams(window.location.search).get("panel");
function DesktopSettings() {
  const [settingsClient, setSettingsClient] = useState<SettingsClient | null>(null);
  useEffect(() => {
    let active = true;
    void discoverFontReader(isTauri(), invoke).then(reader => {
      if (active) setSettingsClient(reader ? { ...client, listFontFamilies: reader } : client);
    });
    return () => { active = false; };
  }, []);
  // Mount once after discovery: replacing the client later would reload draft preferences.
  return settingsClient ? <SettingsPage client={settingsClient} /> : <p role="status">正在连接设置…</p>;
}
const content = panel === "keyboard" ? <DesktopKeyboard client={panelClients.keyboard} preferences={client} />
  : panel === "handwriting" ? <HandwritingPanel client={panelClients.handwriting} />
  : panel === "voice" ? <VoicePanel client={panelClients.voice} />
  : panel === "cloud-clipboard" ? <CloudClipboardPanel client={panelClients.cloudClipboard} />
  : panel === "cloud-dictionary" ? <CloudDictionaryPanel client={panelClients.cloudDictionary} />
  : panel === "emoji" ? <EmojiPanel client={panelClients.emoji} />
  : <DesktopSettings />;
createRoot(document.getElementById("root")!).render(<StrictMode>{content}</StrictMode>);
