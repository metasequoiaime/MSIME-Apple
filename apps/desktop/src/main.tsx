import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { invoke, isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { EmojiPanel, HandwritingPanel, KeyboardPanel, SettingsPage, type EmojiCatalogGroup, type EmojiPanelClient, type PanelClient, type SettingsClient, type Snapshot, type DictionaryClient, type DictionaryEntry } from "@msime/ui";
import "@msime/ui/styles.css";

const dictionary: DictionaryClient = {
  list: (offset, limit) => invoke("dictionary_request", { action: { operation: "list", offset, limit } }),
  edit: (previous: DictionaryEntry | null, replacement: DictionaryEntry | null, request_id: string) => invoke("dictionary_request", { action: { operation: "edit", previous, replacement, request_id } }).then(() => undefined),
};
const client: SettingsClient = {
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
  windowControl: async action => {
    const window = getCurrentWindow();
    if (action === "minimize") return window.minimize();
    if (action === "close") return window.close();
    if (action === "restore") return window.unmaximize();
    return window.maximize();
  },
  beginWindowDrag: () => getCurrentWindow().startDragging(),
  onWindowStateChanged: async listener => {
    const window = getCurrentWindow();
    listener(await window.isMaximized());
    const unlisten = await window.onResized(async () => listener(await window.isMaximized()));
    return unlisten;
  },
  clipboard: {
    clear: () => invoke("clear_clipboard_history"),
    list: () => invoke<string[]>("list_clipboard_history"),
    sync: () => invoke<string[]>("sync_clipboard_history"),
    copy: text => invoke("copy_text", { text }),
  },
  dictionary,
};
const panelClients: { keyboard: PanelClient; handwriting: PanelClient; emoji: EmojiPanelClient } = {
  keyboard: {
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
  emoji: { close: () => invoke("close_panel", { label: "emoji-panel" }), rememberInputTarget: () => invoke("remember_input_target"), sendText: text => invoke("send_text", { text }), copyText: text => invoke("copy_text", { text }), loadCatalog: () => invoke<{ emoji: EmojiCatalogGroup[]; kaomoji: EmojiCatalogGroup[]; symbols: EmojiCatalogGroup[] }>("load_emoji_catalog"), clipboard: {
    list: () => invoke<string[]>("list_clipboard_history"),
    sync: () => invoke<string[]>("sync_clipboard_history"),
    copy: text => invoke("copy_text", { text }),
  } },
};
const panel = new URLSearchParams(window.location.search).get("panel");
const content = panel === "keyboard" ? <KeyboardPanel client={panelClients.keyboard} />
  : panel === "handwriting" ? <HandwritingPanel client={panelClients.handwriting} />
  : panel === "emoji" ? <EmojiPanel client={panelClients.emoji} />
  : <SettingsPage client={client} />;
createRoot(document.getElementById("root")!).render(<StrictMode>{content}</StrictMode>);
