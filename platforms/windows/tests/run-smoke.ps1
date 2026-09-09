param(
    [ValidateRange(1, 300)][int]$TimeoutSeconds = 30,
    [string]$ResourcesDirectory
)
$ErrorActionPreference = 'Stop'
# Run only isolated synthetic fixtures. No installation or TSF registration.
$tests = @(
    'windows-registration-inbox.exe', 'windows-focus-router.exe',
    'windows-main-frame.exe', 'windows-focus-gate.exe',
    'windows-input-queue.exe', 'windows-session-smoke.exe',
    'windows-reply-codec.exe', 'windows-reply-composer.exe',
    'windows-pipe-io.exe', 'windows-server-smoke.exe', 'windows-preview-config.exe'
)
$cases = @($tests | ForEach-Object {
    [PSCustomObject]@{ Name = $_; Label = $_; Arguments = '' }
})
$cases += [PSCustomObject]@{
    Name = 'msime-client-server.exe'; Label = 'preview-help'; Arguments = '--help'
}
if ($PSBoundParameters.ContainsKey('ResourcesDirectory')) {
    if ([string]::IsNullOrWhiteSpace($ResourcesDirectory)) {
        throw 'Resource directory must not be empty'
    }
    $resource = Resolve-Path -LiteralPath $ResourcesDirectory -ErrorAction Stop
    if ($resource.Provider.Name -ne 'FileSystem' -or
        -not [System.IO.Directory]::Exists($resource.ProviderPath) -or
        $resource.ProviderPath.Contains('"')) {
        throw 'Expected a filesystem resource directory'
    }
    # No shell expansion. End with dot so a trailing backslash cannot escape
    # the closing quote in the Windows native argument parser (also PS 5.1).
    $resourceArgument = '"' + $resource.ProviderPath.TrimEnd('\') + '\."'
    $cases += [PSCustomObject]@{
        Name = 'windows-session-smoke.exe'; Label = 'locked-dictionary-session'
        Arguments = $resourceArgument
    }
}
# Preflight every executable before starting any test.
foreach ($case in $cases) {
    $name = $case.Name
    $testPath = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
        throw "Missing test: $name"
    }
}
foreach ($case in $cases) {
    $name = $case.Name
    $process = New-Object System.Diagnostics.Process
    try {
        $process.StartInfo.FileName = Join-Path $PSScriptRoot $name
        $process.StartInfo.WorkingDirectory = $PSScriptRoot
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.Arguments = $case.Arguments
        if (-not $process.Start()) { throw "Could not start: $name" }
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            throw "Test timed out: $name"
        }
        if ($process.ExitCode -ne 0) {
            throw "Test failed: $name (exit $($process.ExitCode))"
        }
        Write-Host "PASS $($case.Label)"
    } finally {
        $process.Dispose()
    }
}
if (-not $PSBoundParameters.ContainsKey('ResourcesDirectory')) {
    Write-Host 'SKIP locked-dictionary-session: no ResourcesDirectory supplied'
}
Write-Host 'Synthetic native tests passed; this is not TSF/editor acceptance.'
