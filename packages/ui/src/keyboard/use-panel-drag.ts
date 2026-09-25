import { useEffect, useRef, type HTMLAttributes } from "react";

export function usePanelDrag(
  client: { beginWindowDrag?(): Promise<void> },
  onFailure: () => void,
): HTMLAttributes<HTMLElement> {
  const pendingDrag = useRef<{ id: number; x: number; y: number } | null>(null);
  const mounted = useRef(true);
  const reset = () => {
    pendingDrag.current = null;
  };
  useEffect(() => {
    mounted.current = true;
    window.addEventListener("blur", reset);
    return () => {
      mounted.current = false;
      reset();
      window.removeEventListener("blur", reset);
    };
  }, [client]);
  return {
    onPointerDown(event) {
      reset();
      if (
        !client.beginWindowDrag ||
        event.button !== 0 ||
        (event.target as Element).closest("button")
      )
        return;
      pendingDrag.current = { id: event.pointerId, x: event.clientX, y: event.clientY };
    },
    onPointerMove(event) {
      const pending = pendingDrag.current;
      if (!pending || pending.id !== event.pointerId) return;
      if (event.buttons !== 1) {
        reset();
        return;
      }
      if (Math.abs(event.clientX - pending.x) + Math.abs(event.clientY - pending.y) < 2) return;
      reset();
      void (async () => {
        try {
          await client.beginWindowDrag?.();
        } catch {
          if (mounted.current) onFailure();
        }
      })();
    },
    onPointerUp: reset,
    onPointerCancel: reset,
    onPointerLeave: reset,
  };
}
