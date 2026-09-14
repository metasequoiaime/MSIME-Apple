# Third-party notice collection

`Collect-Notices.ps1` produces `target/windows-notices/THIRD_PARTY_NOTICES.txt`
from committed Engine notices, supplied dependency-prefix copyright files,
and optional supplemental documents. Packaging selects that generated file
by default when present; explicit `NoticesDirectory` remains authoritative.

```powershell
.\platforms\windows\Collect-Notices.ps1 -DependencyPrefixes C:\deps\x64,C:\deps\x86 -SupplementalNotices C:\release\rust-frontend-notices.txt
```

The Engine revision comes from the Client HEAD gitlink. Text is read with
`git show <commit>:<path>`, never from the Engine working tree. The submodule's
objects must be available locally. Each dependency prefix must provide at least
one nonempty `share/<package>/copyright`; all such files are collected in sorted
order with their SHA-256 and relative provenance. Supplemental files also carry
hashes. Absolute local paths are not included. All inputs are read before an
existing generated bundle is replaced, so missing inputs preserve prior output.

This is a collection tool, not a completeness or redistribution approval check.
It does not infer which ports/crates/npm packages were linked, fetch licenses,
collect nested submodule licenses automatically, or grant permissions missing
from upstream. The Engine helpcode notice explicitly records unresolved
redistribution permissions, and its original text is retained. Supply/review
the nested submodule, Rust/frontend, model and distribution-specific material;
retain the separate bundled Japanese model notice and application LICENSE.
Missing records must not be papered over with a claim that the whole bundle
has one license. Generated output is a release artifact, not a source-tree edit.
