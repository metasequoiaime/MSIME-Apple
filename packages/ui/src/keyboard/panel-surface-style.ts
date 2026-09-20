/**
 * The handwriting and voice panels.
 *
 * Both are separate windows with the same two-palette arrangement as the emoji panel: a fixed dark
 * chrome, and a light half selected by `data-panel-theme` on the root. Same reasoning as there -- the
 * pairs are named once and the light values ride along as `group-data` variants, instead of the
 * stylesheet's habit of writing every declaration twice.
 */

const panelText = "text-[#f5f5f7] group-data-[panel-theme=light]:text-[#202124]";
const panelMuted = "text-[#aeb0b7] group-data-[panel-theme=light]:text-[#656a73]";
const panelSurface = "bg-[#202027] group-data-[panel-theme=light]:bg-[#f7f8fa]";
const panelEdge = "border-[#45454f] group-data-[panel-theme=light]:border-[#c8ccd5]";
const panelField = `rounded-[7px] border bg-[#2b2b33] ${panelEdge} ${panelText} group-data-[panel-theme=light]:bg-white`;

export const panelHeader = `group-data-[panel-theme=light]:border-b-[#d9dce3] border-b-[#45454f] ${panelSurface} ${panelText} [&>button]:text-[#aeb0b7] group-data-[panel-theme=light]:[&>button]:text-[#656a73]`;

// ---- voice ----

export const voicePanel = `group min-h-screen ${panelSurface} ${panelText}`;
export const voiceBody =
  "mx-auto flex min-h-[calc(100vh-38px)] max-w-[560px] flex-col items-stretch gap-3.5 px-8 pt-[38px] pb-7 [&>h1]:m-0 [&>h1]:text-center [&>h1]:text-[22px]";
export const voiceIcon = "self-center text-5xl leading-none";
export const voiceNote = `m-0 text-center text-[13px] ${panelMuted}`;
export const voiceLanguage =
  "flex items-center justify-between gap-4 text-[13px] text-[#d7d7dc] group-data-[panel-theme=light]:text-[#3d424b]";
export const voiceLanguageInput = `min-w-[190px] p-2 ${panelField}`;
export const voiceTextArea = `min-h-25 resize-y p-2.5 font-[inherit] ${panelField}`;
const voiceAction = "min-h-[42px] rounded-lg border-0 font-semibold";
export const voiceRecord = `${voiceAction} bg-[#d88bde] text-[#241c26]`;
export const voiceSubmit = `${voiceAction} bg-[#3a3945] text-[#f5f5f7] group-data-[panel-theme=light]:bg-[#e4e7ed] group-data-[panel-theme=light]:text-[#202124]`;

// ---- handwriting ----

export const handwritingPanel = `group ${panelSurface} ${panelText}`;
/** Canvas beside the recognition column, stacked once the window is too narrow to hold both. */
export const handwritingBody =
  "grid grid-cols-[minmax(300px,0.43fr)_minmax(360px,0.57fr)] gap-7 p-6 max-phone:grid-cols-1 max-phone:p-3.5";
export const inkSection = "min-w-0";
/*
 * Crosshair while a stroke is in progress, hand otherwise, as the shipped panel does: with no cursor
 * at all the square gives no hint that it can be written on.
 */
export const inkCanvas = `block aspect-square w-full cursor-grab touch-none rounded-lg border bg-[#25262d] ${panelEdge} group-data-[panel-theme=light]:bg-white data-[drawing=true]:cursor-crosshair focus-visible:outline-2 focus-visible:-outline-offset-[3px] focus-visible:outline-[#d88bde] [&_polyline]:fill-none [&_polyline]:stroke-[#f5f5f7] [&_polyline]:stroke-4 [&_polyline]:[stroke-linecap:round] [&_polyline]:[stroke-linejoin:round] group-data-[panel-theme=light]:[&_polyline]:stroke-[#202124] [&_circle]:fill-[#f5f5f7] group-data-[panel-theme=light]:[&_circle]:fill-[#202124] [&_text]:fill-[#b8b8c0] [&_text]:text-lg group-data-[panel-theme=light]:[&_text]:fill-[#6b6f78]`;

/*
 * A tappable tile in this panel: the stroke actions and the candidate grid share one treatment.
 *
 * Every variant is written out rather than composed from a shared constant. A prefix interpolated in
 * front of a multi-class string only ever lands on the first class -- `[&>button]:${tile}` yields
 * `[&>button]:border bg-... text-...`, so the rest leak onto the container and Tailwind never emits
 * the prefixed forms at all.
 */
export const handwritingActions =
  "mt-[18px] flex flex-wrap gap-3 [&>button]:flex-[0_0_112px] [&>button]:rounded-md [&>button]:p-2.5 [&>button]:border [&>button]:bg-[#292a31] [&>button]:border-[#45454f] [&>button]:group-data-[panel-theme=light]:border-[#c8ccd5] [&>button]:text-[#f5f5f7] [&>button]:group-data-[panel-theme=light]:text-[#202124] [&>button]:hover:border-[#d88bde] [&>button]:hover:bg-[#3b3240] [&>button]:group-data-[panel-theme=light]:bg-white [&>button]:group-data-[panel-theme=light]:hover:bg-[#edf0f5]";
export const recognitionSection =
  "[&>h2]:mt-0 [&>h2]:mb-4 [&>h2]:text-lg [&>h2]:font-semibold [&>p]:mt-6 [&>p]:text-[13px] [&>p]:text-[#b8b8c0] group-data-[panel-theme=light]:[&>p]:text-[#6b6f78]";
export const candidateGrid =
  "grid grid-cols-4 gap-2 [&>button]:aspect-square [&>button]:rounded-md [&>button]:text-3xl [&>button]:border [&>button]:bg-[#292a31] [&>button]:border-[#45454f] [&>button]:group-data-[panel-theme=light]:border-[#c8ccd5] [&>button]:text-[#f5f5f7] [&>button]:group-data-[panel-theme=light]:text-[#202124] [&>button]:hover:border-[#d88bde] [&>button]:hover:bg-[#3b3240] [&>button]:group-data-[panel-theme=light]:bg-white [&>button]:group-data-[panel-theme=light]:hover:bg-[#edf0f5]";
export const candidate = "flex min-w-0 flex-col gap-1";
export const candidateSubmit =
  "w-full min-w-0 p-1.5 leading-tight break-anywhere whitespace-normal";
/** The copy affordance beside a candidate is a label, not a glyph, so it does not want a square. */
export const candidateCopy = "aspect-auto! px-2 py-1 text-[13px]!";

// ---- the handwriting illustration on the settings page, which uses the app's palette ----

export const mock = "mx-auto w-[min(560px,100%)]";
export const mockCanvas =
  "flex min-h-[230px] items-center justify-center rounded-xl border border-dashed border-edge-strong bg-card text-muted";
export const mockStroke = "rotate-[-7deg] font-kai text-[110px] leading-none text-secondary";
export const mockCandidates =
  "mt-2.5 flex gap-2 [&>span]:flex-1 [&>span]:rounded-md [&>span]:border [&>span]:border-edge [&>span]:p-2";
