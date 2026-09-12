import { useEffect, useMemo, useState } from "react";

export type TypingBreakdown = {
  characters: Record<string, number>;
  sources: Record<string, number>;
};

export type TypingStatistics = {
  enabled: boolean;
  total: number;
  days: Record<string, number>;
  detail?: Partial<TypingBreakdown>;
  dailyDetails?: Record<string, Partial<TypingBreakdown>>;
};

export type TypingStatisticsStatus = {
  statistics: TypingStatistics;
  availability: "ready" | "neverWritten";
  lastWrittenMs?: number | null;
};

export interface TypingStatisticsClient {
  load(): Promise<TypingStatisticsStatus>;
  setEnabled(enabled: boolean): Promise<TypingStatisticsStatus>;
  reset(): Promise<TypingStatisticsStatus>;
}

type Period = 7 | 30 | 0;
type Slice = { id: string; title: string; count: number; color: string };

const palette = ["#19a78d", "#4c8ee8", "#7772df", "#e59b43", "#db6f9f", "#a879d7", "#98705a", "#888b92"];
const characterKinds = [
  ["han", "汉字"], ["latin", "拉丁字母"], ["otherLetter", "其他文字"], ["number", "数字"],
  ["punctuation", "标点"], ["emoji", "表情"], ["symbol", "其他符号"], ["unknown", "历史未分类"],
] as const;
const sources = [
  ["quanpin", "全拼 26 键"], ["nineKey", "全拼 9 键"], ["shuangpin", "小鹤双拼"],
  ["ziranma", "自然码双拼"], ["microsoft", "微软双拼"], ["shoudao", "首道双拼"],
  ["wubi", "86 五笔"], ["japanese", "日语"], ["handwriting", "手写"], ["english", "英文键盘"],
  ["local", "本地输入"], ["ai", "AI 润色"], ["reply", "高情商回复"], ["voice", "语音输入"],
  ["unknown", "历史未分类"],
] as const;

function dayKey(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function recentDays(length: number, today = new Date()): { key: string; label: string }[] {
  const start = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  return Array.from({ length }, (_, index) => {
    const date = new Date(start);
    date.setDate(start.getDate() - (length - index - 1));
    return { key: dayKey(date), label: `${date.getMonth() + 1}月${date.getDate()}日` };
  });
}

function sum(values: Record<string, number>, keys: readonly string[]): number {
  return keys.reduce((total, key) => total + (values[key] ?? 0), 0);
}

function withUnknown(value: Partial<TypingBreakdown> | undefined, total: number): TypingBreakdown {
  const characters = { ...(value?.characters ?? {}) };
  const sourceCounts = { ...(value?.sources ?? {}) };
  characters.unknown = (characters.unknown ?? 0) + Math.max(0, total - Object.values(characters).reduce((a, b) => a + b, 0));
  sourceCounts.unknown = (sourceCounts.unknown ?? 0) + Math.max(0, total - Object.values(sourceCounts).reduce((a, b) => a + b, 0));
  return { characters, sources: sourceCounts };
}

function scopedBreakdown(statistics: TypingStatistics, keys: string[] | null): TypingBreakdown {
  if (keys === null) return withUnknown(statistics.detail, statistics.total);
  const result: TypingBreakdown = { characters: {}, sources: {} };
  for (const key of keys) {
    const count = statistics.days[key] ?? 0;
    const detail = withUnknown(statistics.dailyDetails?.[key], count);
    for (const [id, value] of Object.entries(detail.characters)) result.characters[id] = (result.characters[id] ?? 0) + value;
    for (const [id, value] of Object.entries(detail.sources)) result.sources[id] = (result.sources[id] ?? 0) + value;
  }
  return result;
}

function Distribution({ title, slices, footer }: { title: string; slices: Slice[]; footer?: string }) {
  const total = slices.reduce((value, slice) => value + slice.count, 0);
  const visible = slices.filter(slice => slice.count > 0 || slice.id !== "unknown");
  return <section className="section statistics-distribution" aria-labelledby={`statistics-${title}`}>
    <h2 id={`statistics-${title}`}>{title}</h2>
    <div className="statistics-distribution-bar" aria-hidden="true">
      {slices.filter(slice => slice.count > 0).map(slice => <span key={slice.id} style={{ backgroundColor: slice.color, width: `${slice.count / Math.max(1, total) * 100}%` }} />)}
    </div>
    {total === 0 && <p className="statistics-empty">暂无输入记录</p>}
    <div className="statistics-legend">
      {visible.map(slice => <div className="statistics-legend-row" key={slice.id} aria-label={`${slice.title} ${slice.count} 字符，${total === 0 ? "无占比" : `${(slice.count / total * 100).toFixed(1)}%`}`}>
        <span className="statistics-dot" style={{ backgroundColor: slice.color }} aria-hidden="true" />
        <span>{slice.title}</span><strong>{slice.count.toLocaleString("zh-CN")}</strong>
        <small>{total === 0 ? "—" : `${(slice.count / total * 100).toFixed(1)}%`}</small>
      </div>)}
    </div>
    {footer && <p className="statistics-footer-note">{footer}</p>}
  </section>;
}

export function TypingStatisticsPage({ client }: { client: TypingStatisticsClient }) {
  const [status, setStatus] = useState<TypingStatisticsStatus>();
  const [period, setPeriod] = useState<Period>(7);
  const [selectedDay, setSelectedDay] = useState<string | null>(null);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState("");
  const trendDays = useMemo(() => recentDays(period === 0 ? 30 : period), [period]);

  async function update(operation: () => Promise<TypingStatisticsStatus>) {
    setBusy(true); setError("");
    try { setStatus(await operation()); }
    catch { setError("无法读取或保存统计，请稍后重试。原有统计不会被自动重置。"); }
    finally { setBusy(false); }
  }

  useEffect(() => { void update(() => client.load()); }, [client]);

  if (!status) return <div className="statistics-page">{error ? <p role="alert" className="error">{error}</p> : <p role="status">正在读取打字统计…</p>}</div>;
  const statistics = status.statistics;
  const scopeKeys = selectedDay ? [selectedDay] : period === 0 ? null : trendDays.map(day => day.key);
  const breakdown = scopedBreakdown(statistics, scopeKeys);
  const scopeTotal = scopeKeys === null ? statistics.total : scopeKeys.reduce((total, key) => total + (statistics.days[key] ?? 0), 0);
  const today = recentDays(1)[0];
  const scopeTitle = selectedDay ? trendDays.find(day => day.key === selectedDay)?.label ?? selectedDay : period === 0 ? "累计输入" : `近 ${period} 天输入`;
  const maximum = Math.max(1, ...trendDays.map(day => statistics.days[day.key] ?? 0));
  const characterSlices = characterKinds.map(([id, title], index) => ({ id, title, count: breakdown.characters[id] ?? 0, color: palette[index % palette.length] }));
  const sourceSlices = sources.map(([id, title], index) => ({ id, title, count: breakdown.sources[id] ?? 0, color: palette[index % palette.length] }));
  const languageSlices: Slice[] = [
    { id: "chinese", title: "中文模式", count: sum(breakdown.sources, ["quanpin", "nineKey", "shuangpin", "ziranma", "microsoft", "shoudao", "wubi"]), color: palette[0] },
    { id: "japanese", title: "日语模式", count: breakdown.sources.japanese ?? 0, color: palette[4] },
    { id: "english", title: "英文模式", count: breakdown.sources.english ?? 0, color: palette[1] },
    { id: "local", title: "本地输入", count: breakdown.sources.local ?? 0, color: palette[5] },
    { id: "ai", title: "AI 润色", count: breakdown.sources.ai ?? 0, color: palette[3] },
    { id: "reply", title: "高情商回复", count: breakdown.sources.reply ?? 0, color: "#55bfa0" },
    { id: "voice", title: "语音输入", count: breakdown.sources.voice ?? 0, color: palette[2] },
    { id: "unknown", title: "历史未分类", count: breakdown.sources.unknown ?? 0, color: palette[7] },
  ];
  let availabilityMessage = "";
  if (status.availability === "neverWritten") availabilityMessage = "键盘从未写入过统计。请用水杉键盘成功输入几个字符，再返回此页刷新。";
  else if (statistics.total === 0 && status.lastWrittenMs) availabilityMessage = `统计最后写入于 ${new Date(status.lastWrittenMs).toLocaleString("zh-CN")}，当前计数为零；如果刚刚清空过统计，这是正常的。`;
  else if (statistics.total === 0) availabilityMessage = "统计文件已建立，但当前还没有输入记录。";

  return <div className="statistics-page">
    {error && <p role="alert" className="error">{error}</p>}
    <section className="section statistics-overview">
      <div className="statistics-period" role="group" aria-label="统计范围">
        {([[7, "7 天"], [30, "30 天"], [0, "累计"]] as const).map(([value, label]) => <button type="button" key={value} aria-pressed={period === value} onClick={() => { setPeriod(value); setSelectedDay(null); }}>{label}</button>)}
      </div>
      <div className="statistics-metrics">
        <div><span>今日输入</span><strong aria-label="今日输入字符数">{(statistics.days[today.key] ?? 0).toLocaleString("zh-CN")}</strong><small>字符</small></div>
        <div><span>{scopeTitle}</span><strong aria-label="当前范围输入字符数">{scopeTotal.toLocaleString("zh-CN")}</strong><small>字符</small></div>
      </div>
    </section>
    <section className="section statistics-trend" aria-labelledby="statistics-trend-title">
      <h2 id="statistics-trend-title">每日趋势 · 近 {period === 0 ? 30 : period} 天</h2>
      <p>最高 {maximum === 1 && trendDays.every(day => !statistics.days[day.key]) ? 0 : maximum.toLocaleString("zh-CN")} 字符 / 天</p>
      <div className={`statistics-bars statistics-bars-${trendDays.length}`}>
        {trendDays.map(day => {
          const count = statistics.days[day.key] ?? 0;
          return <button type="button" key={day.key} title={`${day.label}：${count} 字符`} aria-label={`${day.label}，${count} 字符`} aria-pressed={selectedDay === day.key} onClick={() => setSelectedDay(current => current === day.key ? null : day.key)}>
            {trendDays.length === 7 && <span>{count}</span>}<i style={{ height: `${Math.max(2, count / maximum * 100)}%` }} />
          </button>;
        })}
      </div>
      <div className="statistics-axis"><span>{trendDays[0]?.label}</span><span>{trendDays.at(-1)?.label}</span></div>
      <p className="statistics-footer-note">点按柱形查看当天的分类与占比。</p>
      {selectedDay && <button type="button" className="secondary" onClick={() => setSelectedDay(null)}>返回整个时间范围</button>}
    </section>
    <Distribution title="字符类型" slices={characterSlices} />
    <Distribution title="语言模式" slices={languageSlices} footer="按提交时使用的键盘模式统计，不推测文本语言；中文模式下输入的数字仍计入中文模式。AI 润色和语音输入单独按来源统计。" />
    <Distribution title="输入方案" slices={sourceSlices} footer="输入方案统计其上屏字符数，不计未上屏的拼音按键。旧版本总数保留为历史未分类，新输入开始记录细分。" />
    <section className="section statistics-controls">
      <label className="section-header"><span className="section-title">记录打字统计<small>关闭后，新提交不会增加统计。</small></span><input aria-label="记录打字统计" className="toggle" type="checkbox" checked={statistics.enabled} disabled={busy} onChange={event => void update(() => client.setEnabled(event.target.checked))} /></label>
      <div className="statistics-control-actions">
        <button type="button" className="secondary" disabled={busy} onClick={() => void update(() => client.load())}>{busy ? "处理中…" : "刷新统计"}</button>
        <button type="button" className="secondary statistics-reset" disabled={busy} onClick={() => {
          if (!window.confirm("清空所有打字统计？累计字数、分类和每日记录将被删除，无法恢复。")) return;
          setSelectedDay(null); void update(client.reset);
        }}>清空统计</button>
      </div>
      <p className="statistics-privacy">仅统计水杉键盘成功提交的字符，含标点及表情，不含空格、换行和未上屏拼音。组合表情计为一个字符，删除文字不扣减。仅在本机保存日期、分类和数量，不保存输入内容。每日明细保留最近 366 个有记录的日期，累计分类持续保留。</p>
    </section>
    {availabilityMessage && <section className="section statistics-availability"><h2>统计没有数据</h2><p>{availabilityMessage}</p></section>}
  </div>;
}
