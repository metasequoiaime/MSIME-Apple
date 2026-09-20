import { useEffect, useMemo, useState } from "react";

const heading = "m-0 text-[15px] font-semibold text-body";
const metric = "flex min-w-0 flex-col gap-1";
const metricValue = "text-[30px] font-[650] leading-tight break-anywhere tabular-nums text-accent";
const footerNote = "mt-3.5 mb-0 text-xs leading-relaxed text-muted";
const privacy = "mt-4 mb-0 text-xs leading-[1.7] text-muted";
// The phone's overflow menu: a details/summary disclosure, because it closes on an outside tap
// without any state to keep in sync.
const menuSummary =
  "grid h-[30px] w-[34px] cursor-pointer list-none place-items-center rounded-[9px] border border-edge bg-card text-xl leading-none text-secondary hover:bg-[var(--button-secondary-hover)] hover:text-body [&::-webkit-details-marker]:hidden";
const menuPopover =
  "absolute top-9 right-0 flex min-w-[180px] flex-col gap-[3px] rounded-[10px] border border-edge bg-card p-1.5 shadow-card";
const menuItem =
  "flex min-h-[34px] w-full items-center justify-between gap-3 rounded-[7px] border-0 bg-transparent px-[9px] py-1.5 text-left text-body not-disabled:hover:bg-[var(--button-secondary-hover)]";
// The page container. Named because this component returns it from three places -- loading, error and
// loaded -- and the loading branch was the one that got left behind when the class it used was
// replaced.
const page = "flex flex-col gap-3.5 max-phone:gap-2.5";
const empty = "mt-0.5 mb-3.5 text-center text-muted";
const rankChart = "mt-4 mb-[18px] flex flex-col gap-[11px]";
// The first column has to hold the longest label without the row's ellipsis cutting it, so the two
// charts size it differently: 候选命中位置 carries a share column the scheme ranking does not.
const rankRow = (withShare: boolean) =>
  `grid items-center gap-[9px] text-xs ${withShare ? "grid-cols-[minmax(88px,1fr)_minmax(80px,2fr)_auto_auto]" : "grid-cols-[minmax(80px,1fr)_minmax(90px,2fr)_auto]"} [&>span]:overflow-hidden [&>span]:text-ellipsis [&>span]:whitespace-nowrap [&>strong]:min-w-9 [&>strong]:text-right [&>strong]:tabular-nums [&>strong]:text-secondary [&>small]:min-w-11 [&>small]:text-right [&>small]:tabular-nums [&>small]:text-muted`;
const rankTrack = "h-[11px] overflow-hidden rounded-full bg-subtle";
const legendRow =
  "grid animate-row-reveal grid-cols-[22px_minmax(0,1fr)_auto_58px] items-center gap-[9px] motion-reduce:animate-none max-phone:grid-cols-[22px_minmax(0,1fr)_auto_50px] max-phone:gap-[7px] [&>strong]:font-medium [&>strong]:tabular-nums [&>small]:m-0 [&>small]:text-right [&>small]:tabular-nums";
const legendDot =
  "grid size-[22px] place-items-center rounded-[7px] text-xs font-[650] leading-none";
const shapeGraphic = "size-full rounded-full";

// The heatmap's five shades are one accent at five opacities, indexed by level, so the level a day
// falls into picks its class directly. Level 0 is the empty track rather than a faint accent.
const heatLevels = [
  "bg-subtle",
  "bg-accent opacity-[0.28]",
  "bg-accent opacity-[0.46]",
  "bg-accent opacity-[0.68]",
  "bg-accent",
] as const;
const heatCell = "block size-[14px] box-border rounded-[3px] border-0 p-0";
// A week is a column of seven fixed-height rows; the weekday gutter uses the same row track so the
// labels line up with the cells beside them.
const heatWeek = "grid grid-rows-[repeat(7,14px)] gap-[3px]";
const bar = "block w-full min-h-0.5 rounded-t-[3px] rounded-b-[1px]";
const axis = "mt-[7px] flex justify-between text-xs text-muted";

// The segmented control behind both the phone's content tabs and the desktop's range picker. The
// column count is a parameter because the two differ, and because the tab row silently kept four
// columns after a fifth tab was added -- the extra one wrapped onto a second row at a quarter width.
const segmented = (columns: number) =>
  `grid gap-[3px] rounded-[9px] bg-subtle p-[3px] ${columns === 5 ? "grid-cols-5" : "grid-cols-3"} [&>button]:min-h-[34px] [&>button]:rounded-[7px] [&>button]:border-0 [&>button]:bg-transparent [&>button]:text-secondary [&>button[aria-selected=true]]:bg-raised [&>button[aria-selected=true]]:text-body [&>button[aria-selected=true]]:shadow-card [&>button[aria-pressed=true]]:bg-raised [&>button[aria-pressed=true]]:text-body [&>button[aria-pressed=true]]:shadow-card`;

export type TypingBreakdown = {
  characters: Record<string, number>;
  sources: Record<string, number>;
};

export type SelectionCounts = {
  /** Commits from positions 1..9, index 0 being the first candidate. */
  ranks?: number[];
  /** Commits from further down the list than the first page. */
  beyond?: number;
};

export type TypingStatistics = {
  enabled: boolean;
  total: number;
  days: Record<string, number>;
  detail?: Partial<TypingBreakdown>;
  dailyDetails?: Record<string, Partial<TypingBreakdown>>;
  /** Absent in statistics written before candidate positions were counted. */
  selections?: SelectionCounts;
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
type Slice = { id: string; title: string; count: number; color: string; symbol: string };

const palette = [
  "#19a78d",
  "#4c8ee8",
  "#7772df",
  "#e59b43",
  "#db6f9f",
  "#a879d7",
  "#98705a",
  "#888b92",
];
const characterKinds = [
  ["han", "汉字"],
  ["latin", "拉丁字母"],
  ["otherLetter", "其他文字"],
  ["number", "数字"],
  ["punctuation", "标点"],
  ["emoji", "表情"],
  ["symbol", "其他符号"],
  ["unknown", "历史未分类"],
] as const;
const sources = [
  ["quanpin", "全拼 26 键"],
  ["nineKey", "全拼 9 键"],
  ["shuangpin", "小鹤双拼"],
  ["ziranma", "自然码双拼"],
  ["microsoft", "微软双拼"],
  ["shoudao", "首道双拼"],
  ["wubi", "86 五笔"],
  ["japanese", "日语"],
  ["handwriting", "手写"],
  ["english", "英文键盘"],
  ["local", "本地输入"],
  ["ai", "AI 润色"],
  ["reply", "高情商回复"],
  ["voice", "语音输入"],
  ["unknown", "历史未分类"],
] as const;
const characterSymbols: Record<string, string> = {
  han: "汉",
  latin: "A",
  otherLetter: "文",
  number: "123",
  punctuation: "，",
  emoji: "😀",
  symbol: "#",
  unknown: "?",
};
const sourceSymbols: Record<string, string> = {
  quanpin: "全",
  nineKey: "9",
  shuangpin: "鹤",
  ziranma: "自",
  microsoft: "微",
  shoudao: "首",
  wubi: "五",
  japanese: "日",
  handwriting: "手",
  english: "A",
  local: "本",
  ai: "✦",
  reply: "回",
  voice: "♪",
  unknown: "?",
};

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

function mobileTrendLength(days: Record<string, number>): number {
  const earliest = Object.keys(days)
    .filter((key) => /^\d{4}-\d{2}-\d{2}$/.test(key))
    .sort()[0];
  if (!earliest) return 30;
  const start = new Date(`${earliest}T00:00:00`);
  if (Number.isNaN(start.getTime())) return 30;
  const today = new Date();
  const span =
    Math.floor(
      (new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime() -
        start.getTime()) /
        86_400_000,
    ) + 1;
  return Math.min(366, Math.max(30, span));
}

function sum(values: Record<string, number>, keys: readonly string[]): number {
  return keys.reduce((total, key) => total + (values[key] ?? 0), 0);
}

function withUnknown(value: Partial<TypingBreakdown> | undefined, total: number): TypingBreakdown {
  const characters = { ...value?.characters };
  const sourceCounts = { ...value?.sources };
  characters.unknown =
    (characters.unknown ?? 0) +
    Math.max(0, total - Object.values(characters).reduce((a, b) => a + b, 0));
  sourceCounts.unknown =
    (sourceCounts.unknown ?? 0) +
    Math.max(0, total - Object.values(sourceCounts).reduce((a, b) => a + b, 0));
  return { characters, sources: sourceCounts };
}

function scopedBreakdown(statistics: TypingStatistics, keys: string[] | null): TypingBreakdown {
  if (keys === null) return withUnknown(statistics.detail, statistics.total);
  const result: TypingBreakdown = { characters: {}, sources: {} };
  for (const key of keys) {
    const count = statistics.days[key] ?? 0;
    const detail = withUnknown(statistics.dailyDetails?.[key], count);
    for (const [id, value] of Object.entries(detail.characters))
      result.characters[id] = (result.characters[id] ?? 0) + value;
    for (const [id, value] of Object.entries(detail.sources))
      result.sources[id] = (result.sources[id] ?? 0) + value;
  }
  return result;
}

type HeatmapDay = { key: string; label: string; count: number; future: boolean };

function statisticsHeatmapWeeks(days: Record<string, number>, today = new Date()): HeatmapDay[][] {
  const current = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const sundayOffset = current.getDay();
  const thisSunday = new Date(current);
  thisSunday.setDate(current.getDate() - sundayOffset);
  const start = new Date(thisSunday);
  start.setDate(thisSunday.getDate() - 52 * 7);
  return Array.from({ length: 53 }, (_, week) =>
    Array.from({ length: 7 }, (_, row) => {
      const date = new Date(start);
      date.setDate(start.getDate() + week * 7 + row);
      const key = dayKey(date);
      return {
        key,
        label: `${date.getMonth() + 1}月${date.getDate()}日`,
        count: days[key] ?? 0,
        future: date > current,
      };
    }),
  );
}

function StatisticsHeatmap({
  days,
  selectedDay,
  onSelect,
}: {
  days: Record<string, number>;
  selectedDay: string | null;
  onSelect: (key: string) => void;
}) {
  const weeks = useMemo(() => statisticsHeatmapWeeks(days), [days]);
  const maximum = Math.max(1, ...weeks.flat().map((day) => day.count));
  const monthLabels = weeks.map((week, index) => {
    const current = week[0];
    const previous = index > 0 ? weeks[index - 1][0] : undefined;
    return index === 0 || current.key.slice(0, 7) !== previous?.key.slice(0, 7)
      ? `${current.label.split("月")[0]}月`
      : "";
  });
  return (
    <div className="mt-2" role="group" aria-label="每日输入热力图">
      <div className="overflow-x-auto pb-1 [scrollbar-width:thin]">
        <div
          className="flex h-4 w-max min-w-full items-end text-[9px] text-muted [&>span:first-child]:w-[18px] [&>span:first-child]:flex-[0_0_18px] [&>span:not(:first-child)]:mr-[3px] [&>span:not(:first-child)]:w-[14px] [&>span:not(:first-child)]:overflow-visible [&>span:not(:first-child)]:whitespace-nowrap"
          aria-hidden="true"
        >
          <span />
          {monthLabels.map((label, index) => (
            <span key={index}>{label}</span>
          ))}
        </div>
        <div className="flex w-max min-w-full gap-1">
          <div
            className={`${heatWeek} w-[18px] flex-[0_0_18px] text-right text-[9px] leading-[14px] text-muted`}
            aria-hidden="true"
          >
            {["", "一", "", "三", "", "五", ""].map((label, index) => (
              <span key={index}>{label}</span>
            ))}
          </div>
          <div className="flex gap-[3px]" role="grid">
            {weeks.map((week, index) => (
              <div className={heatWeek} key={index}>
                {week.map((day) => {
                  if (day.future)
                    return (
                      <span className={`${heatCell} invisible`} key={day.key} aria-hidden="true" />
                    );
                  const level =
                    day.count === 0 ? 0 : Math.max(1, Math.ceil((day.count / maximum) * 4));
                  return (
                    <button
                      type="button"
                      className={`${heatCell} ${heatLevels[level]} cursor-pointer${selectedDay === day.key ? " outline-2 outline-offset-1 outline-[#e59b43]" : ""}`}
                      key={day.key}
                      aria-label={`热力图：${day.label}，${day.count} 字符`}
                      aria-pressed={selectedDay === day.key}
                      onClick={() => onSelect(day.key)}
                    />
                  );
                })}
              </div>
            ))}
          </div>
        </div>
      </div>
      <div className="mt-2 flex items-center gap-1 text-[10px] text-muted" aria-hidden="true">
        <span>少</span>
        {heatLevels.map((shade, level) => (
          <i className={`block size-3 rounded-[2px] ${shade}`} key={level} />
        ))}
        <span>多</span>
      </div>
    </div>
  );
}

function StatisticsTrendLine({
  days,
  counts,
  selectedDay,
}: {
  days: { key: string; label: string }[];
  counts: Record<string, number>;
  selectedDay: string | null;
}) {
  const values = days.map((day) => counts[day.key] ?? 0);
  const lineValues =
    days.length > 120
      ? values.map((_, index) => {
          const start = Math.max(0, index - 6);
          const window = values.slice(start, index + 1);
          return window.reduce((total, value) => total + value, 0) / window.length;
        })
      : values;
  const maximum = Math.max(1, ...values, ...lineValues);
  const point = (value: number, index: number) =>
    `${(index / Math.max(1, days.length - 1)) * 100},${96 - (value / maximum) * 88}`;
  const line = lineValues.map(point).join(" ");
  const area = `0,100 ${values.map(point).join(" ")} 100,100`;
  const selectedIndex = selectedDay ? days.findIndex((day) => day.key === selectedDay) : -1;
  const selectedValue = selectedIndex >= 0 ? values[selectedIndex] : 0;
  return (
    <div
      className="mt-3 h-[170px] w-full text-accent"
      role="img"
      aria-label={days.length > 120 ? "每日输入趋势折线图，显示七日均线" : "每日输入趋势折线图"}
    >
      <svg
        className="block size-full overflow-visible"
        viewBox="0 0 100 100"
        preserveAspectRatio="none"
        aria-hidden="true"
      >
        <defs>
          <linearGradient id="statistics-trend-area" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="currentColor" stopOpacity=".34" />
            <stop offset="1" stopColor="currentColor" stopOpacity=".03" />
          </linearGradient>
        </defs>
        <polygon points={area} fill="url(#statistics-trend-area)" />
        <polyline
          points={line}
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
          vectorEffect="non-scaling-stroke"
        />
        {selectedIndex >= 0 && (
          <circle
            className="fill-[#e59b43] stroke-card stroke-[1.5px]"
            cx={(selectedIndex / Math.max(1, days.length - 1)) * 100}
            cy={96 - (selectedValue / maximum) * 88}
            r="2.2"
            vectorEffect="non-scaling-stroke"
          />
        )}
      </svg>
    </div>
  );
}

type DistributionVariant = "bar" | "pie" | "donut" | "rank";

function chartGradient(slices: Slice[], total: number): string {
  let cursor = 0;
  const segments = slices
    .filter((slice) => slice.count > 0)
    .map((slice) => {
      const start = (cursor / total) * 360;
      cursor += slice.count;
      return `${slice.color} ${start}deg ${(cursor / total) * 360}deg`;
    });
  return segments.length ? `conic-gradient(${segments.join(", ")})` : "var(--surface-subtle)";
}

function ShapeChart({
  slices,
  variant,
  total,
}: {
  slices: Slice[];
  variant: Exclude<DistributionVariant, "bar">;
  total: number;
}) {
  if (variant === "rank") {
    const ranked = slices.filter((slice) => slice.count > 0).sort((a, b) => b.count - a.count);
    const peak = Math.max(1, ...ranked.map((slice) => slice.count));
    return (
      <div className={rankChart} role="img" aria-label="输入方案排行">
        {ranked.length === 0 && <p className={empty}>暂无输入记录</p>}
        {ranked.map((slice) => (
          <div className={rankRow(false)} key={slice.id}>
            <span>{slice.title}</span>
            <div className={rankTrack}>
              <i
                className="block h-full rounded-[inherit]"
                style={{ width: `${(slice.count / peak) * 100}%`, backgroundColor: slice.color }}
              />
            </div>
            <strong>{slice.count.toLocaleString("zh-CN")}</strong>
          </div>
        ))}
      </div>
    );
  }
  const label = variant === "pie" ? "字符类型饼图" : "语言模式环形图";
  return (
    <div
      className="relative mx-auto mt-4 mb-[18px] grid size-[190px] place-items-center"
      role="img"
      aria-label={label}
    >
      <div
        // The donut is the pie with its middle masked out, so both variants share one gradient and
        // differ only by that mask.
        className={
          variant === "donut"
            ? `${shapeGraphic} [mask:radial-gradient(circle,transparent_0_61%,#000_62%)]`
            : shapeGraphic
        }
        style={{ background: chartGradient(slices, Math.max(1, total)) }}
      />
      {variant === "donut" && (
        <div className="absolute flex size-[106px] flex-col items-center justify-center rounded-full bg-card">
          <strong className="text-[25px] tabular-nums text-body">
            {total.toLocaleString("zh-CN")}
          </strong>
          <span className="text-[11px] text-muted">字符</span>
        </div>
      )}
    </div>
  );
}

function Distribution({
  title,
  slices,
  footer,
  variant = "bar",
}: {
  title: string;
  slices: Slice[];
  footer?: string;
  variant?: DistributionVariant;
}) {
  const total = slices.reduce((value, slice) => value + slice.count, 0);
  const visible = slices.filter((slice) => slice.count > 0 || slice.id !== "unknown");
  return (
    <section className="section m-0" aria-labelledby={`statistics-${title}`}>
      <h2 className={heading} id={`statistics-${title}`}>
        {title}
      </h2>
      {variant === "bar" ? (
        <div
          className="mt-4 mb-3.5 flex h-[18px] w-full overflow-hidden rounded-full bg-subtle"
          aria-hidden="true"
        >
          {slices
            .filter((slice) => slice.count > 0)
            .map((slice) => (
              <span
                className="h-full origin-left animate-bar-reveal motion-reduce:animate-none"
                key={slice.id}
                style={{
                  backgroundColor: slice.color,
                  width: `${(slice.count / Math.max(1, total)) * 100}%`,
                }}
              />
            ))}
        </div>
      ) : (
        <ShapeChart slices={slices} variant={variant} total={total} />
      )}
      {total === 0 && <p className={empty}>暂无输入记录</p>}
      <div className="flex flex-col gap-[11px]">
        {visible.map((slice, index) => (
          <div
            // The rows reveal in sequence. The stylesheet staggered them with eight :nth-child rules;
            // the index is already here, so the delay comes from it and any row count works.
            className={legendRow}
            style={{ animationDelay: `${Math.min(index, 8) * 0.03}s` }}
            key={slice.id}
            aria-label={`${slice.title} ${slice.count} 字符，${total === 0 ? "无占比" : `${((slice.count / total) * 100).toFixed(1)}%`}`}
          >
            <span
              className={legendDot}
              style={{ color: slice.color, backgroundColor: `${slice.color}1a` }}
              aria-hidden="true"
            >
              {slice.symbol}
            </span>
            <span>{slice.title}</span>
            <strong>{slice.count.toLocaleString("zh-CN")}</strong>
            <small>{total === 0 ? "—" : `${((slice.count / total) * 100).toFixed(1)}%`}</small>
          </div>
        ))}
      </div>
      {footer && <p className={footerNote}>{footer}</p>}
    </section>
  );
}

/** Positions the first page holds; anything past it is counted together. */
const RANK_SLOTS = 9;

/**
 * How often each candidate position was the one committed.
 *
 * One series, so one colour and no legend — the heading names it. The bars stay in position order
 * and are never sorted by size: the whole point is the shape of the fall-off from the first
 * candidate, and ranking the ranks would destroy it. The mark colour sits below 3:1 against the
 * surface, so every row carries its count and share as text; the numbers are the relief, not
 * decoration.
 */
function CandidateRanks({ selections }: { selections: SelectionCounts | undefined }) {
  const ranks = Array.from({ length: RANK_SLOTS }, (_, index) => selections?.ranks?.[index] ?? 0);
  const beyond = selections?.beyond ?? 0;
  const total = ranks.reduce((sum, count) => sum + count, 0) + beyond;
  const peak = Math.max(1, ...ranks, beyond);
  const rows = [
    ...ranks.map((count, index) => ({
      id: `rank-${index + 1}`,
      label: `第 ${index + 1} 条`,
      count,
    })),
    { id: "beyond", label: "第 10 条以后", count: beyond },
  ];
  const share = (count: number) => (total === 0 ? "—" : `${((count / total) * 100).toFixed(1)}%`);
  return (
    <section className="section m-0" aria-labelledby="statistics-candidate-ranks">
      <h2 className={heading} id="statistics-candidate-ranks">
        候选命中位置
      </h2>
      <p className="mt-3.5 mb-1 flex items-baseline gap-2">
        <strong className="text-[30px] leading-[1.1] tabular-nums" aria-label="首选命中率">
          {total === 0 ? "—" : `${((ranks[0] / total) * 100).toFixed(1)}%`}
        </strong>
        <span className="text-[13px] text-secondary" aria-hidden="true">
          首选命中率
        </span>
        <small className="ml-auto text-xs text-muted">
          {total === 0 ? "暂无记录" : `共 ${total.toLocaleString("zh-CN")} 次上屏`}
        </small>
      </p>
      {total === 0 ? (
        <p className={empty}>暂无候选记录。用水杉键盘上屏几次后再回来查看。</p>
      ) : (
        <div className={rankChart} role="img" aria-label="候选命中位置分布">
          {rows.map((row) => (
            <div
              className={rankRow(true)}
              key={row.id}
              aria-label={`${row.label}：${row.count} 次，${share(row.count)}`}
            >
              <span>{row.label}</span>
              <div className={rankTrack}>
                <i
                  className="block h-full rounded-[inherit]"
                  style={{ width: `${(row.count / peak) * 100}%`, backgroundColor: palette[0] }}
                />
              </div>
              <strong>{row.count.toLocaleString("zh-CN")}</strong>
              <small>{share(row.count)}</small>
            </div>
          ))}
        </div>
      )}
      <p className={footerNote}>
        每次上屏记录选中的是第几条候选，只记位置，不记任何文字。首选命中率越高，说明排序越贴合你的输入。
      </p>
    </section>
  );
}

export function TypingStatisticsPage({
  client,
  mobile = false,
  platform,
  openSystemSettings,
}: {
  client: TypingStatisticsClient;
  mobile?: boolean;
  platform?: string;
  /** iOS only: opens this app's page in Settings, from which Full Access is reachable. */
  openSystemSettings?: () => Promise<void>;
}) {
  const [status, setStatus] = useState<TypingStatisticsStatus>();
  const [period, setPeriod] = useState<Period>(7);
  const [selectedDay, setSelectedDay] = useState<string | null>(null);
  const [mobileTab, setMobileTab] = useState<"trend" | "kind" | "mode" | "scheme" | "ranks">(
    "trend",
  );
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState("");
  const mobileTrendDays = useMemo(
    () => recentDays(mobileTrendLength(status?.statistics.days ?? {})),
    [status?.statistics.days],
  );
  const desktopTrendDays = useMemo(() => recentDays(period === 0 ? 30 : period), [period]);
  const trendDays = mobile ? mobileTrendDays : desktopTrendDays;

  async function update(operation: () => Promise<TypingStatisticsStatus>) {
    setBusy(true);
    setError("");
    try {
      setStatus(await operation());
    } catch {
      setError("无法读取或保存统计，请稍后重试。原有统计不会被自动重置。");
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    void update(() => client.load());
  }, [client]);

  useEffect(() => {
    if (!mobile) return;
    const refreshWhenVisible = () => {
      if (document.visibilityState !== "hidden") void update(() => client.load());
    };
    window.addEventListener("focus", refreshWhenVisible);
    document.addEventListener("visibilitychange", refreshWhenVisible);
    return () => {
      window.removeEventListener("focus", refreshWhenVisible);
      document.removeEventListener("visibilitychange", refreshWhenVisible);
    };
  }, [client, mobile]);

  if (!status)
    return (
      <div className={page}>
        {error ? (
          <p role="alert" className="error">
            {error}
          </p>
        ) : (
          <p role="status">正在读取打字统计…</p>
        )}
      </div>
    );
  const statistics = status.statistics;
  const scopeKeys = selectedDay
    ? [selectedDay]
    : mobile || period === 0
      ? null
      : trendDays.map((day) => day.key);
  const breakdown = scopedBreakdown(statistics, scopeKeys);
  const scopeTotal =
    scopeKeys === null
      ? statistics.total
      : scopeKeys.reduce((total, key) => total + (statistics.days[key] ?? 0), 0);
  const today = recentDays(1)[0];
  const scopeTitle = selectedDay
    ? (trendDays.find((day) => day.key === selectedDay)?.label ?? selectedDay)
    : mobile || period === 0
      ? "累计输入"
      : `近 ${period} 天输入`;
  const maximum = Math.max(1, ...trendDays.map((day) => statistics.days[day.key] ?? 0));
  const characterSlices = characterKinds.map(([id, title], index) => ({
    id,
    title,
    count: breakdown.characters[id] ?? 0,
    color: palette[index % palette.length],
    symbol: characterSymbols[id] ?? "?",
  }));
  const sourceSlices = sources.map(([id, title], index) => ({
    id,
    title,
    count: breakdown.sources[id] ?? 0,
    color: palette[index % palette.length],
    symbol: sourceSymbols[id] ?? "?",
  }));
  const languageSlices: Slice[] = [
    {
      id: "chinese",
      title: "中文模式",
      count: sum(breakdown.sources, [
        "quanpin",
        "nineKey",
        "shuangpin",
        "ziranma",
        "microsoft",
        "shoudao",
        "wubi",
      ]),
      color: palette[0],
      symbol: "中",
    },
    {
      id: "japanese",
      title: "日语模式",
      count: breakdown.sources.japanese ?? 0,
      color: palette[4],
      symbol: "日",
    },
    {
      id: "english",
      title: "英文模式",
      count: breakdown.sources.english ?? 0,
      color: palette[1],
      symbol: "A",
    },
    {
      id: "local",
      title: "本地输入",
      count: breakdown.sources.local ?? 0,
      color: palette[5],
      symbol: "本",
    },
    {
      id: "ai",
      title: "AI 润色",
      count: breakdown.sources.ai ?? 0,
      color: palette[3],
      symbol: "✦",
    },
    {
      id: "reply",
      title: "高情商回复",
      count: breakdown.sources.reply ?? 0,
      color: "#55bfa0",
      symbol: "回",
    },
    {
      id: "voice",
      title: "语音输入",
      count: breakdown.sources.voice ?? 0,
      color: palette[2],
      symbol: "♪",
    },
    {
      id: "unknown",
      title: "历史未分类",
      count: breakdown.sources.unknown ?? 0,
      color: palette[7],
      symbol: "?",
    },
  ];
  // On iOS the keyboard extension cannot reach the shared App Group container without Full
  // Access, so "type a few more characters" is advice that cannot work: the count stays at
  // zero however much is typed. Name the actual prerequisite instead.
  const iosPlatform = platform === "ios";
  let availabilityMessage = "";
  if (status.availability === "neverWritten") {
    availabilityMessage = iosPlatform
      ? "键盘从未写入过统计。请在系统设置 → 通用 → 键盘 → 键盘 → 水杉输入法中开启“允许完全访问”，然后用水杉键盘输入几个字再回来刷新。未开启时仍可正常打字，只是不记录统计。"
      : "键盘从未写入过统计。请用水杉键盘成功输入几个字符，再返回此页刷新。";
  } else if (statistics.total === 0 && status.lastWrittenMs)
    availabilityMessage = `统计最后写入于 ${new Date(status.lastWrittenMs).toLocaleString("zh-CN")}，当前计数为零；如果刚刚清空过统计，这是正常的。`;
  else if (statistics.total === 0) availabilityMessage = "统计文件已建立，但当前还没有输入记录。";
  const resetStatistics = () => {
    if (!window.confirm("清空所有打字统计？累计字数、分类和每日记录将被删除，无法恢复。")) return;
    setSelectedDay(null);
    void update(client.reset);
  };

  return (
    <div className={page}>
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      {mobile && (
        <div className="-mb-1 flex min-h-0 justify-end">
          <details className="relative z-[3]">
            <summary className={menuSummary} aria-label="统计选项">
              ⋯
            </summary>
            <div className={menuPopover} role="menu" aria-label="统计选项">
              <label className={menuItem}>
                <span>记录打字统计</span>
                <input
                  aria-label="记录打字统计"
                  className="toggle"
                  type="checkbox"
                  checked={statistics.enabled}
                  disabled={busy}
                  onChange={(event) => void update(() => client.setEnabled(event.target.checked))}
                />
              </label>
              <button
                type="button"
                role="menuitem"
                disabled={busy}
                onClick={() => void update(() => client.load())}
              >
                {busy ? "处理中…" : "刷新统计"}
              </button>
              <button
                type="button"
                role="menuitem"
                className={`${menuItem} text-danger`}
                disabled={busy}
                onClick={resetStatistics}
              >
                清空统计
              </button>
            </div>
          </details>
        </div>
      )}
      <section className="section m-0">
        {mobile ? (
          <div className={segmented(5)} role="tablist" aria-label="统计内容">
            {(
              [
                ["trend", "趋势"],
                ["kind", "类型"],
                ["mode", "模式"],
                ["scheme", "方案"],
                ["ranks", "候选"],
              ] as const
            ).map(([value, label]) => (
              <button
                type="button"
                role="tab"
                key={value}
                aria-selected={mobileTab === value}
                onClick={() => {
                  setMobileTab(value);
                  setSelectedDay(null);
                }}
              >
                {label}
              </button>
            ))}
          </div>
        ) : (
          <div className={segmented(3)} role="group" aria-label="统计范围">
            {(
              [
                [7, "7 天"],
                [30, "30 天"],
                [0, "累计"],
              ] as const
            ).map(([value, label]) => (
              <button
                type="button"
                key={value}
                aria-pressed={period === value}
                onClick={() => {
                  setPeriod(value);
                  setSelectedDay(null);
                }}
              >
                {label}
              </button>
            ))}
          </div>
        )}
        <div className="mt-[22px] grid grid-cols-2 gap-6 max-phone:gap-3">
          <div className={metric}>
            <span className="text-secondary">今日输入</span>
            <strong className={metricValue} aria-label="今日输入字符数">
              {(statistics.days[today.key] ?? 0).toLocaleString("zh-CN")}
            </strong>
            <small className="m-0">字符</small>
          </div>
          <div className={metric}>
            <span className="text-secondary">{scopeTitle}</span>
            <strong className={metricValue} aria-label="当前范围输入字符数">
              {scopeTotal.toLocaleString("zh-CN")}
            </strong>
            <small className="m-0">字符</small>
          </div>
        </div>
      </section>
      {(!mobile || mobileTab === "trend") && (
        <section className="section m-0" aria-labelledby="statistics-trend-title">
          <h2 className={heading} id="statistics-trend-title">
            每日趋势 ·{" "}
            {mobile && trendDays.length >= 360
              ? "近一年"
              : `近 ${mobile ? trendDays.length : period === 0 ? 30 : period} 天`}
          </h2>
          <p className="mt-[7px] mb-0 text-xs text-muted">
            最高{" "}
            {maximum === 1 && trendDays.every((day) => !statistics.days[day.key])
              ? 0
              : maximum.toLocaleString("zh-CN")}{" "}
            字符 / 天
          </p>
          {mobile ? (
            <StatisticsTrendLine
              days={trendDays}
              counts={statistics.days}
              selectedDay={selectedDay}
            />
          ) : (
            <div
              className={`mt-3 flex h-[145px] items-end ${trendDays.length === 7 ? "gap-2.5" : "gap-[3px]"} max-phone:gap-0.5`}
            >
              {trendDays.map((day) => {
                const count = statistics.days[day.key] ?? 0;
                const chosen = selectedDay === day.key;
                // A selection dims every other bar. The old stylesheet did this with two `:has()`
                // selectors because CSS could not see which day was picked; here the component
                // already holds it, so the state answers directly.
                const dimmed = selectedDay !== null && !chosen;
                return (
                  <button
                    type="button"
                    className="flex h-full min-w-0 flex-1 flex-col items-center justify-end gap-1 border-0 bg-transparent p-0 text-[10px] text-muted"
                    key={day.key}
                    title={`${day.label}：${count} 字符`}
                    aria-label={`${day.label}，${count} 字符`}
                    aria-pressed={chosen}
                    onClick={() =>
                      setSelectedDay((current) => (current === day.key ? null : day.key))
                    }
                  >
                    {trendDays.length === 7 && <span>{count}</span>}
                    <i
                      className={`${bar} ${chosen ? "bg-[#e59b43]" : "bg-accent"} ${dimmed ? "opacity-40" : chosen ? "opacity-100" : "opacity-85"}`}
                      style={{ height: `${Math.max(2, (count / maximum) * 100)}%` }}
                    />
                  </button>
                );
              })}
            </div>
          )}
          <div className={axis}>
            <span>{trendDays[0]?.label}</span>
            <span>{trendDays.at(-1)?.label}</span>
          </div>
          {mobile && (
            <>
              <p className="mt-[18px] mb-0 text-xs text-muted">每天一格，一列一周</p>
              <StatisticsHeatmap
                days={statistics.days}
                selectedDay={selectedDay}
                onSelect={(key) => setSelectedDay((current) => (current === key ? null : key))}
              />
            </>
          )}
          <p className={footerNote}>
            {mobile ? "点按热力图查看当天的分类与占比。" : "点按柱形查看当天的分类与占比。"}
          </p>
          {selectedDay && (
            <button type="button" className="secondary" onClick={() => setSelectedDay(null)}>
              返回整个时间范围
            </button>
          )}
        </section>
      )}
      {(!mobile || mobileTab === "kind") && (
        <Distribution title="字符类型" slices={characterSlices} variant={mobile ? "pie" : "bar"} />
      )}
      {(!mobile || mobileTab === "mode") && (
        <Distribution
          title="语言模式"
          slices={languageSlices}
          variant={mobile ? "donut" : "bar"}
          footer="按提交时使用的键盘模式统计，不推测文本语言；中文模式下输入的数字仍计入中文模式。AI 润色和语音输入单独按来源统计。"
        />
      )}
      {(!mobile || mobileTab === "scheme") && (
        <Distribution
          title="输入方案"
          slices={sourceSlices}
          variant={mobile ? "rank" : "bar"}
          footer="输入方案统计其上屏字符数，不计未上屏的拼音按键。旧版本总数保留为历史未分类，新输入开始记录细分。"
        />
      )}
      {(!mobile || mobileTab === "ranks") && <CandidateRanks selections={statistics.selections} />}
      {mobile ? (
        <section className="section m-0 pt-0.5">
          <p className={`${privacy} mt-0`}>
            仅统计水杉键盘成功提交的字符，含标点及表情，不含空格、换行和未上屏拼音。组合表情计为一个字符，删除文字不扣减。仅在本机保存日期、分类和数量，不保存输入内容。每日明细保留最近
            366 个有记录的日期，累计分类持续保留。
          </p>
        </section>
      ) : (
        <section className="section m-0">
          <label className="section-header mb-4">
            <span className="section-title">
              记录打字统计<small>关闭后，新提交不会增加统计。</small>
            </span>
            <input
              aria-label="记录打字统计"
              className="toggle"
              type="checkbox"
              checked={statistics.enabled}
              disabled={busy}
              onChange={(event) => void update(() => client.setEnabled(event.target.checked))}
            />
          </label>
          <div className="flex flex-wrap gap-[9px]">
            <button
              type="button"
              className="secondary m-0"
              disabled={busy}
              onClick={() => void update(() => client.load())}
            >
              {busy ? "处理中…" : "刷新统计"}
            </button>
            <button
              type="button"
              className="secondary m-0 text-danger"
              disabled={busy}
              onClick={resetStatistics}
            >
              清空统计
            </button>
          </div>
          <p className={privacy}>
            仅统计水杉键盘成功提交的字符，含标点及表情，不含空格、换行和未上屏拼音。组合表情计为一个字符，删除文字不扣减。仅在本机保存日期、分类和数量，不保存输入内容。每日明细保留最近
            366 个有记录的日期，累计分类持续保留。
          </p>
        </section>
      )}
      {availabilityMessage && (
        <section className="section m-0">
          <h2 className={heading}>统计没有数据</h2>
          <p className="mt-2 mb-0 leading-relaxed text-secondary">{availabilityMessage}</p>
          {iosPlatform && status.availability === "neverWritten" && openSystemSettings && (
            <button type="button" className="secondary" onClick={() => void openSystemSettings()}>
              打开系统键盘设置
            </button>
          )}
        </section>
      )}
    </div>
  );
}
