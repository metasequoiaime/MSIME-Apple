/**
 * The first-run walkthrough.
 *
 * It is the only surface in the app that owns the whole window rather than living inside the settings
 * chrome, which is why it sets its own background and centres a fixed measure: header, body and footer
 * all share one column so the text does not run the full width of a desktop window.
 */

const column = "mx-auto w-[min(560px,100%)]";

export const page =
  "flex min-h-full w-full flex-col overflow-y-auto bg-chrome px-[max(22px,5vw)] pt-7 pb-[22px] text-body max-tight:pt-[18px]";
export const header = `${column} flex items-center gap-4 [&>img]:size-[58px] [&>img]:rounded-[18px] [&>img]:bg-raised [&>img]:p-[11px] [&>h1]:m-0 [&>h1]:text-[21px] [&>h1]:font-[650]`;
export const skip = "ml-auto border-0 bg-transparent px-0 py-[5px] text-[13px] text-secondary";
export const progress = "mt-0 mb-[3px] text-xs tabular-nums text-accent";

export const body = `${column} flex-1 pt-7 pb-5 max-tight:pt-[22px]`;
export const section = "flex flex-col gap-[18px]";
export const sectionTitle = "m-0 text-[27px] font-bold tracking-[-0.02em] max-tight:text-2xl";
export const lead = "mt-[-8px] mb-1 text-[15px] leading-relaxed text-secondary";

/** A feature or a setup step: an icon, a growing middle, and text that wraps inside it. */
const rowText =
  "[&_strong]:block [&_strong]:text-[15px] [&_strong]:font-semibold [&_small]:mt-1 [&_small]:text-[13px] [&_small]:leading-relaxed [&_small]:text-secondary";
export const feature = `flex items-start gap-[13px] ${rowText} [&>span:last-child]:min-w-0 [&>span:last-child]:flex-1`;
export const featureIcon =
  "grid size-10 flex-[0_0_40px] place-items-center rounded-xl bg-accent-soft text-xl text-accent";
export const note = "mt-0.5 mb-0 text-xs leading-[1.7] text-muted";

export const setupCard =
  "flex flex-col gap-0 rounded-[18px] border border-edge bg-card px-[18px] py-[5px] shadow-card";
/** The connector between steps is drawn by the step itself, absolutely placed under its number. */
export const setupStep = `relative flex min-h-[76px] items-start gap-[13px] py-3.5 ${rowText} [&>span:nth-child(2)]:min-w-0 [&>span:nth-child(2)]:flex-1 [&>span:nth-child(2)]:pt-[3px] [&>i]:absolute [&>i]:top-11 [&>i]:left-3.5 [&>i]:h-[46px] [&>i]:w-0.5 [&>i]:bg-accent-soft-border`;
export const setupNumber =
  "grid size-[30px] flex-[0_0_30px] place-items-center rounded-full bg-accent-strong font-bold text-white";

export const systemActions = "flex flex-wrap gap-[9px] [&>button]:m-0";
/** This page's buttons are larger than the settings ones: they are the only action on the screen. */
export const buttons =
  "[&_.primary]:rounded-[10px] [&_.primary]:border [&_.primary]:border-accent [&_.primary]:bg-accent-strong [&_.primary]:px-[18px] [&_.primary]:py-2.5 [&_.primary]:text-white [&_.secondary]:m-0 [&_.secondary]:px-[18px] [&_.secondary]:py-2.5";

export const schemeList = "flex flex-col gap-[11px]";
export const schemeOption = (selected: boolean) =>
  `flex items-center gap-3.5 rounded-2xl border bg-card p-[17px] text-left text-body [&>span:first-child]:text-[23px] [&>span:first-child]:text-accent [&>span:nth-child(2)]:min-w-0 [&>span:nth-child(2)]:flex-1 [&_strong]:block [&_strong]:text-base [&_strong]:font-semibold [&_small]:mt-1 [&_b]:text-[21px] [&_b]:text-accent ${
    selected
      ? "border-accent shadow-[0_0_0_1px_var(--accent-color),var(--card-shadow)]"
      : "border-edge shadow-card"
  }`;

export const error = `${column} mt-0 mb-3 text-[13px] text-danger`;
export const footer = `${column} flex flex-col items-stretch gap-2.5`;
/** The page indicator. The current page's dot stretches rather than changing only colour. */
export const dots = "mb-[3px] flex justify-center gap-[7px]";
export const dot = (active: boolean) =>
  `h-2 rounded-full ${active ? "w-6 bg-accent" : "w-2 bg-[var(--border-color)]"}`;
export const next = "w-full";
export const back = "self-center border-0 bg-transparent px-[9px] py-[3px] text-secondary";
