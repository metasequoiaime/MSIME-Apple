import { useEffect, useState } from "react";

export type HelpcodeSchema = "lantian" | "ziranma" | "shouyou2_0" | "shouyouplus" | "xiaohe";
export type HelpcodePreferences = { enabled: boolean; schema: HelpcodeSchema };
const defaultHelpcode: HelpcodePreferences = { enabled: true, schema: "ziranma" };
const helpcodeSchemas: [HelpcodeSchema, string][] = [["lantian", "蓝天小雨点"], ["ziranma", "自然码"], ["shouyou2_0", "首右2.0"], ["shouyouplus", "首右plus"], ["xiaohe", "小鹤"]];
const pages = [
  { id: "appearance", title: "外观", icon: new URL("./assets/appearance.svg", import.meta.url).href },
  { id: "input", title: "输入", icon: new URL("./assets/input.svg", import.meta.url).href },
  { id: "helpcode", title: "辅助码", icon: new URL("./assets/helpcode.svg", import.meta.url).href },
] as const;
const logo = new URL("./assets/msime.svg", import.meta.url).href;

export type Preferences = {
  scheme: "quanpin" | "shuangpin" | "wubi" | "japanese";
  shuangpin_profile: "xiaohe" | "ziranma" | "shoudao" | "microsoft";
  candidate_page_size: number;
  learning: boolean;
  autocorrect?: boolean;
  quanpin_helpcode?: HelpcodePreferences;
  shuangpin_helpcode?: HelpcodePreferences;
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
  const [page, setPage] = useState<(typeof pages)[number]["id"]>("appearance");

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
  return <div className="settings-shell">
    <nav className="sidebar" aria-label="设置分类">
      <div className="sidebar-header"><img src={logo} alt="" /><span>水杉 IME</span></div>
      {pages.map(item => <button key={item.id} type="button" className={`item${page === item.id ? " active" : ""}`}
        aria-current={page === item.id ? "page" : undefined} aria-controls="settings-content" onClick={() => setPage(item.id)}>
        <span className="icon"><img src={item.icon} alt="" /></span>{item.title}
      </button>)}
      <p className="preview-label">客户端预览版</p>
    </nav>
    <main id="settings-content" aria-labelledby="page-title"><div className="content">
    <header className="content-header"><h1 id="page-title">{pages.find(item => item.id === page)!.title}</h1></header>
    {error && <p role="alert" className="error">{error}</p>}
    {notice && <p role="status" className="notice">{notice}</p>}
    {busy && !draft && <p role="status">正在读取设置…</p>}
    {draft && <form onSubmit={event => { event.preventDefault(); void save(); }}>
      <fieldset disabled={busy} hidden={page !== "appearance"} aria-label="外观">
        <div className="section"><label className="section-header"><span className="section-title">每页候选数量</span><select value={draft.candidate_page_size} onChange={event => setDraft({ ...draft, candidate_page_size: Number(event.target.value) })}>
          {Array.from({ length: 9 }, (_, index) => index + 1).map(size => <option key={size} value={size}>{size}</option>)}
        </select></label></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "input"} aria-label="输入">
        <div className="section"><label className="section-header"><span className="section-title">输入方案</span><select value={draft.scheme} onChange={event => setDraft({ ...draft, scheme: event.target.value as Preferences["scheme"] })}>
          <option value="quanpin">全拼</option><option value="shuangpin">双拼</option>
          <option value="wubi">五笔</option><option value="japanese">日语</option>
        </select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">双拼方案</span><select disabled={draft.scheme !== "shuangpin"} value={draft.shuangpin_profile} onChange={event => setDraft({ ...draft, shuangpin_profile: event.target.value as Preferences["shuangpin_profile"] })}>
          <option value="xiaohe">小鹤双拼</option><option value="ziranma">自然码双拼</option>
          <option value="shoudao">首道双拼</option><option value="microsoft">微软双拼</option>
        </select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">全拼纠错<small>自动纠正常见拼音输入错误</small></span><input className="toggle" type="checkbox" checked={draft.autocorrect ?? true} onChange={event => setDraft({ ...draft, autocorrect: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">学习选词习惯<small>根据选词调整候选顺序</small></span><input className="toggle" type="checkbox" checked={draft.learning} onChange={event => setDraft({ ...draft, learning: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">中文标点<small>默认使用中文标点符号</small></span><input className="toggle" type="checkbox" checked={draft.chinese_punctuation} onChange={event => setDraft({ ...draft, chinese_punctuation: event.target.checked })} /></label></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "helpcode"} aria-label="辅助码">
        {([['shuangpin_helpcode', '双拼'], ['quanpin_helpcode', '全拼']] as const).map(([key, label]) => {
          const value = draft[key] ?? defaultHelpcode;
          return <div className="section" key={key}>
            <label className="section-header"><span className="section-title">{label}辅助码</span><input className="toggle" type="checkbox" checked={value.enabled} onChange={event => setDraft({ ...draft, [key]: { ...value, enabled: event.target.checked } })} /></label>
            <label className="section-header helpcode-schema"><span className="section-title">{label}辅助码方案</span><select disabled={!value.enabled} value={value.schema} onChange={event => setDraft({ ...draft, [key]: { ...value, schema: event.target.value as HelpcodeSchema } })}>
              {helpcodeSchemas.map(([schema, name]) => <option key={schema} value={schema}>{name}</option>)}
            </select></label>
          </div>;
        })}
      </fieldset>
      <footer className="settings-actions"><span>{dirty ? "有未保存的修改" : ""}</span><button type="submit" disabled={busy || !dirty}>{busy ? "处理中…" : "保存设置"}</button></footer>
    </form>}
    <button className="secondary" disabled={busy} onClick={() => {
      if (!dirty || window.confirm("重新读取会放弃尚未保存的修改，是否继续？")) void reload();
    }}>重新读取</button>
  </div></main></div>;
}
