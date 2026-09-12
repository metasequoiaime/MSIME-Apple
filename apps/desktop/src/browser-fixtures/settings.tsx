// Synthetic, in-memory settings only. No native bridge or real user data.
import { createRoot } from "react-dom/client";
import { SettingsPage, type Snapshot } from "@msime/ui";
import "../../../../packages/ui/src/styles.css";

export function mount() {
  const snapshot: Snapshot = { format_version: 1, revision: 1, preferences: {
    scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 6,
    learning: true, chinese_punctuation: true,
  } };
  const root = createRoot(document.getElementById("root")!);
  root.render(<SettingsPage client={{ load: async () => snapshot, save: async (_revision, preferences) => ({ ...snapshot, preferences }) }} />);
  return () => root.unmount();
}
