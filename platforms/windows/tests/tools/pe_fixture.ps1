# Synthetic headers, deliberately not loadable images. For parser tests only.
function Write-PEFixture {
    param([string]$Path, [string]$Architecture = 'x64', [string]$Kind = 'exe')
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    $bytes = [byte[]]::new(512)
    [BitConverter]::GetBytes([uint16]0x5a4d).CopyTo($bytes, 0)
    [BitConverter]::GetBytes([uint32]128).CopyTo($bytes, 60)
    [BitConverter]::GetBytes([uint32]0x4550).CopyTo($bytes, 128)
    $machine = if ($Architecture -eq 'x64') { 0x8664 } else { 0x14c }
    $magic = if ($Architecture -eq 'x64') { 0x20b } else { 0x10b }
    [BitConverter]::GetBytes([uint16]$machine).CopyTo($bytes, 132)
    [BitConverter]::GetBytes([uint16]240).CopyTo($bytes, 148)
    $flags = if ($Kind -eq 'dll') { 0x2002 } else { 2 }
    [BitConverter]::GetBytes([uint16]$flags).CopyTo($bytes, 150)
    [BitConverter]::GetBytes([uint16]$magic).CopyTo($bytes, 152)
    [IO.File]::WriteAllBytes($Path, $bytes)
}
