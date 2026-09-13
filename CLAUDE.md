# CLAUDE.md

## Worktrees

This repository is developed with many short-lived worktrees, one per task. They accumulate quickly and each one carries its own build output, so placement and cleanup matter.

- Create every worktree **outside** the repository, under `~/worktrees/<feature>/` or a dedicated `worktrees/` directory on a secondary disk. Never inside the repository, next to the main worktree, or on the Desktop.
- **Never use `/tmp` or `/var/tmp`.** Those directories belong to the system, which is free to purge them at any time, and uncommitted work placed there has been lost this way.
- Name `<feature>` in kebab-case, derived from the branch name or issue number. Do not prefix it with `wt-`; the parent directory already says what it is.
- Commit as you go rather than saving everything for the end. The branch is the first line of defence, the directory only the second: a work-in-progress commit costs nothing and survives anything that happens to the checkout.
- Remove the worktree as soon as its branch is merged or abandoned: `git worktree remove <path>`, then `git branch -D <branch>`. Run `git worktree prune` if a directory was deleted by hand.

Cleanup is not optional bookkeeping. A stale worktree keeps its full build tree alive — `target/`, `node_modules/` and `gradle-home/` each run to several gigabytes — and a few dozen forgotten worktrees are enough to fill a disk.

Before deleting a worktree, confirm it is safe: its branch is merged into `develop` (an ancestor of `origin/develop`, or every commit reported as already applied by `git cherry origin/develop <branch>`), and `git status --porcelain` shows no tracked modifications. Leave anything else alone; another session may still be working in it.
