# Windows settings UI source

Source: https://github.com/metasequoiaime/MSIME-Windows at remote default branch
`develop`, commit `0eaa35eed1dd699b28883068f2909afe3a5902da`.

`src/upstream/variables.css`, `sections.css`, and `sidebar.css` come from
`ui-html/webview2/settings/ime-settings/src/styles/` (sections is under
`components/`). SVG files in `src/assets/` come from that settings project's
`public/assets/`, with category icons under `sidebar/`. Upstream repository
license: GPL-3.0. These are tracked commit contents, not adjacent worktree edits.

The React layout adapts the sidebar, cards, and helpcode rows to the shared
preferences client. Native checkbox/select semantics and focus indicators are
retained. Explicit save/reload and cross-page drafts use the existing shared
revision protocol. Only migrated settings categories are currently shown;
native titlebar controls, remaining categories, custom dropdown menus, and
full visual parity remain outstanding. The current palette follows upstream's
default dark appearance; persisted theme settings remain outstanding.

Input mode and scheme controls follow `src/partials/input.html` and
`src/modules/input.ts` at the same commit. Radio sizes, colors, dividers, and
mode layout are adapted from `styles/components/forms.css` and
`styles/modules/input.css`, retaining keyboard focus and forced-color support.
The shared active `scheme` remains compatible with existing hosts; optional
`last_chinese_scheme` preserves the Chinese choice while Japanese is active.

Frequency controls follow the same `input.html`: five modes and numeric choices
1–6. Shared validation follows `server/assets/config/config.toml` (1–10);
existing values above 6 stay visible without truncation. Defaults are promote/1/1.
The existing learning switch remains the Engine's independent master gate.

Mixed English/emoji/kaomoji controls follow `input.html` and `input.ts` at the
same pinned Windows commit. Persisted defaults follow `config.toml`: English
enabled with a two-character threshold, emoji and kaomoji disabled. The English
threshold has eight choices and is disabled (but retained) when English mixing
is off. Candidate generation and ordering remain owned by Engine.

The utilities category and eight local-mode toggles follow
`src/partials/tools-settings.html`; `src/assets/utilities.svg` is copied from
`public/assets/sidebar/utilities.svg` at the same commit (GPL-3.0). Descriptions
are condensed for the shared cards. Clipboard history now uses the shared
bounded store and desktop host actions; system clipboard observation remains a
host responsibility. The quick-phrase CRUD/import/export manager is not
migrated in this increment.

The dedicated skin category follows `src/partials/skin.html` at the same pinned
commit. The four built-in theme cards retain the shared `candidate_skin` values;
the compact candidate previews are CSS adaptations for the React settings page.
External skin directory scanning and live preview asset loading remain pending.

Window control icons (`src/assets/minimize.svg`, `maximize.svg`, `restore.svg`,
and `close.svg`) come from the upstream settings `public/assets/` directory at
`develop` commit `04a8df56f86312474a069f4335a1b58da7afaa9e` (GPL-3.0), with only
a final newline added. Dimensions and light-theme filters follow that commit's
`src/styles/components/titlebar.css`. Maximize/restore icons follow the injected
host state subscription; native behavior and full visual parity remain unverified.

Titlebar drag initiation follows `src/main.ts` at `04a8df56`: primary press,
two-pixel Manhattan movement threshold, no second double-click press, and no
drag/maximize on resize edges. The shared React host uses pointer cancellation,
leave and window blur to discard pending gestures. Native drag delivery and
maximized-window restore-on-drag still require actual platform verification.

Independent built-in card light/dark preview switches follow `src/modules/skin.ts`
at `04a8df56f86312474a069f4335a1b58da7afaa9e`. `src/skin-preview.css` adapts the
six WeChat/Graphite/Willow color-variable rules from that commit's
`src/styles/modules/skin.css` with scoped selectors; Fluent uses shared upstream
variables. License: GPL-3.0. Preview state is UI-only, separate from saved skin
selection. Candidate markup, toolbar previews and external skin catalog parity
remain incomplete; these palette changes are not full visual parity.

Skin cards now render both candidate layouts with the first six fixed samples
from `src/partials/candidate/candidate-wnd-h.html` and `candidate-wnd-v.html` at
`04a8df56f86312474a069f4335a1b58da7afaa9e` (GPL-3.0). The React translation
omits repeated `realContainer` IDs and unused hidden candidates 7–9. Scoped
layout CSS comes from `src/styles/modules/candidate/style-h.css` and `style-v.css`;
the vertical preview is constrained to the card width. Detailed skin-specific
decoration, toolbar previews and native visual validation remain outstanding.

`src/skin-candidate-decorations.css` now ports the 32 non-palette candidate
decoration rules from the same pinned settings `src/styles/modules/skin.css`
(GPL-3.0). Selectors map skin/theme classes onto the shared card and its preview
appearance attribute; declaration bodies remain unchanged. This includes
WeChat selected text, Graphite selected contrast and Willow full-row treatment.
Toolbar previews and native visual validation remain outstanding.

Each built-in skin card now includes a static toolbar preview. The tracked
`src/upstream/skin-toolbar-preview.html` is extracted from
`ui-html/webview2/ftb/default.html` at `04a8df56f86312474a069f4335a1b58da7afaa9e`,
following upstream `skin.ts` fillToolbar: retain only `.status-bar`, remove
`#en`, `#fullwidth`, `#puncEn`, and remove descendant IDs. No scripts or host
handlers are included. `src/skin-toolbar-preview.css` adapts the toolbar rules
from settings `floating-toolbar.css` and `skin.css` to card-local selectors.
All sources are GPL-3.0. This preview is decorative and does not control the
real toolbar; native visual parity and external skin support remain unverified.

Skin card arrangement follows the pinned `skin.html` and `skin.css`: one column,
title and selection/preview actions above three preview stages, with 20px/24px
header padding and 9px/24px stage padding. Selection uses a native button with
switch semantics and the upstream 38px/19px toggle geometry. Like upstream
`bindSkinSwitch`, activating an already-selected skin keeps it selected. Saving
still uses the shared draft/revision workflow, not immediate WebView2 writes.

External skin discovery now connects the host-owned `scan_skin_catalog` command
to `src/external-skins.tsx`. Metadata, manual refresh, empty state, invalid-folder
diagnostics, compatibility-gated selection and independent preview themes follow
the same pinned Windows `skin.ts`/`skin.html` (GPL-3.0). Candidate preview colour
validation and supported palette rules follow upstream; generated rules are
scoped to a React-owned identifier, never a manifest-provided selector. The
directory/metadata/diagnostic CSS follows the pinned `skin.css` declarations.
Selection uses the shared revisioned draft. Current host theme is dark; preview
overrides do not alter compatibility. Refresh errors keep the last catalog and
late responses from a replaced host are ignored. No local path is sent by UI.

This is still partial external-skin migration: opening the directory, loading
external CSS/images, decoration geometry, native runtime resource delivery and
native visual parity remain unfinished. Cards with external resources explicitly
label the preview limitation. No arbitrary stylesheet or image URL is loaded.

The external catalog now exposes the pinned upstream `openSkinDirectory` action
as a host-injected, argument-free `open_skin_directory` command. Like
`server/src/settings/settings_app.cpp` at the same Windows commit, explicit
opening creates the host's skin directory first. Scanning remains read-only.
Windows uses ShellExecuteW (with COM initialized on a dedicated thread); macOS
and Linux pass one absolute path argument to their directory opener, never a
shell command. Failures are sanitized, existing files are preserved, and the
UI guards duplicate requests and stale completions. Native file-manager
interaction is not covered by the automated tests. External resource loading
and native visual parity remain unfinished.

External candidate preview geometry now follows the same pinned Windows
`skin.ts` `candidatePreviewCss` and `skin.css` decoration rules: conditional
`containerParent`, manifest top/width/minimum-width variables, a 118px ornament
layer, separate stacking, no pointer interception, and visible card/stage
overflow. Both candidate orientations receive this wrapper; toolbar and built-in
previews retain their markup. Numeric values are finite and bounded before use;
refresh removes obsolete geometry. Like upstream, minimum width is applied by
the decoration rule only when decoration is enabled. Image delivery remains
unimplemented, so the ornament background is explicitly `none` for now.

Sparse light palettes now layer over dark palette rules as upstream does,
instead of dropping all unspecified dark fields. Tests cover geometry bindings,
CSSOM declarations, refresh/reset and palette layering, not native pixel layout.

External decoration images now load through the host-owned `read_skin_image`
command using the bounded core resource reader. The host returns image MIME
types and bytes only; the shared UI creates an image data URL accepted by the
existing desktop img-src CSP, without broadening it. Both preview orientations
share one request and use an image element with the pinned 118px, right-aligned,
contain geometry in place of upstream's background URL. SVG bytes are never
inserted as markup. Missing/invalid images retain the base preview; refresh
reloads unchanged filenames and discards late responses. This supersedes the
earlier image-delivery limitation above. External toolbar CSS, native candidate
resource delivery and browser/native visual verification remain unfinished.

Palette delivery now uses constructed, adopted stylesheets instead of inline
`<style>` text. A real Chromium fixture using the desktop CSP reproduced the
old inline block and verified the compiled `skin-palette.ts` helper applies
scoped colours, preserves light override order, and removes only its own sheet.
Theme changes/unmount clean up sheets; unsupported browsers show a fallback
notice without weakening CSP. Native WebView acceptance remains outstanding.

Manual browser regression (no CI changes): compile `src/skin-palette.ts` with
the desktop TypeScript compiler (`--ignoreConfig --target ES2022 --module ESNext
--lib ES2022,DOM --skipLibCheck --outDir <temporary-directory>`), serve that
directory on a loopback HTTP port, then run `scripts/test-skin-palette-csp.py`
with `--url http://127.0.0.1:<port>`, `--csp` from the desktop Tauri config and
optionally `--executable <installed-chromium>`. Python Playwright is required.
Stop the temporary server afterward. The fixture is synthetic and does not
launch the native input method or access user input data.

External toolbar styles now connect the manifest-owned host reader to a
constructed `@scope` around the external preview, following the fixed Windows
`skin.ts` parse-then-insert approach. Ordinary rules, media/supports groups,
`:root` mapping and light-theme selectors are wired; refresh/unmount remove
owned sheets and late reads cannot install stale rules. Browser capability or
parse/read failure retains the base preview. CSP is unchanged.

This is partial stylesheet support, not full parity: resource-valued/escaped
declarations, imports, nested style rules and global font/keyframe/other at-rules
are deferred with a visible partial-support notice. Resource URL rewriting and
global name isolation remain follow-ups. Compile both `skin-palette.ts` and
`skin-toolbar-css.ts` for the manual Chromium regression above; it verifies
computed styles, conditional rules, root mapping, scope containment and cleanup.

Native CSS nesting is now preserved by sanitizing the browser-parsed rule tree
in place before scoped insertion. Parent declarations, nested selectors,
media/supports groups and CSSNestedDeclarations retain their original ordering;
this also preserves pseudo-element behavior that rebuilding declarations as an
`&` rule would change. Unsupported resource/global rules are still filtered at
every depth, without discarding their supported parent rule. The Chromium
regression now checks declaration order, nested conditions, pseudo-elements,
scope isolation, nested resource filtering and cleanup. This supersedes the
earlier nesting limitation, not the remaining resource/font/keyframe limitations.

Toolbar CSS image URLs now resolve against the same validated skin package via
the existing host image reader, then become bounded image-only data URLs before
scoped adoption. Repeated relative names share one read; nested declarations
and conditional groups use the same rewrite path. Remote/absolute/traversal
references never reach the reader. Failed resources omit only their declaration
and keep the partial-support notice. Preparation is tied to the card's refresh
generation, so stale image reads cannot install an old sheet. Per preparation,
32 unique reads and 16 MiB resolved/expanded content budgets bound fan-out.

Compile `toolbar-images.ts` together with the two stylesheet modules for the
manual Chromium test (TypeScript also emits `css-image-value.ts`). The regression
now verifies background data URLs, real image decoding under desktop CSP,
deduplication, nested references, scope isolation and the read-count limit.
Image-set, escaped resource syntax, fonts, animation/global rules, imports and
native-platform visual acceptance remain unfinished; simple image URL support
does not imply full external stylesheet parity.

Image-set support now includes string/URL choices, resolution descriptors,
type hints and the WebKit alias. Browser parsing normalizes each expression
before the existing bounded image rewriter, including raw expressions stored
in custom properties. Bare strings are never assumed safe if an older parser
cannot normalize them. Quoted non-resource text is preserved. The Chromium
regression covers nested/variable image sets, deduplication, scoped computed
styles and rejection of unprepared remote options. This supersedes the
image-set limitation above; escaped URLs, fonts, global animation/import rules
and native platform acceptance remain outstanding.

Literal url() payloads now support CSS hexadecimal/simple escapes and quoted
line continuations. Decoded names pass the unchanged package path allowlist
before image reads; escaped traversal and remote URLs are rejected. Quoted
non-resource text (including icon code points) is preserved. Semantics follow
https://www.w3.org/TR/css-syntax-3/#consume-escaped-code-point.
Unit and Chromium regressions cover escapes in custom-property images,
non-resource content, containment and scoped rendering. Escaped function
identifiers and escaped image-set expressions remain unsupported, as do
fonts, global animations/imports and native platform visual acceptance.

Image-set expressions now accept escaped string/URL options and quoted line
continuations, including custom properties and the WebKit alias. A
delimiter-aware scan preserves escaped quotes/parentheses and comments before
browser normalization; normalized URLs still pass package-path validation.
The Chromium regression covers rendering, cross-spelling deduplication,
scope/cleanup and rejection of escaped traversal, remote and unsupported
filename characters before reads. This supersedes the escaped image-set
limitation above. Escaped outer function identifiers, fonts, global animations,
imports and native platform visual parity remain unfinished.

Toolbar keyframes now receive per-installation private names, with matching
animation-name longhands rewritten after browser shorthand parsing. Duration,
delay, easing, fill mode, play state and priority remain intact. Media/supports
conditions, native nesting and duplicate definition order are retained. Quoted
and escaped names use the browser's keyframes grammar. Keyframe image URLs use
the existing bounded package reader, cache and final resource sanitizer.
Chromium regressions seek paused animations to verify independent playback in
two cards, name collisions, quoted/escaped names, nested declarations, image
embedding, rejection of unprepared remote frames and cleanup.
See https://www.w3.org/TR/css-animations-1/ for the animation-name/keyframes
contract. This supersedes the blanket keyframes limitation above, not full
animation compatibility: var()-dependent animation names/shorthands and
unresolved external/inherited names are disabled with a partial-support notice.
Fonts, imports, escaped resource function identifiers and native-platform
visual parity remain unfinished.

Whole-value var() animation-name and animation shorthand references now use
private, mode-specific custom-property aliases. Original variables remain
unchanged for non-animation consumers. Alias definitions stay in the original
rules with the original priorities, so browser inheritance, media/nesting,
fallbacks and dependency-cycle handling remain active. Referenced definitions
and nested whole-value fallback chains are rewritten with the same private
keyframe names. Alias expansion is bounded to 256 source/mode pairs, 32 nested
fallback levels and 16 MiB of duplicated values. Unit tests and real Chromium
cover shorthand/name variables, inherited values, conditional priority,
cyclic fallback, two-card isolation and cleanup through image preparation.
Semantics follow https://www.w3.org/TR/css-variables-1/.
This supersedes the blanket var() limitation, not full variable substitution:
fragment substitutions (e.g. pulse var(--duration)), escaped/non-ASCII variable
names and partially overridden pending shorthands remain partial support.
Fonts, imports and native-platform visual acceptance remain unfinished.

Pending variable animation shorthands are now expanded before browser parsing,
because Chromium drops their source when individual longhands override them.
PostCSS 8.5.28 (MIT, already locked for the build toolchain, now an explicit UI
dependency) preserves declaration order, comments and opaque custom values.
Whole-value variables are projected into private per-longhand aliases; original
custom properties are retained. This preserves later duration/play-state
overrides, earlier important longhands and later shorthand resets through both
image preparation and scoped installation. Browser validation remains in place;
source maps are disabled and malformed input falls back to browser recovery
with a partial notice. Source and expanded output are each capped at 16 MiB.
The production JS bundle increases by approximately 13 KiB gzip.

For the CSP regression, replace the earlier raw tsc compile instructions with
node scripts/build-skin-browser.mjs <temporary-directory>, then serve that
directory on loopback and run the same Python test. The bundled entries include
the parser's browser implementation with no external assets or relaxed CSP.
The regression checks actual fixed-time playback, overridden longhands,
priority/order, opaque quoted text and the complete prior skin tests.
This supersedes the pending-shorthand override limitation. Fragment variable
substitution, escaped/non-ASCII variable names, fonts, imports and native visual
acceptance remain unfinished.

Animation custom-property names now support non-ASCII characters and CSS
hexadecimal/simple escapes. Definitions and references share decoded logical
names through source projection and private animation aliasing; escaped names
also reserve their decoded spelling to avoid namespace collisions. Resource
validation treats only a valid var() name as opaque, leaving fallback URLs
subject to all existing image/path checks. Unit and Chromium regressions cover
Chinese names, equivalent escaped/plain spellings, escaped punctuation,
name-only variables, timing overrides and blocked remote fallbacks.
This supersedes the non-ASCII/escaped variable-name limitation, not fragment
substitution, fonts, imports or native-platform visual acceptance.

Root selector mapping now happens on browser-parsed CSSStyleRule selectors,
not by replacing text throughout the source. Actual :root pseudo-classes become
:scope, while quoted attribute values, escaped class-name colons, custom values,
content and animation names remain untouched. Browser-canonical escaped root
pseudo-classes and root rules nested under supported conditions work too.
Unit and Chromium regressions cover exact token matching, escaped/quoted text,
conditional variable inheritance, scoped computed styles and cleanup. Existing
animation, resource and native-platform limitations are unchanged.

Top-level external @font-face rules now load through an injected font reader
and the host-managed package resource API. The desktop command accepts only
package ID/relative path and font MIME types, retaining the core containment and
8 MiB per-resource limit. Binary FontFace loading needs no font URL or relaxed
CSP. Private family names and family-variable aliases isolate preview cards;
font shorthand family values and keyframe family declarations are rewritten
where browser CSSOM exposes them. Fonts are adopted only after current-generation
preparation and removed with the card stylesheet; stale results never register.
Failures retain other styling and show partial support. Limits are 8 font faces,
16 distinct source reads and 16 MiB total bytes per preparation.

Tests cover the Rust command contract, byte validation, settings-reader wiring,
React stale/cleanup/rollback ownership and actual Chromium font rendering under
desktop CSP, two-card isolation, decoder failure, remote rejection and limits.
scripts/skin-font-fixture.json contains an original synthetic rectangular glyph
font (1000 units/em and advance), not copied font artwork. Browser behavior
follows https://www.w3.org/TR/css-font-loading/.
Conditional font faces inside media/supports groups now follow nested conditions;
media changes update registration in source order and cleanup removes listeners.
Media resources preload within the existing budgets; false supports conditions
do not read resources. Unit and Chromium resize tests cover this lifecycle.
local()/data sources, tech() hints, variable font
shorthand recovery and native-platform typography parity remain unfinished.
This is preview font support, not full native candidate font delivery.

Whole-value variable font shorthands now use the same bounded source projection
as animation shorthands, before CSSOM can discard their pending substitution.
Each font longhand receives a private variable alias; original variables and
declaration priority/order are retained. Family projection subsequently passes
through the existing per-card font namespace. Chromium tests reproduce failure
on the previous implementation and verify actual font rendering after later
size overrides, earlier important sizes, shorthand resets, inheritance,
conditional definitions, nested fallback and cyclic fallback. The full font,
animation, image and CSP regression also passes without relaxing policy.
This supersedes whole-value variable font shorthand recovery above; fragment
substitution, local()/data sources, tech() hints and native typography parity
remain unfinished. No native platform acceptance is claimed.

The appearance page now includes the candidate preview section from pinned
04a8df56 settings appearance.html / appearance.ts. It reuses the scoped candidate
markup and built-in palettes, follows current draft layout, font size, page size,
preedit visibility, helpcode visibility and built-in skin selection, and resets
on reload without writing preferences. Fixed sample candidates 7–9 now also come
from the same candidate-wnd-h.html partial (GPL-3.0); skin cards still default to
six samples. No Engine input or private data is used. External skins explicitly
direct users to the existing skin-page preview, not an inaccurate built-in
substitute. Preview remains dark like the current settings host.

React tests cover draft/reload behavior and helpcode visibility. Local Chromium
tests bundle the actual settings page with an in-memory host and production CSS:
node scripts/build-settings-browser.mjs <temporary-directory>, serve on loopback,
then run scripts/test-appearance-preview.py with --url, desktop --csp and optional
--executable / --screenshot. Actual font sizes, selected skin colours, both
layouts, candidate count, preedit visibility and cleanup are checked. Native
host parity, external-skin appearance-page previews, full upstream font controls
and global theme selection remain unfinished.

External skins now also render in the appearance preview, following the same
pinned skin.ts candidate palette/decoration path already used on skin cards.
The selected package is resolved through the host catalog on entry, selection
or host changes, and manual refresh. Draft layout, size, count and visibility
continue to update without writes. Palette validation, dimension bounds and the
bounded image reader are shared with existing previews; no toolbar stylesheet
is applied to the candidate-only appearance stage. Unsupported layouts/themes,
missing packages and resource failures are explicit, not silent substitutions.

Catalog generations discard late results when selection/host/page changes;
refresh and leaving the page remove owned styles and discard pending image
results. Unit tests cover lifecycle, retry, compatibility and failed images;
the real settings Chromium fixture checks external colours, decoration geometry,
decoded image pixels, draft layout updates and stylesheet cleanup under desktop
CSP. This supersedes the appearance-page external-skin limitation above. Native
host resource delivery, global theme and full typography controls remain open.
