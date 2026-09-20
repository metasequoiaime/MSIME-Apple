/**
 * The settings shell and the surfaces that hang off it: the startup screen, the skin gallery, the
 * floating-toolbar editor, shortcuts, service actions, the dictionary and clipboard managers, the
 * panel launchers, and the desktop window chrome.
 */

export const shell = "flex h-full flex-col overflow-hidden bg-chrome";

// ---- the startup screen, shown while the host is still handing over preferences ----

export const startup =
  "relative flex h-full min-h-60 w-full flex-col items-center justify-center overflow-hidden bg-chrome text-body [&>h1]:mx-6 [&>h1]:mt-[18px] [&>h1]:mb-0 [&>h1]:text-lg [&>h1]:leading-[30px] [&>h1]:font-semibold [&>h1]:text-body [&>p]:m-0 [&>p]:text-sm [&>p]:leading-6 [&>p]:text-muted";
export const startupSpinner =
  "size-9 animate-startup-spin rounded-full border-[3px] border-edge border-t-accent motion-reduce:animate-none";
/** Three pulsing dots, each a third of a cycle behind the last. */
export const startupDots = "mt-[22px] flex h-2 items-center gap-2.5";
export const startupDot =
  "size-[5px] animate-startup-pulse rounded-full bg-accent motion-reduce:animate-none";
export const startupClose =
  "absolute top-[5px] right-[5px] size-8 rounded-[7px] border-0 bg-transparent p-0 text-[22px] leading-[30px] text-muted hover:bg-[var(--button-secondary-hover)] hover:text-body";

// ---- the skin gallery on the appearance page ----

export const skinIntro = "mt-0 mb-3.5 leading-relaxed text-muted";
export const externalHeading =
  "mx-1 mt-7 mb-3 flex items-start justify-between gap-[18px] [&>div]:min-w-0";
export const externalActions =
  "flex shrink-0 grow-0 basis-auto gap-2 [&>button]:mt-0.5 [&>button]:h-[30px] [&>button]:shrink-0 [&>button]:grow-0 [&>button]:basis-auto";
export const externalDirectory =
  "mt-2 inline-block max-w-[620px] rounded-[5px] bg-[var(--button-secondary-bg)] px-[7px] py-1 break-anywhere text-muted";
export const externalMeta = "mt-1 text-xs break-anywhere text-muted";
export const externalDiagnostics =
  "mx-1 mt-2.5 text-xs break-anywhere text-muted [&>summary]:cursor-pointer [&>ul]:mt-[7px] [&>ul]:mb-0 [&>ul]:pl-5";
export const externalResourceNote = "px-6 pt-0 pb-3";

export const skinGrid = "grid grid-cols-[minmax(0,1fr)] gap-[18px]";
export const skinCard = (selected: boolean) =>
  `block overflow-hidden rounded-lg border bg-card p-0 focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-accent hover:border-edge-strong ${
    selected
      ? "border-accent shadow-[0_0_0_1px_var(--accent-color),var(--card-shadow)]"
      : "border-edge shadow-card"
  }`;
export const skinCardHeader = "flex items-center justify-between gap-4 px-6 py-5";
export const skinCardActions = "flex shrink-0 flex-col items-end gap-2";
export const skinCardBody = "flex min-w-0 flex-col gap-[5px]";
export const skinCardTitle = "text-[15px] font-[550] text-body";
export const skinCardDescription = "text-[13px] leading-normal text-muted";
/** A switch drawn by hand, because it has to sit inside a card that is itself a button. */
export const skinSwitch = (on: boolean) =>
  `relative h-[19px] w-[38px] shrink-0 rounded-[9px] border-0 p-0 ${on ? "bg-[#8e8cd8]" : "bg-[var(--toggle-off-bg)]"}`;
export const skinSwitchKnob = (on: boolean) =>
  `absolute top-1/2 left-px size-4 rounded-full bg-white shadow-[0_1px_2px_rgba(0,0,0,0.3)] ${
    on ? "translate-x-5 -translate-y-1/2" : "-translate-y-1/2"
  }`;
export const skinPreviewSwitch =
  "h-6 rounded-md border border-edge bg-transparent px-2.5 text-[11px] leading-none text-muted hover:bg-[var(--button-secondary-bg)] hover:text-body";
/*
 * The preview renders the vendored candidate markup, so these reach into class names the upstream
 * skins own (`.candidate`, `.wnd-v .container`). They stay descendant selectors for that reason --
 * as arbitrary variants rather than as stylesheet rules.
 */
export const skinCardPreview =
  "flex flex-col bg-[var(--skin-preview-stage-bg)] py-[9px] [&_.candidate]:max-w-full [&_.candidate]:min-w-0 [&_.candidate]:text-base [&_.wnd-v_.container]:w-fit [&_.wnd-v_.container]:max-w-full";
export const skinPreviewStage = "flex min-w-0 items-start overflow-hidden px-6 py-[9px]";

// ---- the floating toolbar editor ----

export const toolbarCard = "overflow-hidden p-0";
export const toolbarSettingRow = "px-6 py-5";
export const toolbarPreviewArea =
  "min-h-[190px] overflow-hidden border-t border-edge bg-subtle px-6 pt-5 pb-[30px] max-phone:px-4";
export const toolbarPreviewLabel = "mb-7 text-xs text-muted";
export const toolbarPreview = (enabled: boolean) =>
  `mx-auto flex min-h-[35px] w-max max-w-full origin-center items-center gap-1.5 rounded-lg border border-white/15 bg-[#1a1a1a] px-[7px] py-1 whitespace-nowrap text-white shadow-[4px_4px_4px_rgba(0,0,0,0.3)] ${
    enabled ? "" : "opacity-45"
  }`;
export const toolbarHandle = "text-[1.1em] leading-none text-accent";
export const toolbarRequired = "border-r border-white/20 pr-[5px]";
export const toolbarItem = "rounded-[5px] bg-white/12 px-[5px] py-[3px] text-[0.7em]";
export const toolbarAppearanceHeader =
  "[&>.section-header]:gap-4 [&>.section-header]:px-6 [&>.section-header]:py-4";
export const toolbarComponents = "overflow-hidden";
export const toolbarComponentList =
  "px-5 pt-2 pb-2.5 [&_.check-option]:min-h-[34px] [&_.check-option]:px-1 [&_.check-option]:py-2";
export const toolbarRequiredOption = "cursor-default [&_input:disabled]:opacity-72";
export const toolbarRequiredLabel = "ml-auto text-xs! text-muted!";

// ---- shortcuts ----

export const shortcutIntro = "leading-relaxed text-secondary";
export const shortcutSectionTitle = "[&>.section-title]:text-[15px]";
export const shortcutList = "mt-3 flex flex-col gap-0";
export const shortcutRow =
  "flex items-center justify-between gap-4 border-t border-[var(--divider-color)] py-[9px] [&>kbd]:min-w-30 [&>kbd]:rounded-[5px] [&>kbd]:border [&>kbd]:border-edge [&>kbd]:bg-[var(--button-secondary-bg)] [&>kbd]:px-2 [&>kbd]:py-1 [&>kbd]:text-center [&>kbd]:font-[inherit] [&>kbd]:text-xs [&>kbd]:text-body";
export const shortcutRowDanger = "text-danger";

// ---- service actions ----

export const serviceRow =
  "flex items-center justify-between gap-4 pt-3 [&>div]:flex [&>div]:flex-wrap [&>div]:items-center [&>div]:gap-2 [&_.secondary]:mt-0 [&_[role=status]]:text-xs [&_[role=status]]:text-muted [&_[role=alert]]:text-xs [&_[role=alert]]:text-muted";
export const serviceRowDanger =
  "relative items-start [&>span]:flex [&>span]:min-w-0 [&>span]:flex-col [&>span]:gap-1.5 [&>span_label]:flex [&>span_label]:items-center [&>span_label]:gap-1.5 [&>span_label]:text-xs [&>span_label]:text-muted [&>span_label_input]:m-0";
export const serviceConfirmation =
  "mt-1 flex basis-full flex-col gap-2.5 rounded-[9px] border border-danger bg-raised p-3 [&>p]:m-0 [&>p]:leading-relaxed [&>p]:text-secondary [&>div]:flex [&>div]:flex-wrap [&>div]:gap-2 [&_.danger]:rounded-lg [&_.danger]:border [&_.danger]:border-danger [&_.danger]:bg-danger [&_.danger]:px-3 [&_.danger]:py-[7px] [&_.danger]:text-white";

export const settingsActions =
  "flex flex-wrap items-center justify-end gap-3 [&>span]:text-xs [&>span]:text-muted [&>button]:rounded-lg [&>button]:border [&>button]:border-accent-soft-border [&>button]:bg-accent-strong [&>button]:px-[18px] [&>button]:py-[7px] [&>button]:text-white";
export const settingsWarning = "mt-1.5 mb-0 text-[13px] leading-normal text-[#a2543a]";

// ---- clipboard, quick phrases, personal dictionary ----

export const clipboardList = "mt-3.5 flex flex-col gap-2";
export const clipboardRow =
  "flex items-center justify-between gap-3 border-t border-[var(--divider-color)] pt-2 [&>.secondary]:mt-0 [&>.secondary]:shrink-0 [&>.secondary]:grow-0 [&>.secondary]:basis-auto [&>.secondary]:px-[9px] [&>.secondary]:py-1";
export const clipboardActions = "flex flex-wrap gap-2";
export const clipboardToolbar = "mt-2.5 flex flex-wrap gap-2";
/** The timestamp under an entry. Its colour referenced `--muted-color`, a token that does not exist. */
export const clipboardEntry =
  "flex min-w-0 flex-1 flex-col gap-0.5 [&>span]:overflow-hidden [&>span]:text-ellipsis [&>span]:whitespace-nowrap [&>small]:text-muted";

export const managerHeader =
  "[&>.section-header]:items-start [&>.section-header>span:last-child]:flex [&>.section-header>span:last-child]:flex-wrap [&>.section-header>span:last-child]:justify-end [&>.section-header>span:last-child]:gap-1.5 [&_.secondary]:mt-0 [&_.primary]:mt-0";
export const importSection = `flex flex-col gap-3 ${managerHeader}`;
export const importPreview =
  "flex max-h-70 flex-col gap-[7px] overflow-y-auto rounded-lg border border-edge bg-raised px-3 py-2.5 [&>span]:text-xs [&>span]:text-muted [&>div]:flex [&>div]:flex-col [&>div]:gap-0.5 [&>div]:border-t [&>div]:border-[var(--divider-color)] [&>div]:pt-[7px] [&>div_span]:break-anywhere [&_code]:text-[11px] [&_code]:text-muted";

export const field = "flex flex-col gap-[5px] text-xs text-secondary";
export const fieldInput =
  "min-w-25 rounded-md border border-edge bg-[var(--dropdown-bg)] px-2 py-1.5 text-body";
export const fieldSelect = `${fieldInput} min-w-[150px]`;
export const managerControls = "flex flex-wrap items-end gap-2.5";
export const phraseForm = "mt-3.5 flex flex-wrap items-end gap-2.5";
export const keyHint = "text-[11px] text-muted";
const listRow =
  "flex items-center justify-between gap-3 border-t border-[var(--divider-color)] pt-2 [&>span:first-child]:min-w-0 [&>span:first-child]:break-anywhere [&_.secondary]:mt-0 [&_.secondary]:px-[9px] [&_.secondary]:py-1";
export const phraseList = "mt-3.5 mb-0 flex list-none flex-col gap-2 p-0";
export const phraseListItem = listRow;
export const failures =
  "mt-3.5 rounded-lg border border-edge-strong bg-raised px-3 py-2.5 [&>p]:m-0 [&>p]:text-xs [&>p]:text-danger [&>ul]:mt-2 [&>ul]:mb-0 [&>ul]:flex [&>ul]:list-none [&>ul]:flex-col [&>ul]:gap-2 [&>ul]:p-0";
export const failureItem = `${listRow} [&>span:first-child]:flex [&>span:first-child]:flex-col [&>span:first-child]:gap-0.5 [&_small]:text-muted [&>button]:mt-0 [&>button]:px-[9px] [&>button]:py-1`;
export const empty = "text-muted";

// ---- panel launchers ----

export const launchCard = "overflow-hidden p-0";
export const launchRow = "px-6 py-5";
export const openButton = "mt-0 min-w-18 shrink-0 grow-0 basis-auto";
export const panelPreview =
  "min-h-[330px] border-t border-edge bg-subtle px-6 pt-5 pb-[30px] max-phone:px-4";
export const panelPreviewLabel = "mb-[18px] text-xs text-muted";

// ---- the desktop window chrome ----

export const titlebar =
  "flex h-[var(--titlebar-height)] flex-shrink-0 items-center justify-between bg-chrome pl-3 text-body select-none";
export const title =
  "min-w-0 overflow-hidden text-xs font-normal tracking-[0.2px] text-ellipsis whitespace-nowrap opacity-92";
export const windowControls =
  "flex flex-shrink-0 items-center gap-0.5 [&>button]:inline-flex [&>button]:h-[var(--titlebar-height)] [&>button]:w-[42px] [&>button]:cursor-default [&>button]:items-center [&>button]:justify-center [&>button]:rounded-none [&>button]:border-0 [&>button]:bg-transparent [&>button]:p-0 [&>button]:text-base [&>button]:text-inherit [&>button:hover]:bg-[var(--titlebar-btn-hover)] [&>button:active]:bg-[var(--titlebar-btn-active)] [&>button:focus-visible]:-outline-offset-[3px]";
/*
 * Close turns red on hover, so the glyph has to stay white there. Everywhere else on a light theme it
 * is inverted, and without this the icon would flip to dark on the red -- which is the one place the
 * inversion is wrong.
 */
export const windowClose =
  "window-close hover:bg-[#c42b1c]! hover:text-white active:bg-[#a72216]! active:text-white light-theme:hover:[&_img]:[filter:none] light-theme:active:[&_img]:[filter:none]";
/** The glyphs ship white, so a light theme inverts them -- except on the close button, which turns red. */
export const windowIcon =
  "block size-[9px] h-2.5 object-contain [pointer-events:none] light-theme:invert light-theme:brightness-[0.2]";

// ---- secret fields ----

export const secretInput = "inline-flex items-center gap-1.5";
export const secretToggle =
  "cursor-pointer rounded-md border border-current bg-transparent px-2 py-0.5 text-xs text-inherit disabled:cursor-default disabled:opacity-50";
