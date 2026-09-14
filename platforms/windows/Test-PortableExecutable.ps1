[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LiteralPath,
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Architecture,
    [Parameter(Mandatory)][ValidateSet('exe', 'dll')][string]$Kind
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Bounded header inspection only; never load or execute an unverified image.
# Layout: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
$stream = [IO.File]::Open($LiteralPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
$reader = [IO.BinaryReader]::new($stream)
try {
    if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5a4d) { throw 'Missing DOS image header' }
    $stream.Position = 0x3c
    $offset = $reader.ReadUInt32()
    if ($offset -lt 64 -or [long]$offset + 26 -gt $stream.Length) { throw 'Invalid PE header offset' }
    $stream.Position = $offset
    if ($reader.ReadUInt32() -ne 0x00004550) { throw 'Missing PE signature' }
    $machine = $reader.ReadUInt16()
    $expected = if ($Architecture -eq 'x64') { 0x8664 } else { 0x14c }
    if ($machine -ne $expected) { throw 'PE architecture mismatch' }
    $stream.Position = [long]$offset + 20
    $optionalSize = $reader.ReadUInt16()
    $characteristics = $reader.ReadUInt16()
    if ($optionalSize -lt 2 -or [long]$offset + 24 + $optionalSize -gt $stream.Length) {
        throw 'Truncated PE optional header'
    }
    $magic = $reader.ReadUInt16()
    $expectedMagic = if ($Architecture -eq 'x64') { 0x20b } else { 0x10b }
    if ($magic -ne $expectedMagic) { throw 'PE optional header architecture mismatch' }
    if (($characteristics -band 2) -eq 0 -or
        (($characteristics -band 0x2000) -ne 0) -ne ($Kind -eq 'dll')) {
        throw 'PE executable/DLL kind mismatch'
    }
} finally {
    $reader.Dispose()
}
