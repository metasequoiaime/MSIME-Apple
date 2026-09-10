import { useRef, useState } from "react";

/** Host failures may contain private paths or data; display only fixed UI messages. */
export function HostActionButton({ action, label, success }: {
  action?: () => Promise<void>;
  label: string;
  success?: string;
}) {
  const running = useRef(false);
  const [pending, setPending] = useState(false);
  const [result, setResult] = useState<"success" | "error" | null>(null);
  async function run() {
    if (!action || running.current) return;
    running.current = true;
    setPending(true);
    setResult(null);
    try {
      await action();
      setResult("success");
    } catch {
      setResult("error");
    } finally {
      running.current = false;
      setPending(false);
    }
  }
  return <div>
    <button type="button" className="secondary" disabled={!action || pending} aria-label={label} aria-busy={pending} onClick={() => void run()}>{pending ? "处理中…" : label}</button>
    {result === "success" && success && <span role="status">{success}</span>}
    {result === "error" && <span role="alert">操作失败，请重试。</span>}
  </div>;
}
