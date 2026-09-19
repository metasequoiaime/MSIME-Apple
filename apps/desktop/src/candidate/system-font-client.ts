type Invoke = <T>(command: string) => Promise<T>;

// Ask the compiled host, not user-agent heuristics. Enumeration stays lazy.
export async function discoverFontReader(native: boolean, invoke: Invoke) {
  if (!native) return undefined;
  try {
    if (await invoke<boolean>("supports_font_catalog") !== true) return undefined;
    return () => invoke<string[]>("list_font_families");
  } catch {
    // Older/unsupported hosts retain manual entry.
    return undefined;
  }
}
