import { ScreenKeyboardPreview, type TouchKeyboardSkin } from "./screen-keyboard-preview";
import { useCandidatePreviewTheme } from "../candidate/candidate-preview-theme";
import type { Preferences, TouchKeyboardScheme } from "../index";

// Every tappable surface on this page is the same card: full width, a hairline that strengthens on
// hover, and the shared press animation. Named here rather than repeated at each of the five call
// sites, because a card that drifts from the others is the failure this page is prone to.
const card =
  "press-spring w-full rounded-[14px] border border-edge bg-card text-left text-body shadow-card hover:border-edge-strong active:scale-[0.96] active:opacity-[0.88] motion-reduce:transition-none";
// The cards that are a single row: icon, a growing middle, and a trailing chevron.
const rowCard = `${card} flex items-center justify-between gap-3 px-3.5 py-[13px]`;
const cardTitle = "block text-[15px] font-semibold";
const cardNote = "mt-1";
// The middle column of a row card: it takes the leftover width and is allowed to shrink, which is
// what lets the note beside it ellipsise instead of pushing the chevron off the edge.
const rowBody = "min-w-0 flex-1";
const rowChevron = "shrink-0 grow-0 basis-auto text-lg text-muted";
const quickTile =
  "press-spring flex min-w-0 flex-col items-start gap-[5px] rounded-[11px] border border-edge bg-subtle p-3 text-left text-body hover:border-edge-strong hover:bg-raised active:scale-[0.96] active:opacity-[0.88] motion-reduce:transition-none max-tight:px-2 max-tight:py-2.5";
const quickIcon =
  "grid size-[34px] place-items-center rounded-[11px] text-[17px] font-[650] leading-none";
const quickTitle = "text-[13px] font-semibold";
const quickNote =
  "m-0 w-full overflow-hidden text-ellipsis whitespace-nowrap max-tight:text-[11px]";

/**
 * A settings page that has no tab of its own.
 *
 * The phone bar holds the source's four tabs and nothing more, so every other page has to be
 * reachable from inside one of them. They land here, at the foot of the 键盘 tab, the same way the
 * source keeps them inside its own 键盘 tab rather than growing the bar.
 */
export interface MoreSettingsPage {
  id: string;
  title: string;
  icon: string;
}

export interface HomePageActions {
  openKeyboard?: () => Promise<void>;
  openEmojiPanel?: () => Promise<void>;
  openClipboardPanel?: () => Promise<void>;
  openSystemKeyboardSettings?: () => Promise<void>;
  showInputMethodPicker?: () => Promise<void>;
}

function schemeTitle(preferences: Preferences): string {
  const selected = preferences.touch_keyboard_schemes?.selected;
  if (selected) {
    return {
      quanpin: "全拼 26 键",
      nine_key: "全拼 9 键",
      xiaohe: "小鹤双拼",
      ziranma: "自然码双拼",
      microsoft: "微软双拼",
      shoudao: "首道双拼",
      wubi: "86 五笔",
      japanese_nine_key: "日语 9 键",
      japanese: "日语 26 键",
      handwriting: "手写",
      thoughtful_reply: "高情商回复",
    }[selected];
  }
  if (preferences.touch_keyboard_layout === "handwriting") return "手写";
  if (preferences.touch_keyboard_layout === "nine_key")
    return preferences.scheme === "japanese" ? "日语 9 键" : "全拼 9 键";
  if (preferences.scheme === "japanese") return "日语 26 键";
  if (preferences.scheme === "wubi") return "86 五笔";
  if (preferences.scheme === "shuangpin") return `${preferences.shuangpin_profile} 双拼`;
  return "全拼 26 键";
}

export function HomePage({
  preferences,
  actions,
  onOpenPage,
  onSelectScheme,
  onOpenChat,
  touchLayout = false,
  morePages,
}: {
  preferences: Preferences;
  actions?: HomePageActions;
  onOpenPage: (page: string) => void;
  onOpenChat?: () => void;
  onSelectScheme?: (scheme: TouchKeyboardScheme) => void;
  touchLayout?: boolean;
  morePages?: readonly MoreSettingsPage[];
}) {
  const theme = useCandidatePreviewTheme(preferences.theme, preferences.screen_keyboard_theme);
  const skin = preferences.touch_keyboard_skin ?? "forest";
  const customDesign = preferences.custom_touch_keyboard_skin;
  const skinTitle =
    skin === "custom"
      ? "我的皮肤"
      : ({
          forest: "水杉绿",
          ocean: "海盐蓝",
          rose: "浅蔷薇",
          porcelain: "素白瓷",
          typewriter: "纸上时光",
          candy: "奶油桃桃",
          midnight: "霓虹夜航",
          blueprint: "工程蓝图",
        }[skin] ?? "水杉绿");
  const invokeAction = (action?: () => Promise<void>) => {
    if (action) void action();
  };
  const openKeyboard = () => {
    if (!actions?.openKeyboard) {
      // iOS has no separate desktop-style panel. Its Apple home card opens a
      // real text field so the system keyboard extension can be tried in place.
      if (onOpenChat) {
        onOpenChat();
        return;
      }
      onOpenPage("screen-keyboard");
      return;
    }
    void actions.openKeyboard().catch(() => {
      if (onOpenChat) onOpenChat();
      else onOpenPage("screen-keyboard");
    });
  };

  return (
    <section className="flex flex-col gap-3.5 pb-6" aria-label="首页">
      <header className="flex items-center justify-between gap-4 px-1 pt-2 pb-0.5">
        <div>
          <h2 className="m-0 text-2xl font-[650] tracking-[-0.02em] text-body max-tight:text-[21px]">
            让输入，更像你
          </h2>
          <p className="mt-1.5 mb-0 text-muted">从一次顺手的表达开始</p>
        </div>
        <img
          className="size-12 opacity-80"
          src={new URL("../assets/msime.svg", import.meta.url).href}
          alt=""
        />
      </header>
      <button type="button" className={`${card} flex flex-col gap-3 p-4`} onClick={openKeyboard}>
        <div className="flex items-center justify-between gap-3">
          <span>
            <strong className={cardTitle}>我的键盘</strong>
            <small className={cardNote}>
              {skinTitle} · {schemeTitle(preferences)}
            </small>
          </span>
          <em className="shrink-0 grow-0 basis-auto rounded-full bg-accent-soft px-2 py-1 text-[11px] not-italic text-accent">
            当前外观
          </em>
        </div>
        <ScreenKeyboardPreview
          theme={theme}
          skin={skin as TouchKeyboardSkin}
          customDesign={customDesign}
          layout={touchLayout ? "touch" : "desktop"}
        />
        <span className="flex items-center justify-between text-[13px] font-semibold text-accent">
          ⌨ 试用键盘 <span aria-hidden="true">→</span>
        </span>
      </button>
      <div className="grid grid-cols-3 gap-2.5 max-tight:gap-[7px]">
        <button type="button" className={quickTile} onClick={() => onOpenPage("skin")}>
          <span
            className={`${quickIcon} bg-[rgb(219_111_159/15%)] text-[#db6f9f]`}
            aria-hidden="true"
          >
            ◈
          </span>
          <strong className={quickTitle}>皮肤</strong>
          <small className={quickNote}>{skinTitle}</small>
        </button>
        <button type="button" className={quickTile} onClick={() => onOpenPage("input")}>
          <span
            className={`${quickIcon} bg-[rgb(25_167_141/15%)] text-[#19a78d]`}
            aria-hidden="true"
          >
            ⌨
          </span>
          <strong className={quickTitle}>输入方案</strong>
          <small className={quickNote}>{schemeTitle(preferences)}</small>
        </button>
        <button type="button" className={quickTile} onClick={() => onOpenPage("screen-keyboard")}>
          <span
            className={`${quickIcon} bg-[rgb(119_114_223/15%)] text-[#7772df]`}
            aria-hidden="true"
          >
            ⌗
          </span>
          <strong className={quickTitle}>按键</strong>
          <small className={quickNote}>间距与语音</small>
        </button>
        <button type="button" className={quickTile} onClick={() => onOpenPage("dictionary")}>
          <span
            className={`${quickIcon} bg-[rgb(152_112_90/15%)] text-[#98705a]`}
            aria-hidden="true"
          >
            ▤
          </span>
          <strong className={quickTitle}>词库</strong>
          <small className={quickNote}>个人词与同步</small>
        </button>
        <button type="button" className={quickTile} onClick={() => onOpenPage("ai")}>
          <span
            className={`${quickIcon} bg-[rgb(229_155_67/15%)] text-[#e59b43]`}
            aria-hidden="true"
          >
            ✦
          </span>
          <strong className={quickTitle}>AI</strong>
          <small className={quickNote}>回复与润色</small>
        </button>
        <button
          type="button"
          className={quickTile}
          onClick={() =>
            actions?.openSystemKeyboardSettings
              ? invokeAction(actions.openSystemKeyboardSettings)
              : onOpenPage("screen-keyboard")
          }
        >
          <span
            className={`${quickIcon} bg-[rgb(130_136_146/15%)] text-[#747b86]`}
            aria-hidden="true"
          >
            ⚙
          </span>
          <strong className={quickTitle}>系统设置</strong>
          <small className={quickNote}>启用与完全访问</small>
        </button>
      </div>
      <button
        type="button"
        className={rowCard}
        onClick={() => {
          onSelectScheme?.("thoughtful_reply");
          onOpenPage("input");
        }}
      >
        <span
          className="grid size-[34px] shrink-0 grow-0 basis-[34px] place-items-center rounded-[10px] bg-accent-soft text-[18px] text-accent"
          aria-hidden="true"
        >
          ✦
        </span>
        <span className={rowBody}>
          <strong className={cardTitle}>高情商回复</strong>
          <small className={cardNote}>切换回复键盘，试试更合适的表达</small>
        </span>
        <span className={rowChevron} aria-hidden="true">
          ↗
        </span>
      </button>
      {onOpenChat && (
        <button type="button" className={rowCard} onClick={onOpenChat}>
          <span
            className="grid size-[34px] shrink-0 grow-0 basis-[34px] place-items-center rounded-[10px] bg-accent-soft text-[18px] text-accent"
            aria-hidden="true"
          >
            ◌
          </span>
          <span className={rowBody}>
            <strong className={cardTitle}>边聊天，边试键盘</strong>
            <small className={cardNote}>在共享账号中选择 EveryAPI 模型开始对话</small>
          </span>
          <span className={rowChevron} aria-hidden="true">
            →
          </span>
        </button>
      )}
      <button type="button" className={rowCard} onClick={() => onOpenPage("appearance")}>
        <span className="text-[19px] text-accent" aria-hidden="true">
          ⚙
        </span>
        <span className={rowBody}>
          <strong className={cardTitle}>键盘设置</strong>
          <small className={cardNote}>输入偏好、词库、AI 与语音</small>
        </span>
        <span className={rowChevron} aria-hidden="true">
          ›
        </span>
      </button>
      <div className="flex flex-wrap gap-[9px]">
        {actions?.openEmojiPanel && (
          <button
            type="button"
            className="secondary m-0"
            onClick={() => invokeAction(actions.openEmojiPanel)}
          >
            表情与符号
          </button>
        )}
        {actions?.openClipboardPanel && (
          <button
            type="button"
            className="secondary m-0"
            onClick={() => invokeAction(actions.openClipboardPanel)}
          >
            剪贴板历史
          </button>
        )}
        {actions?.openSystemKeyboardSettings && (
          <button
            type="button"
            className="secondary m-0"
            onClick={() => invokeAction(actions.openSystemKeyboardSettings)}
          >
            系统键盘设置
          </button>
        )}
        {actions?.showInputMethodPicker && (
          <button
            type="button"
            className="secondary m-0"
            onClick={() => invokeAction(actions.showInputMethodPicker)}
          >
            选择输入法
          </button>
        )}
      </div>
      {morePages && morePages.length > 0 && (
        <>
          <h3 className="mt-1 mb-0 text-[13px] font-semibold text-muted">全部设置</h3>
          <div className="flex flex-col gap-2">
            {morePages.map((item) => (
              <button
                key={item.id}
                type="button"
                className={rowCard}
                onClick={() => onOpenPage(item.id)}
              >
                <img src={item.icon} alt="" aria-hidden="true" className="size-[22px] shrink-0" />
                <span className={rowBody}>
                  <strong className={cardTitle}>{item.title}</strong>
                </span>
                <span className={rowChevron} aria-hidden="true">
                  ›
                </span>
              </button>
            ))}
          </div>
        </>
      )}
    </section>
  );
}
