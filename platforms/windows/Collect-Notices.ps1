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
if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf) -or
    (Get-Content -LiteralPath $markerPath -Raw).Trim() -ne $pin) {
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
