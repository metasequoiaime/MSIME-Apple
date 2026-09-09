param([ValidateRange(1, 300)][int]$TimeoutSeconds = 30)
$ErrorActionPreference = 'Stop'
# Run only isolated synthetic fixtures. No installation or TSF registration.
$tests = @(
    'windows-registration-inbox.exe', 'windows-focus-router.exe',
    'windows-main-frame.exe', 'windows-focus-gate.exe',
    'windows-input-queue.exe', 'windows-session-smoke.exe',
    'windows-reply-codec.exe', 'windows-reply-composer.exe',
    'windows-pipe-io.exe', 'windows-server-smoke.exe', 'windows-preview-config.exe'
)
foreach ($name in $tests) {
    $testPath = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
        throw "Missing test: $name"
    }
}
foreach ($name in $tests) {
    $process = New-Object System.Diagnostics.Process
    try {
        $process.StartInfo.FileName = Join-Path $PSScriptRoot $name
        $process.StartInfo.WorkingDirectory = $PSScriptRoot
        $process.StartInfo.UseShellExecute = $false
        if (-not $process.Start()) { throw "Could not start: $name" }
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            throw "Test timed out: $name"
        }
        if ($process.ExitCode -ne 0) {
            throw "Test failed: $name (exit $($process.ExitCode))"
        }
        Write-Host "PASS $name"
    } finally {
        $process.Dispose()
    }
}
Write-Host 'Synthetic native tests passed; this is not TSF/editor acceptance.'
