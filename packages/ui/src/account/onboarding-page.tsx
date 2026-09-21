import { useState } from "react";
import * as onboarding from "./onboarding-style";

export type OnboardingInputScheme = "quanpin" | "nine_key";

export interface OnboardingActions {
  platform?: "android" | "ios";
  prepareResources: () => Promise<void>;
  openSystemKeyboardSettings: () => Promise<void>;
  showInputMethodPicker: () => Promise<void>;
}

function Feature({ icon, title, children }: { icon: string; title: string; children: string }) {
  return (
    <div className={onboarding.feature}>
      <span className={onboarding.featureIcon} aria-hidden="true">
        {icon}
      </span>
      <span>
        <strong>{title}</strong>
        <small>{children}</small>
      </span>
    </div>
  );
}

function SetupStep({
  number,
  title,
  children,
  last,
}: {
  number: number;
  title: string;
  children: string;
  last?: boolean;
}) {
  return (
    <div className={onboarding.setupStep}>
      <span className={onboarding.setupNumber} aria-hidden="true">
        {number}
      </span>
      <span>
        <strong>{title}</strong>
        <small>{children}</small>
      </span>
      {!last && <i aria-hidden="true" />}
    </div>
  );
}

export function WelcomeFlowPage({
  actions,
  onComplete,
  onSkip,
}: {
  actions: OnboardingActions;
  onComplete: (scheme: OnboardingInputScheme) => Promise<void>;
  onSkip?: () => Promise<void>;
}) {
  const [page, setPage] = useState(0);
  const [scheme, setScheme] = useState<OnboardingInputScheme>("quanpin");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const ios = actions.platform === "ios";

  const run = async (operation: () => Promise<void>, next?: number) => {
    if (busy) return;
    setBusy(true);
    setError("");
    try {
      await operation();
      if (next !== undefined) setPage(next);
    } catch {
      setError("操作失败，请稍后重试。");
    } finally {
      setBusy(false);
    }
  };

  const advance = () => {
    if (page === 0) void run(actions.prepareResources, 1);
    else if (page === 3) void run(() => onComplete(scheme));
    else setPage(page + 1);
  };

  return (
    // Marked the same way the settings shell is: this page owns the whole window and renders before
    // the shell exists, so without its own marker the first screen anyone sees is the only one still
    // in the desktop accent.
    <main
      className={`${onboarding.page} ${onboarding.buttons}`}
      aria-label="首次设置"
      data-onboarding-shell=""
      data-mobile=""
    >
      <header className={onboarding.header}>
        <img src={new URL("./assets/msime.svg", import.meta.url).href} alt="" />
        <div>
          <p className={onboarding.progress}>{page + 1} / 4</p>
          <h1>{["欢迎使用水杉", "启用键盘", "选择输入方式", "让表达更轻松"][page]}</h1>
        </div>
        {onSkip && (
          <button
            type="button"
            className={onboarding.skip}
            disabled={busy}
            onClick={() => void run(onSkip)}
          >
            稍后设置
          </button>
        )}
      </header>
      <div className={onboarding.body}>
        {page === 0 && (
          <section className={onboarding.section}>
            <h2 className={onboarding.sectionTitle}>水杉输入法</h2>
            <p className={onboarding.lead}>让输入更自然，让表达更自在。</p>
            <Feature icon="⌨" title="熟悉的键盘，自由的选择">
              全拼、九键、双拼、五笔与日语，按你的习惯开启。
            </Feature>
            <Feature icon="◈" title="把键盘变成你的风格">
              挑选皮肤、设计配色，也可以去社区发现更多作品。
            </Feature>
            <Feature icon="✦" title="从打字到更好的表达">
              AI 对话、高情商回复和语音服务，按需配置。
            </Feature>
            <p className={onboarding.note}>日常输入无需登录，默认保持离线。</p>
          </section>
        )}
        {page === 1 && (
          <section className={onboarding.section}>
            <h2 className={onboarding.sectionTitle}>{ios ? "添加水杉键盘" : "添加水杉输入法"}</h2>
            <p className={onboarding.lead}>
              {ios
                ? "在系统键盘列表中启用水杉，再回到任意输入框开始使用。"
                : "准备好内置词库后，按下面步骤启用系统键盘。"}
            </p>
            <div className={onboarding.setupCard}>
              <SetupStep number={1} title="打开键盘设置">
                {ios
                  ? "前往系统设置中的“通用 → 键盘 → 键盘”。"
                  : "前往系统设置中的“语言和输入法”或“屏幕键盘”。"}
              </SetupStep>
              <SetupStep number={2} title={ios ? "添加水杉键盘" : "启用水杉输入法"}>
                {ios
                  ? "在第三方键盘列表中添加水杉键盘。"
                  : "在可用输入法列表中打开 MSIME Preview。"}
              </SetupStep>
              <SetupStep number={3} title="切换并开始输入" last>
                {ios
                  ? "在输入框中切换到水杉键盘即可开始使用。"
                  : "在输入框中选择水杉输入法即可开始使用。"}
              </SetupStep>
            </div>
            <div className={onboarding.systemActions}>
              <button
                type="button"
                className="primary"
                disabled={busy}
                onClick={() => void run(actions.openSystemKeyboardSettings)}
              >
                打开系统设置
              </button>
              {!ios && (
                <button
                  type="button"
                  className="secondary"
                  disabled={busy}
                  onClick={() => void run(actions.showInputMethodPicker)}
                >
                  选择输入法
                </button>
              )}
            </div>
            <p className={onboarding.note}>
              {ios
                ? "系统设置页面由 iOS 管理，水杉不会自动启用或切换键盘。"
                : "系统设置页面由 Android 管理，水杉不会自动启用或切换输入法。"}
            </p>
          </section>
        )}
        {page === 2 && (
          <section className={onboarding.section}>
            <h2 className={onboarding.sectionTitle}>从你熟悉的键盘开始</h2>
            <p className={onboarding.lead}>先选一种，稍后可以在输入设置中调整全部方案。</p>
            <div className={onboarding.schemeList} role="radiogroup" aria-label="首次输入方案">
              <button
                type="button"
                role="radio"
                aria-checked={scheme === "quanpin"}
                className={onboarding.schemeOption(scheme === "quanpin")}
                onClick={() => setScheme("quanpin")}
              >
                <span aria-hidden="true">⌨</span>
                <span>
                  <strong>全拼 26 键</strong>
                  <small>完整字母，熟悉的输入手感</small>
                </span>
                <b aria-hidden="true">{scheme === "quanpin" ? "✓" : "○"}</b>
              </button>
              <button
                type="button"
                role="radio"
                aria-checked={scheme === "nine_key"}
                className={onboarding.schemeOption(scheme === "nine_key")}
                onClick={() => setScheme("nine_key")}
              >
                <span aria-hidden="true">▦</span>
                <span>
                  <strong>全拼 9 键</strong>
                  <small>大按键，单手输入更方便</small>
                </span>
                <b aria-hidden="true">{scheme === "nine_key" ? "✓" : "○"}</b>
              </button>
            </div>
          </section>
        )}
        {page === 3 && (
          <section className={onboarding.section}>
            <h2 className={onboarding.sectionTitle}>输入之外，多一点灵感</h2>
            <Feature icon="✦" title="高情商回复">
              复制对方的话，在回复键盘中选择回复风格，点选结果插入。
            </Feature>
            <Feature icon="◌" title="边试键盘，边聊 AI">
              在共享账号中选择 EveryAPI 模型，开始对话。
            </Feature>
            <Feature icon="♫" title="语音与智能服务">
              语音输入和 AI 润色都可以单独配置，按需使用。
            </Feature>
            <p className={onboarding.note}>键盘联网功能由你主动触发；日常拼音输入不需要联网。</p>
          </section>
        )}
      </div>
      {error && (
        <p className={onboarding.error} role="alert">
          {error}
        </p>
      )}
      <footer className={onboarding.footer}>
        <div className={onboarding.dots} aria-label={`第 ${page + 1} 步，共 4 步`}>
          {[0, 1, 2, 3].map((index) => (
            <i key={index} className={onboarding.dot(index === page)} />
          ))}
        </div>
        <button
          type="button"
          className={`primary ${onboarding.next}`}
          disabled={busy}
          onClick={advance}
        >
          {busy ? "正在准备…" : page === 3 ? "开始使用水杉" : page === 0 ? "开始设置" : "下一步"}
        </button>
        {page > 0 && (
          <button
            type="button"
            className={onboarding.back}
            disabled={busy}
            onClick={() => setPage(page - 1)}
          >
            上一步
          </button>
        )}
      </footer>
    </main>
  );
}
