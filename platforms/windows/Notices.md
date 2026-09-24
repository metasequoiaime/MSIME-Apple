# Third-party notice collection

`Collect-Notices.ps1` produces `target/windows-notices/THIRD_PARTY_NOTICES.txt` from committed Engine notices, supplied dependency-prefix copyright files, and optional supplemental documents. Packaging selects that generated file by default when present; explicit `NoticesDirectory` remains authoritative.

```powershell
.\platforms\windows\Collect-Notices.ps1 -DependencyPrefixes C:\deps\x64,C:\deps\x86 -SupplementalNotices C:\release\rust-frontend-notices.txt
```

The Rust crates statically linked into the host DLL, the dictionary replay tool, the MCP server and the settings binary, and the npm packages bundled into the settings frontend, are not in any dependency prefix. `platforms/linux/collect-notices.py` collects them from the resolved graphs; run it on Windows so Cargo resolves the Windows graph, after `Build-Client.ps1` has installed `node_modules`, and pass both outputs as supplemental notices. `.github/workflows/release-windows.yml` does exactly this:

```powershell
python -X utf8 platforms\linux\collect-notices.py cargo C:\release\rust-crates-NOTICES.txt msime-host-api msime-engine-bridge msime-mcp-server msime-desktop:tauri/custom-protocol
python -X utf8 platforms\linux\collect-notices.py npm C:\release\frontend-npm-NOTICES.txt apps\desktop
```

The on-device speech runtime that `Build-Client.ps1` stages beside the Server (`sherpa-onnx-c-api.dll`, Apache-2.0; `onnxruntime.dll` and `onnxruntime_providers_shared.dll`, MIT) is pinned by `resources/voice-runtime.lock.json`, and its upstream archive carries no license files. `Collect-Notices.ps1` therefore always adds the committed texts: `shared/voice/third_party/sherpa-onnx/LICENSE` under a header naming the locked sherpa-onnx version, and the ONNX Runtime license and third-party notices pinned in `platforms/linux/data/licenses/` (the Windows DLLs report the same ONNX Runtime release). `installer/Prepare-PackageFiles.ps1` refuses to package the runtime with a notice file that does not name both sherpa-onnx and ONNX Runtime, so a notice collection older than the runtime has to be regenerated.

The Engine revision comes from `engine-lock.json`. `Collect-Notices.ps1` reads only the prepared Engine tree whose `.msime-engine-lock` marker matches that commit; it never follows a gitlink or `.gitmodules` file. Each dependency prefix must provide at least one nonempty `share/<package>/copyright`; all such files are collected in sorted order with their SHA-256 and relative provenance. Supplemental files also carry hashes. Absolute local paths are not included. All inputs are read before an existing generated bundle is replaced, so missing inputs preserve prior output.

This is a collection tool, not a completeness or redistribution approval check. It does not infer which ports/crates/npm packages were linked, fetch licenses, collect nested third-party archive licenses automatically, or grant permissions missing from upstream. The Engine helpcode notice explicitly records unresolved redistribution permissions, and its original text is retained. Supply and review the nested archive, Rust/frontend, model and distribution-specific material; retain the separate bundled Japanese model notice and application LICENSE. Missing records must not be papered over with a claim that the whole bundle has one license. Generated output is a release artifact, not a source-tree edit.
