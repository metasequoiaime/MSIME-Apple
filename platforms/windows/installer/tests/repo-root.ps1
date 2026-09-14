$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$source = (Resolve-Path (Join-Path $PSScriptRoot '../Prepare-PackageFiles.ps1')).Path
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Packaging script has syntax errors' }
$parameter = @($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'RepoRoot' })
if ($parameter.Count -ne 1) { throw 'Missing RepoRoot parameter' }
# Evaluate only the real parameter declaration, never the packaging side effects.
$literal = "'" + (Split-Path -Parent $source).Replace("'", "''") + "'"
$declaration = $parameter[0].Extent.Text.Replace('$PSScriptRoot', $literal)
$probe = [scriptblock]::Create('param(' + $declaration + ') $RepoRoot')
$expected = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
Push-Location ([IO.Path]::GetTempPath())
try {
    if ((& $probe) -ne $expected) { throw 'Default RepoRoot does not resolve to repository root' }
    $override = Join-Path ([IO.Path]::GetTempPath()) 'synthetic-custom-package-root'
    if ((& $probe -RepoRoot $override) -ne $override) { throw 'Explicit RepoRoot was changed' }
} finally { Pop-Location }
Write-Output 'Packaging root defaults and override passed'
