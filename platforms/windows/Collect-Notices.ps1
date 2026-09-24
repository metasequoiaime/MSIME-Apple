[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$DependencyPrefixes,
    [string[]]$SupplementalNotices = @(),
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$OutputDirectory = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $RepoRoot 'target/windows-notices' }
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) { throw 'Notice output directory must be absolute' }
$engine = Join-Path $RepoRoot 'vendor/MSIME-Engine'
$lockPath = Join-Path $RepoRoot 'engine-lock.json'
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
$pin = "$($lock.commit)"
if ($pin -notmatch '^[a-f0-9]{40}$') { throw 'Cannot resolve locked Engine commit' }
$markerPath = Join-Path $engine '.msime-engine-lock'
# scripts/fetch_engine.py writes the locked commit on the first line and a digest of the local overlays after it.
if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf) -or
    "$(Get-Content -LiteralPath $markerPath -TotalCount 1)".Trim() -ne $pin) {
    throw 'Engine sources are not prepared from the locked archive; run scripts/fetch_engine.py'
}
$documents = [Collections.Generic.List[string]]::new()
$documents.Add("MSIME Client third-party notice collection`nEngine commit: $pin`nThis collection is not a license-completeness or redistribution-authorization assessment. Nested third-party archives, Rust/frontend and other distribution-specific notices must also be supplied and reviewed.`n")
foreach ($relative in @('NOTICE.md', 'LICENSE', 'dictionary/NOTICE.md', 'dictionary/makecikudb/LICENSE',
    'helpcode/NOTICE.md', 'voice/LICENSE', 'handwriting/models/HandwritingModel-LICENSE.txt',
    'handwriting/third_party/zinnia/Zinnia-LICENSE.txt')) {
    $noticePath = Join-Path $engine $relative
    if (-not (Test-Path -LiteralPath $noticePath -PathType Leaf)) { throw "Missing locked Engine notice: $relative" }
    $content = Get-Content -LiteralPath $noticePath -Raw
    if (-not $content) { throw "Empty locked Engine notice: $relative" }
    $documents.Add("===== MSIME-Engine/$relative @ $pin =====`n$content`n")
}
# Data compiled into the shared host library rather than taken from the Engine tree.
foreach ($relative in @('crates/client-core/data/opencc/LICENSE')) {
    $noticePath = Join-Path $RepoRoot $relative
    if (-not (Test-Path -LiteralPath $noticePath -PathType Leaf)) { throw "Missing repository notice: $relative" }
    $content = Get-Content -LiteralPath $noticePath -Raw
    if (-not $content) { throw "Empty repository notice: $relative" }
    $documents.Add("===== OpenCC dictionaries ($relative), BYVoid/OpenCC @ 26753884f1984add422f3b0249ccee8613deaff6 =====`n$content`n")
}
# The on-device speech runtime Build-Client.ps1 stages beside the Server from resources/voice-runtime.lock.json: sherpa-onnx-c-api.dll (Apache-2.0), and onnxruntime.dll with onnxruntime_providers_shared.dll (MIT, plus the notices of the components ONNX Runtime bundles). The upstream archive carries no license files, so the texts pinned for the Linux package are the ones collected here; the Windows DLLs report the same ONNX Runtime release those texts name. Prepare-PackageFiles.ps1 refuses to package the runtime with a notice file that lacks these sections.
$voiceLockPath = Join-Path $RepoRoot 'resources/voice-runtime.lock.json'
if (-not (Test-Path -LiteralPath $voiceLockPath -PathType Leaf)) { throw 'Missing voice runtime lock: resources/voice-runtime.lock.json' }
$voiceVersion = "$((Get-Content -LiteralPath $voiceLockPath -Raw | ConvertFrom-Json).version)"
if ($voiceVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Cannot resolve locked voice runtime version' }
foreach ($voiceNotice in @(
    @('shared/voice/third_party/sherpa-onnx/LICENSE', "sherpa-onnx $voiceVersion (sherpa-onnx-c-api.dll), Apache License 2.0"),
    @('platforms/linux/data/licenses/onnxruntime-MIT.txt', 'ONNX Runtime (onnxruntime.dll, onnxruntime_providers_shared.dll), MIT License'),
    @('platforms/linux/data/licenses/onnxruntime-ThirdPartyNotices.txt', 'ONNX Runtime third-party notices'))) {
    $relative = $voiceNotice[0]
    $noticePath = Join-Path $RepoRoot $relative
    if (-not (Test-Path -LiteralPath $noticePath -PathType Leaf)) { throw "Missing repository notice: $relative" }
    $content = Get-Content -LiteralPath $noticePath -Raw
    if (-not $content) { throw "Empty repository notice: $relative" }
    $documents.Add("===== $($voiceNotice[1]) ($relative) =====`n$content`n")
}
$number = 0
foreach ($prefix in $DependencyPrefixes) {
    $number++
    if (-not [IO.Path]::IsPathRooted($prefix)) { throw 'Dependency prefix must be absolute' }
    $share = Join-Path $prefix 'share'
    if (-not (Test-Path -LiteralPath $share -PathType Container)) { throw 'Missing dependency license directory' }
    $licenses = @(Get-ChildItem -LiteralPath $share -Directory | Sort-Object Name | ForEach-Object {
        $copyright = Join-Path $_.FullName 'copyright'
        if (Test-Path -LiteralPath $copyright -PathType Leaf) { Get-Item -LiteralPath $copyright }
    })
    if ($licenses.Count -eq 0) { throw 'Dependency prefix has no copyright files' }
    foreach ($license in $licenses) {
        if ($license.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked copyright file refused' }
        $content = [IO.File]::ReadAllText($license.FullName)
        if ([string]::IsNullOrWhiteSpace($content)) { throw 'Empty dependency copyright file' }
        $digest = (Get-FileHash -LiteralPath $license.FullName -Algorithm SHA256).Hash
        $documents.Add("===== Dependency prefix $number/share/$($license.Directory.Name)/copyright; SHA256 $digest =====`n$content`n")
    }
}
foreach ($notice in $SupplementalNotices) {
    $content = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $notice).Path)
    if ([string]::IsNullOrWhiteSpace($content)) { throw 'Empty supplemental notice' }
    $digest = (Get-FileHash -LiteralPath $notice -Algorithm SHA256).Hash
    $documents.Add("===== Supplemental $([IO.Path]::GetFileName($notice)); SHA256 $digest =====`n$content`n")
}
# All inputs must succeed before touching an earlier generated notice bundle.
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'THIRD_PARTY_NOTICES.txt'),
    ($documents -join "`n"), [Text.UTF8Encoding]::new($false))
Write-Output 'Collected pinned Engine and supplied dependency notices; completeness review remains required.'
