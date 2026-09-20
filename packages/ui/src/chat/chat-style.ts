/**
 * The account chat playground.
 *
 * Every colour here used to reference a token this project does not define -- `--muted`, `--border`,
 * `--surface`, `--text`, `--accent`, `--panel`, `--danger` -- names carried in from somewhere else
 * when the page was added. An undefined custom property makes the declaration invalid at computed
 * value time, so each of them silently did nothing: the message area had no background and a border
 * the colour of its text, and a sent message was `color: #fff` over a background that resolved to
 * transparent, which is white text on the page. They are wired to the real tokens below.
 */

export const page = "flex min-h-[560px] flex-col gap-3.5";
export const toolbar =
  "flex items-center justify-between gap-4 [&_strong]:block [&_small]:block [&_small]:text-muted";
export const modelControls = "flex items-center gap-2 [&>select]:min-w-[170px]";

export const messages =
  "min-h-70 flex-1 overflow-auto rounded-[14px] border border-edge bg-card p-[18px]";
export const empty =
  "grid max-w-[480px] gap-2 px-2.5 py-[26px] text-muted [&>strong]:text-body [&>span]:text-muted";

export const message = (mine: boolean) => `mt-0 mb-3 flex ${mine ? "justify-end" : ""}`;
/** The bubble. A sent one is filled with the strong accent, which white text can actually sit on. */
export const bubble = (mine: boolean) =>
  `max-w-[82%] rounded-[14px] px-3.5 py-[11px] whitespace-pre-wrap break-anywhere ${
    mine ? "bg-accent-strong text-white" : "bg-raised text-body"
  }`;
export const pending = "text-muted";
export const error =
  "flex items-center justify-between gap-3 rounded-[10px] border border-danger/35 px-3 py-2.5 text-danger";

export const composer =
  "grid gap-2 [&>textarea]:min-h-[86px] [&>textarea]:resize-y [&>small]:text-muted";
export const actions = "flex justify-end gap-2";
export const login = "self-start";
