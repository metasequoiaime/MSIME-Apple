$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'pe_fixture.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('msime-pe-' + [Guid]::NewGuid())
$path = Join-Path $root 'synthetic image.bin'
$verify = Join-Path $PSScriptRoot '../Test-PortableExecutable.ps1'
try {
    foreach ($arch in @('x86', 'x64')) {
        foreach ($kind in @('exe', 'dll')) {
            Write-PEFixture $path $arch $kind
            & $verify -LiteralPath $path -Architecture $arch -Kind $kind
            $otherArch = if ($arch -eq 'x64') { 'x86' } else { 'x64' }
            $otherKind = if ($kind -eq 'exe') { 'dll' } else { 'exe' }
            foreach ($mismatch in @(@($otherArch, $kind), @($arch, $otherKind))) {
                $rejected = $false
                try { & $verify -LiteralPath $path -Architecture $mismatch[0] -Kind $mismatch[1] } catch { $rejected = $true }
                if (-not $rejected) { throw 'Mismatched image accepted' }
            }
        }
    }
    foreach ($offset in @(0, 60, 128, 148, 150, 152)) {
        Write-PEFixture $path
        $bytes = [IO.File]::ReadAllBytes($path)
        $bytes[$offset] = 0xff
        $bytes[$offset + 1] = 0xff
        [IO.File]::WriteAllBytes($path, $bytes)
        $rejected = $false
        try { & $verify -LiteralPath $path -Architecture x64 -Kind exe } catch { $rejected = $true }
        if (-not $rejected) { throw "Malformed header accepted at offset $offset" }
    }
    [IO.File]::WriteAllText($path, 'not an executable')
    $rejected = $false
    try { & $verify -LiteralPath $path -Architecture x64 -Kind exe } catch { $rejected = $true }
    if (-not $rejected) { throw 'Text file accepted' }
    Remove-Item -LiteralPath $path
    $rejected = $false
    try { & $verify -LiteralPath $path -Architecture x64 -Kind exe } catch { $rejected = $true }
    if (-not $rejected) { throw 'Missing image accepted' }
    Write-Output 'PE architecture, image kind and malformed header checks passed'
} finally {
    if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
