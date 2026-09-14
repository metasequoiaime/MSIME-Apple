[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DependencyPrefix,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Architecture
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
foreach ($path in @($DependencyPrefix, $Destination)) {
    if (-not [IO.Path]::IsPathRooted($path) -or -not (Test-Path -LiteralPath $path -PathType Container)) {
        throw 'Runtime dependency paths must be absolute existing directories'
    }
}
$source = Join-Path $DependencyPrefix 'bin'
# Static-only dependency prefixes need not have a release DLL directory.
if (-not (Test-Path -LiteralPath $source)) { return }
if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw 'Invalid dependency bin directory' }
$files = @(Get-ChildItem -LiteralPath $source -File | Where-Object { $_.Extension -ieq '.dll' })
$names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$existing = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in @(Get-ChildItem -LiteralPath $Destination -File | Where-Object { $_.Extension -ieq '.dll' })) {
    if ($existing.ContainsKey($file.Name)) { throw 'Ambiguous existing DLL names' }
    $existing.Add($file.Name, $file)
}
# Validate the complete set before copying anything. Never silently overwrite a
# same-named Host DLL or a dependency from a different build/generation.
foreach ($file in $files) {
    if (-not $names.Add($file.Name) -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Ambiguous or linked runtime dependency'
    }
    & (Join-Path $PSScriptRoot 'Test-PortableExecutable.ps1') -LiteralPath $file.FullName -Architecture $Architecture -Kind dll
    if ($existing.ContainsKey($file.Name) -and
        (Get-FileHash -LiteralPath $existing[$file.Name].FullName).Hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash) {
        throw 'Conflicting runtime dependency already exists in output'
    }
}
foreach ($file in $files) {
    if (-not $existing.ContainsKey($file.Name)) {
        # No Force: concurrent conflicting outputs fail instead of being replaced.
        [IO.File]::Copy($file.FullName, (Join-Path $Destination $file.Name), $false)
    }
}
