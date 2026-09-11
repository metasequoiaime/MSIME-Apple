/** Versioned window bridge shared by WebView2 and Tauri settings hosts. */
export type WindowControl = "minimize" | "maximize" | "restore" | "close";
export type WindowResizeEdge = "n" | "s" | "e" | "w" | "ne" | "nw" | "se" | "sw";
export type WindowHostMessage =
  | { type: "windowControl"; data: WindowControl }
  | { type: "resizeWindow"; data: { edge: WindowResizeEdge; dpr: number } }
  | { type: "windowState"; data: { isMaximized: boolean } };

export function serializeWindowHostMessage(message: WindowHostMessage): string {
  return JSON.stringify({ version: 1, ...message });
}
