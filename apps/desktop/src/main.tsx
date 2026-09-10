import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { invoke, isTauri } from "@tauri-apps/api/core";
import { SettingsPage, type SettingsClient, type Snapshot, type DictionaryClient, type DictionaryEntry } from "@msime/ui";
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
  dictionary,
};
createRoot(document.getElementById("root")!).render(<StrictMode><SettingsPage client={client} /></StrictMode>);
