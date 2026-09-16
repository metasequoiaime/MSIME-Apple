import { useState } from "react";
import { CloudCandidatesPanel, CloudDictionaryCatalogPanel, CloudDictionaryFilesPanel, CloudDictionaryPanel, type CloudDictionaryPanelClient } from "@msime/ui";

// Keep all subpages in the authenticated dictionary webview. Opening another
// window would lose the native account session's label-bound authorization.
export function DesktopCloudDictionary({ client }: { client: CloudDictionaryPanelClient }) {
  const [page, setPage] = useState<"dictionary" | "catalog" | "candidates" | "files">("dictionary");
  if (page === "catalog") return <CloudDictionaryCatalogPanel client={{ ...client, back: async () => setPage("dictionary") }} />;
  if (page === "candidates") return <CloudCandidatesPanel client={{ ...client, back: async () => setPage("dictionary") }} />;
  if (page === "files") return <CloudDictionaryFilesPanel client={{ ...client, back: async () => setPage("dictionary") }} />;
  return <CloudDictionaryPanel client={{ ...client, openCatalog: async () => setPage("catalog"), openCandidates: async () => setPage("candidates"), openFiles: async () => setPage("files") }} />;
}
