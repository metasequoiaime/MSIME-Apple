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
