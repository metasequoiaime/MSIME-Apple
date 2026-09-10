import { useRef, useState } from "react";

/** Host failures may contain private paths or data; display only fixed UI messages. */
export function HostActionButton({ action, label, success, error }: {
  action?: () => Promise<void>;
  label: string;
  success?: string;
  error?: string;
}) {
  const running = useRef(false);
  const [pending, setPending] = useState(false);
  const [result, setResult] = useState<"success" | "error" | null>(null);
  const [errorMessage, setErrorMessage] = useState("操作失败，请重试。");
  async function run() {
    if (!action || running.current) return;
    running.current = true;
    setPending(true);
    setResult(null);
    try {
      await action();
      setResult("success");
    } catch (reason) {
      const code = typeof reason === "object" && reason !== null && "code" in reason ? reason.code : undefined;
      setErrorMessage(code === "unknown_skin" ? "找不到该外部皮肤，请先刷新皮肤目录。" : code === "invalid_skin" ? "皮肤标识无效，未执行应用。" : error ?? "操作失败，请重试。");
      setResult("error");
    } finally {
      running.current = false;
      setPending(false);
    }
  }
  return <div>
    <button type="button" className="secondary" disabled={!action || pending} aria-label={label} aria-busy={pending} onClick={() => void run()}>{pending ? "处理中…" : label}</button>
    {result === "success" && success && <span role="status">{success}</span>}
    {result === "error" && <span role="alert">{errorMessage}</span>}
  </div>;
}
