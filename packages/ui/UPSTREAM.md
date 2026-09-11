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
