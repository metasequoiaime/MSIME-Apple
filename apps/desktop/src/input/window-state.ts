/** Keep native window state ordered without exposing the host to shared UI. */
export interface WindowStateSource {
  isMaximized(): Promise<boolean>;
  onResized(listener: () => void): Promise<() => void>;
}

export async function subscribeWindowState(
  source: WindowStateSource,
  listener: (maximized: boolean) => void,
  onError: () => void = () => {},
): Promise<() => void> {
  let active = true;
  let generation = 0;
  async function refresh(initial = false) {
    if (!active) return;
    const request = ++generation;
    try {
      const maximized = await source.isMaximized();
      if (active && request === generation) listener(maximized);
    } catch (error) {
      if (!active || request !== generation) return;
      if (initial) throw error;
      onError();
    }
  }

  // Listen before reading: otherwise a maximize between the read and listener
  // registration can leave the titlebar displaying the wrong action indefinitely.
  let unlisten: () => void;
  try {
    unlisten = await source.onResized(() => { void refresh(); });
  } catch (error) {
    active = false;
    throw error;
  }
  const dispose = () => {
    if (!active) return;
    active = false;
    ++generation;
    unlisten();
  };
  try {
    await refresh(true);
    return dispose;
  } catch (error) {
    dispose();
    throw error;
  }
}
