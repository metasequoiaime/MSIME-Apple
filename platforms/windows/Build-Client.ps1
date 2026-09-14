# Run from a Windows MSVC build environment with both Rust MSVC targets and
# prebuilt native dependency prefixes. This script never signs or installs.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$X64Dependencies,
    [Parameter(Mandatory)][string]$X86Dependencies,
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$Generator = 'Visual Studio 17 2022'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-ClientBuild {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Client build command failed: $Command ($LASTEXITCODE)" }
}

foreach ($prefix in @($X64Dependencies, $X86Dependencies)) {
    if (-not [IO.Path]::IsPathRooted($prefix) -or -not (Test-Path -LiteralPath $prefix -PathType Container)) {
        throw 'Provide absolute, existing x64 and x86 native dependency prefixes'
    }
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($relative in @('Cargo.toml', 'vendor/MSIME-Engine/CMakeLists.txt',
                         'platforms/windows/CMakeLists.txt', 'platforms/windows/tsf/CMakeLists.txt',
                         'apps/desktop/package.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $relative) -PathType Leaf)) {
        throw "Missing Client build source: $relative"
    }
}
$previousPrefix = $env:CMAKE_PREFIX_PATH
$previousTarget = $env:CARGO_TARGET_DIR
$previousDebug = $env:CARGO_PROFILE_RELEASE_DEBUG
Push-Location $RepoRoot
try {
    $env:CARGO_TARGET_DIR = Join-Path $RepoRoot 'target'
    $env:CARGO_PROFILE_RELEASE_DEBUG = '2'
    foreach ($arch in @('x64', 'x86')) {
        $triple = if ($arch -eq 'x64') { 'x86_64-pc-windows-msvc' } else { 'i686-pc-windows-msvc' }
        $platform = if ($arch -eq 'x64') { 'x64' } else { 'Win32' }
        $env:CMAKE_PREFIX_PATH = if ($arch -eq 'x64') { $X64Dependencies } else { $X86Dependencies }
        $release = Join-Path $env:CARGO_TARGET_DIR "$triple/release"
        $output = Join-Path $RepoRoot "target/windows-full/$arch"
        $bin = Join-Path $output 'bin'
        Invoke-ClientBuild cargo @('build', '--locked', '--release', '--target', $triple, '-p', 'msime-host-api')
        $source = if ($arch -eq 'x64') { 'platforms/windows' } else { 'platforms/windows/tsf' }
        Invoke-ClientBuild cmake @('-S', (Join-Path $RepoRoot $source), '-B', $output,
            '-G', $Generator, '-A', $platform,
            "-DCMAKE_PREFIX_PATH=$($env:CMAKE_PREFIX_PATH)",
            "-DMSIME_HOST_LIBRARY=$(Join-Path $release 'msime_host_api.dll.lib')",
            "-DCMAKE_RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO=$bin",
            '-DMSIMEUI_BUILD_HANDWRITING_DEMO=OFF')
        $targets = if ($arch -eq 'x64') {
            @('msime-client-server', 'msime-client-watchdog', 'msime-client-prepare', 'msime-tsf')
        } else { @('msime-tsf') }
        Invoke-ClientBuild cmake (@('--build', $output, '--config', 'RelWithDebInfo', '--parallel', '4', '--target') + $targets)
        Invoke-ClientBuild cmake @('-E', 'copy_if_different', (Join-Path $release 'msime_host_api.dll'), $bin)
        if ($arch -eq 'x64') {
            Invoke-ClientBuild cargo @('build', '--locked', '--release', '--target', $triple,
                '-p', 'msime-engine-bridge', '--bin', 'MetasequoiaImeDictionaryReplay')
            Invoke-ClientBuild cmake @('-E', 'copy_if_different',
                (Join-Path $release 'MetasequoiaImeDictionaryReplay.exe'), $bin)
            Invoke-ClientBuild cmake @('-E', 'copy_if_different',
                (Join-Path $release 'MetasequoiaImeDictionaryReplay.pdb'), $bin)
        }
    }
    $env:CMAKE_PREFIX_PATH = $X64Dependencies
    Invoke-ClientBuild pnpm @('install', '--frozen-lockfile')
    Invoke-ClientBuild pnpm @('--filter', '@msime/desktop', 'typecheck')
    Invoke-ClientBuild pnpm @('--filter', '@msime/desktop', 'tauri', 'build', '--no-bundle',
        '--target', 'x86_64-pc-windows-msvc')
    Invoke-ClientBuild cmake @('-E', 'copy_if_different',
        (Join-Path $env:CARGO_TARGET_DIR 'x86_64-pc-windows-msvc/release/msime-desktop.exe'),
        (Join-Path $RepoRoot 'target/windows-full/x64/bin/msime-client-settings.exe'))
    Write-Output 'Client native and Tauri build commands completed; no signing, packaging or installation performed.'
} finally {
    $env:CMAKE_PREFIX_PATH = $previousPrefix
    $env:CARGO_TARGET_DIR = $previousTarget
    $env:CARGO_PROFILE_RELEASE_DEBUG = $previousDebug
    Pop-Location
}
