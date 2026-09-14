# Existing installations only: build/sign/install without replacing dictionaries.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$X64Dependencies,
    [Parameter(Mandatory)][string]$X86Dependencies,
    [Parameter(Mandatory)][string]$NoticesDirectory,
    [string]$DesktopResourcesDirectory = 'target/desktop-resources',
    [string]$TargetVersion = '0.0.1',
    [string]$RepoRoot,
    [string]$Generator = 'Visual Studio 17 2022'
)
& (Join-Path $PSScriptRoot 'Invoke-LocalInstall.ps1') @PSBoundParameters -Light
