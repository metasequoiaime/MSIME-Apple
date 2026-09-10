import { useEffect, useState } from "react";

export type Preferences = {
  scheme: "quanpin" | "shuangpin" | "wubi" | "japanese";
  shuangpin_profile: "xiaohe" | "ziranma" | "shoudao" | "microsoft";
  candidate_page_size: number;
  learning: boolean;
  autocorrect?: boolean;
  chinese_punctuation: boolean;
};
export type Snapshot = { format_version: number; revision: number; preferences: Preferences };
export interface SettingsClient {
  load(): Promise<Snapshot>;
  save(revision: number, preferences: Preferences): Promise<Snapshot>;
}

function message(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "object" && error !== null && "code" in error) {
    switch (error.code) {
      case "conflict": return "设置已在其他窗口修改。请重新读取后再保存。";
      case "invalid": return "候选数量必须为 1 到 9。";
      case "format": return "配置文件无法读取或版本较新，原文件已保留。";
    }
  }
  return "无法访问设置，请重试。原有设置不会被自动重置。";
}

export function SettingsPage({ client }: { client: SettingsClient }) {
  const [snapshot, setSnapshot] = useState<Snapshot>();
  const [draft, setDraft] = useState<Preferences>();
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  useEffect(() => {
    let active = true;
    client.load().then(value => {
      if (active) { setSnapshot(value); setDraft(value.preferences); }
    }).catch(reason => { if (active) setError(message(reason)); })
      .finally(() => { if (active) setBusy(false); });
    return () => { active = false; };
  }, [client]);

  async function reload() {
    setBusy(true); setError(""); setNotice("");
    try {
      const value = await client.load();
      setSnapshot(value); setDraft(value.preferences);
    } catch (reason) { setError(message(reason)); }
    finally { setBusy(false); }
  }

  async function save() {
    if (!draft || !snapshot) return;
    setBusy(true); setError(""); setNotice("");
    try {
      const value = await client.save(snapshot.revision, draft);
      setSnapshot(value); setDraft(value.preferences); setNotice("设置已保存。");
    } catch (reason) { setError(message(reason)); }
    finally { setBusy(false); }
  }

  const dirty = !!draft && !!snapshot && JSON.stringify(draft) !== JSON.stringify(snapshot.preferences);
  return <main className="settings">
    <header><span className="brand">水杉输入法</span><h1>输入设置</h1>
      <p>设置你的输入习惯。</p></header>
    <aside>预览版：设置供 MSIME Client 宿主使用，已接入的宿主会在组词结束后应用；不影响旧版输入法。</aside>
    {error && <p role="alert" className="error">{error}</p>}
    {notice && <p role="status" className="notice">{notice}</p>}
    {busy && !draft && <p role="status">正在读取设置…</p>}
    {draft && <form onSubmit={event => { event.preventDefault(); void save(); }}>
      <fieldset disabled={busy}>
        <legend>输入与候选</legend>
        <label>输入方案<select value={draft.scheme} onChange={event => setDraft({ ...draft, scheme: event.target.value as Preferences["scheme"] })}>
          <option value="quanpin">全拼</option><option value="shuangpin">双拼</option>
          <option value="wubi">五笔</option><option value="japanese">日语</option>
        </select></label>
        <label>双拼方案<select disabled={draft.scheme !== "shuangpin"} value={draft.shuangpin_profile} onChange={event => setDraft({ ...draft, shuangpin_profile: event.target.value as Preferences["shuangpin_profile"] })}>
          <option value="xiaohe">小鹤双拼</option><option value="ziranma">自然码双拼</option>
          <option value="shoudao">首道双拼</option><option value="microsoft">微软双拼</option>
        </select></label>
        <label>每页候选数量<select value={draft.candidate_page_size} onChange={event => setDraft({ ...draft, candidate_page_size: Number(event.target.value) })}>
          {Array.from({ length: 9 }, (_, index) => index + 1).map(size => <option key={size} value={size}>{size}</option>)}
        </select></label>
        <label className="toggle"><span>全拼纠错<small>自动纠正常见拼音输入错误</small></span><input type="checkbox" checked={draft.autocorrect ?? true} onChange={event => setDraft({ ...draft, autocorrect: event.target.checked })} /></label>
        <label className="toggle"><span>学习选词习惯<small>根据选词调整候选顺序</small></span><input type="checkbox" checked={draft.learning} onChange={event => setDraft({ ...draft, learning: event.target.checked })} /></label>
        <label className="toggle"><span>中文标点<small>默认使用中文标点符号</small></span><input type="checkbox" checked={draft.chinese_punctuation} onChange={event => setDraft({ ...draft, chinese_punctuation: event.target.checked })} /></label>
      </fieldset>
      <footer><button type="submit" disabled={busy || !dirty}>{busy ? "处理中…" : "保存设置"}</button></footer>
    </form>}
    <button className="secondary" disabled={busy} onClick={() => {
      if (!dirty || window.confirm("重新读取会放弃尚未保存的修改，是否继续？")) void reload();
    }}>重新读取</button>
  </main>;
}
