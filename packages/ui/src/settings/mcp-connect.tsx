import { useCallback, useEffect, useState } from "react";
import { useConfirm } from "../core/confirm";
import * as settings from "./settings-style";

/** The assistants the host can write the entry for. */
export type McpClientId = "claude_desktop" | "cursor";

export type McpClientStatus = {
  id: McpClientId;
  /** The assistant's configuration file. */
  path: string;
  /** The file already holds exactly this entry. */
  configured: boolean;
};

export type McpServerStatus = {
  /** The absolute path of `msime-mcp` beside the settings app. */
  command: string;
  /** Whether that file exists. */
  installed: boolean;
  /** The runtime options the entry points at; absent before the input method is set up. */
  options: string | null;
  /** `{"mcpServers": {"msime": ...}}` to paste into any assistant. */
  config: string | null;
  clients: McpClientStatus[];
};

export type McpInstallOutcome = "added" | "replaced" | "unchanged";

const clientNames: Record<McpClientId, string> = {
  claude_desktop: "Claude Desktop",
  cursor: "Cursor",
};

const code =
  "m-0 overflow-x-auto rounded-lg border border-edge bg-raised p-3 text-xs leading-relaxed";

function errorCode(error: unknown): string | undefined {
  return typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : undefined;
}

function failure(error: unknown, name: string): string {
  switch (errorCode(error)) {
    case "mcp_client_missing":
      return `没有找到 ${name} 的配置目录。请先安装并打开一次 ${name}。`;
    case "mcp_config_invalid":
      return `${name} 的配置文件不是有效的 JSON，已保持原样。请先修正该文件。`;
    case "mcp_server_missing":
      return "没有找到 msime-mcp，请重新安装输入法。";
    case "mcp_options_missing":
      return "输入法尚未完成初始化，请先完成设置向导。";
  }
  return `无法写入 ${name} 的配置文件。`;
}

/**
 * 「连接 AI 助手」: the `msime-mcp` entry an assistant runs, to copy or to write into Claude Desktop's or Cursor's configuration.
 *
 * The callbacks are passed in rather than read from the settings client so that the page decides, at the call site in `index.tsx`, which of them a host offers; that is where the settings action guard looks.
 */
export function McpConnectSection({
  status,
  install,
  copyText,
}: {
  status: () => Promise<McpServerStatus>;
  install?: (client: McpClientId, replace: boolean) => Promise<McpInstallOutcome>;
  copyText?: (text: string) => Promise<void>;
}) {
  const { confirm, confirmation } = useConfirm();
  const [server, setServer] = useState<McpServerStatus>();
  const [loadFailed, setLoadFailed] = useState(false);
  const [busy, setBusy] = useState<McpClientId>();
  const [result, setResult] = useState<string>();
  const [copied, setCopied] = useState(false);

  const refresh = useCallback(
    () =>
      status().then(
        (next) => {
          setServer(next);
          setLoadFailed(false);
        },
        () => setLoadFailed(true),
      ),
    [status],
  );

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function write(id: McpClientId) {
    if (!install) return;
    const name = clientNames[id];
    setBusy(id);
    setResult(undefined);
    try {
      let outcome: McpInstallOutcome;
      try {
        outcome = await install(id, false);
      } catch (error) {
        if (errorCode(error) !== "mcp_entry_exists") throw error;
        const replace = await confirm({
          title: `替换 ${name} 中的 msime？`,
          message: `${name} 的配置里已有另一个名为 msime 的服务器。替换后，它原来的命令和参数（包括手动加上的 --allow-write）会被这里的设置覆盖。`,
          confirmLabel: "替换",
        });
        if (!replace) return;
        outcome = await install(id, true);
      }
      setResult(
        outcome === "unchanged"
          ? `${name} 已经连接，无需改动。`
          : `已写入 ${name} 的配置。重新启动 ${name} 后生效。`,
      );
      await refresh();
    } catch (error) {
      setResult(failure(error, name));
    } finally {
      setBusy(undefined);
    }
  }

  return (
    <div className="section" role="group" aria-label="连接 AI 助手">
      <div className="section-header">
        <span className="section-title">
          连接 AI 助手
          <small>
            通过 MCP（Model Context Protocol）让本机的 AI
            助手读取快捷短语、设置和打字统计。服务器只在本机运行，不联网；默认只读。
          </small>
        </span>
      </div>
      {loadFailed && <p role="alert">无法读取 MCP 服务器的状态。</p>}
      {server && (
        <>
          <div className={settings.serviceRow}>
            <span>
              服务器程序
              <small>
                <code>{server.command}</code>
                {server.installed ? "" : "（未找到，请重新安装输入法）"}
              </small>
            </span>
          </div>
          {server.config ? (
            <>
              <pre className={code} aria-label="MCP 配置">
                {server.config}
              </pre>
              <p className="notice">
                要让助手修改快捷短语和设置，在 args 中加入 <code>--allow-write</code>
                ；要让它读取你的用户词库、查看编码的候选，加入 <code>--allow-dictionary-read</code>
                ；两项都加才能增删、调整和导入词。这两项只应在你信任该助手时开启。
              </p>
              {copyText && (
                <div className={settings.serviceRow}>
                  <span>复制后粘贴到任意支持 MCP 的助手的配置中</span>
                  <div>
                    <button
                      type="button"
                      className="secondary"
                      onClick={() =>
                        void copyText(server.config!).then(() => {
                          setCopied(true);
                          window.setTimeout(() => setCopied(false), 1600);
                        })
                      }
                    >
                      {copied ? "已复制" : "复制配置"}
                    </button>
                  </div>
                </div>
              )}
              {install &&
                server.installed &&
                server.clients.map((client) => (
                  <div className={settings.serviceRow} key={client.id}>
                    <span>
                      {clientNames[client.id]}
                      <small>
                        <code>{client.path}</code>
                        {client.configured ? "（已连接）" : ""}
                      </small>
                    </span>
                    <div>
                      <button
                        type="button"
                        className="secondary"
                        disabled={busy !== undefined || client.configured}
                        aria-busy={busy === client.id}
                        onClick={() => void write(client.id)}
                      >
                        {busy === client.id ? "正在写入…" : `写入 ${clientNames[client.id]}`}
                      </button>
                    </div>
                  </div>
                ))}
            </>
          ) : (
            <p className="notice">输入法尚未完成初始化，完成设置向导后即可连接。</p>
          )}
          {result && <p role="status">{result}</p>}
        </>
      )}
      {confirmation}
    </div>
  );
}
