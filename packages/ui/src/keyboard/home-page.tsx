import { ScreenKeyboardPreview, type TouchKeyboardSkin } from "./screen-keyboard-preview";
import { useCandidatePreviewTheme } from "../candidate/candidate-preview-theme";
import type { Preferences, TouchKeyboardScheme } from "../index";

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
}: {
  preferences: Preferences;
  actions?: HomePageActions;
  onOpenPage: (page: string) => void;
  onOpenChat?: () => void;
  onSelectScheme?: (scheme: TouchKeyboardScheme) => void;
  touchLayout?: boolean;
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
      <button type="button" className="home-keyboard-card" onClick={openKeyboard}>
        <div className="home-card-heading">
          <span>
            <strong>我的键盘</strong>
            <small>
              {skinTitle} · {schemeTitle(preferences)}
            </small>
          </span>
          <em>当前外观</em>
        </div>
        <ScreenKeyboardPreview
          theme={theme}
          skin={skin as TouchKeyboardSkin}
          customDesign={customDesign}
          layout={touchLayout ? "touch" : "desktop"}
        />
        <span className="home-card-action">
          ⌨ 试用键盘 <span aria-hidden="true">→</span>
        </span>
      </button>
      <div className="home-quick-grid">
        <button type="button" onClick={() => onOpenPage("skin")}>
          <span className="home-quick-icon home-quick-icon-skin" aria-hidden="true">
            ◈
          </span>
          <strong>皮肤</strong>
          <small>{skinTitle}</small>
        </button>
        <button type="button" onClick={() => onOpenPage("input")}>
          <span className="home-quick-icon home-quick-icon-input" aria-hidden="true">
            ⌨
          </span>
          <strong>输入方案</strong>
          <small>{schemeTitle(preferences)}</small>
        </button>
        <button type="button" onClick={() => onOpenPage("screen-keyboard")}>
          <span className="home-quick-icon home-quick-icon-keyboard" aria-hidden="true">
            ⌗
          </span>
          <strong>按键</strong>
          <small>间距与语音</small>
        </button>
        <button type="button" onClick={() => onOpenPage("dictionary")}>
          <span className="home-quick-icon home-quick-icon-dictionary" aria-hidden="true">
            ▤
          </span>
          <strong>词库</strong>
          <small>个人词与同步</small>
        </button>
        <button type="button" onClick={() => onOpenPage("ai")}>
          <span className="home-quick-icon home-quick-icon-ai" aria-hidden="true">
            ✦
          </span>
          <strong>AI</strong>
          <small>回复与润色</small>
        </button>
        <button
          type="button"
          onClick={() =>
            actions?.openSystemKeyboardSettings
              ? invokeAction(actions.openSystemKeyboardSettings)
              : onOpenPage("screen-keyboard")
          }
        >
          <span className="home-quick-icon home-quick-icon-system" aria-hidden="true">
            ⚙
          </span>
          <strong>系统设置</strong>
          <small>启用与完全访问</small>
        </button>
      </div>
      <button
        type="button"
        className="home-feature-card"
        onClick={() => {
          onSelectScheme?.("thoughtful_reply");
          onOpenPage("input");
        }}
      >
        <span className="home-feature-icon" aria-hidden="true">
          ✦
        </span>
        <span>
          <strong>高情商回复</strong>
          <small>切换回复键盘，试试更合适的表达</small>
        </span>
        <span aria-hidden="true">↗</span>
      </button>
      {onOpenChat && (
        <button type="button" className="home-feature-card" onClick={onOpenChat}>
          <span className="home-feature-icon" aria-hidden="true">
            ◌
          </span>
          <span>
            <strong>边聊天，边试键盘</strong>
            <small>在共享账号中选择 EveryAPI 模型开始对话</small>
          </span>
          <span aria-hidden="true">→</span>
        </button>
      )}
      <button type="button" className="home-settings-card" onClick={() => onOpenPage("appearance")}>
        <span aria-hidden="true">⚙</span>
        <span>
          <strong>键盘设置</strong>
          <small>输入偏好、词库、AI 与语音</small>
        </span>
        <span aria-hidden="true">›</span>
      </button>
      <div className="home-system-actions">
        {actions?.openEmojiPanel && (
          <button
            type="button"
            className="secondary"
            onClick={() => invokeAction(actions.openEmojiPanel)}
          >
            表情与符号
          </button>
        )}
        {actions?.openClipboardPanel && (
          <button
            type="button"
            className="secondary"
            onClick={() => invokeAction(actions.openClipboardPanel)}
          >
            剪贴板历史
          </button>
        )}
        {actions?.openSystemKeyboardSettings && (
          <button
            type="button"
            className="secondary"
            onClick={() => invokeAction(actions.openSystemKeyboardSettings)}
          >
            系统键盘设置
          </button>
        )}
        {actions?.showInputMethodPicker && (
          <button
            type="button"
            className="secondary"
            onClick={() => invokeAction(actions.showInputMethodPicker)}
          >
            选择输入法
          </button>
        )}
      </div>
    </section>
  );
}
