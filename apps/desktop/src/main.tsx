import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { invoke, isTauri } from "@tauri-apps/api/core";
import { SettingsPage, type SettingsClient, type Snapshot } from "@msime/ui";
import "@msime/ui/styles.css";

const client: SettingsClient = {
  load: () => {
    if (!isTauri()) return Promise.reject(new Error("请通过客户端应用打开设置。浏览器预览不会写入本地配置。"));
    return invoke<Snapshot>("load_preferences");
  },
  save: (expectedRevision, preferences) => invoke<Snapshot>("save_preferences", { expectedRevision, preferences }),
};
createRoot(document.getElementById("root")!).render(<StrictMode><SettingsPage client={client} /></StrictMode>);
