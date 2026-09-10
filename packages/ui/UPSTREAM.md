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
`src/partials/tools-settings.html`; `assets/utilities.svg` is copied from
`public/assets/sidebar/utilities.svg` at the same commit (GPL-3.0).
Descriptions are condensed for the shared cards. Clipboard history and the
quick-phrase CRUD/import/export manager are not migrated in this increment.
