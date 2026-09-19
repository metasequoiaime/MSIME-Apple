<#
.SYNOPSIS
    Build, stage, sign and compile a release Windows installer.

.DESCRIPTION
    This is the release orchestration counterpart to Invoke-LocalInstall.ps1.
    It performs no installation and never enables CI; the caller explicitly
    supplies native dependencies, notices and the SimplySign certificate.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$X64Dependencies,
    [Parameter(Mandatory)][string]$X86Dependencies,
    [Parameter(Mandatory)][ValidatePattern('^(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})$')][string]$TargetVersion,
    [Parameter(Mandatory)][string]$NoticesDirectory,
    [string]$DesktopResourcesDirectory = 'target/desktop-resources',
    [string]$CertificateThumbprint,
    [string]$TimestampUrl = 'http://time.certum.pl',
    [string]$SignToolPath,
    [string]$IsccPath,
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))),
    [string]$Generator = 'Visual Studio 17 2022',
    [switch]$IncludeSymbols,
    [switch]$Light,
    [switch]$Reconfigure
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Stage {
    param([string]$Path, [hashtable]$Arguments)
    & $Path @Arguments
    if ($LASTEXITCODE -ne 0) { throw "发布阶段失败：$Path ($LASTEXITCODE)" }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$noticeRoot = if ([IO.Path]::IsPathRooted($NoticesDirectory)) { $NoticesDirectory } else { Join-Path $RepoRoot $NoticesDirectory }
if (-not (Test-Path -LiteralPath (Join-Path $noticeRoot 'THIRD_PARTY_NOTICES.txt') -PathType Leaf)) {
    throw 'NoticesDirectory 必须包含 THIRD_PARTY_NOTICES.txt'
}
$build = Join-Path $RepoRoot 'platforms/windows/Build-Client.ps1'
$prepare = Join-Path $PSScriptRoot 'Prepare-PackageFiles.ps1'
$payload = Join-Path $PSScriptRoot 'Sign-PackageBinaries-SimplySign.ps1'
$compile = Join-Path $PSScriptRoot 'Compile-Installer.ps1'
$installer = Join-Path $PSScriptRoot 'Sign-Installer-SimplySign.ps1'
foreach ($path in @($build, $prepare, $payload, $compile, $installer)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "发布入口缺失：$path" }
}
$stageArgs = @{
    RepoRoot=$RepoRoot; X64Dependencies=$X64Dependencies; X86Dependencies=$X86Dependencies
    Generator=$Generator; TargetVersion=$TargetVersion
}
$prepareArgs = @{
    RepoRoot=$RepoRoot; TargetVersion=$TargetVersion; NoticesDirectory=$noticeRoot
    DesktopResourcesDirectory=$DesktopResourcesDirectory; Light=$Light
    ServerReleaseDirectory='target/windows-full/x64/bin'
    Tsf32ReleaseDirectory='target/windows-full/x86/bin'
    Tsf64ReleaseDirectory='target/windows-full/x64/bin'
    DesktopExecutable='target/windows-full/x64/bin/msime-client-settings.exe'
}
$signArgs = @{ PackageRoot=$PSScriptRoot; CertificateThumbprint=$CertificateThumbprint; TimestampUrl=$TimestampUrl; SignToolPath=$SignToolPath }
$outerName = "MetasequoiaIME_Setup_v$TargetVersion"
if ($Light) { $outerName += '_light' }
if ($IncludeSymbols) { $outerName += '_with_pdb' }
$outerPath = Join-Path $PSScriptRoot "Output\$outerName.exe"
Push-Location $RepoRoot
try {
    Invoke-Stage $build $stageArgs
    Invoke-Stage $prepare $prepareArgs
    Invoke-Stage $payload $signArgs
    Invoke-Stage $compile @{ IsccPath=$IsccPath; Light=$Light }
    if (-not (Test-Path -LiteralPath $outerPath -PathType Leaf)) { throw "未生成安装包：$outerPath" }
    Invoke-Stage $installer @{ InstallerPath=$outerPath; CertificateThumbprint=$CertificateThumbprint; TimestampUrl=$TimestampUrl; SignToolPath=$SignToolPath }
    Write-Host "发布安装包已生成并签名：$outerPath"
} finally { Pop-Location }
