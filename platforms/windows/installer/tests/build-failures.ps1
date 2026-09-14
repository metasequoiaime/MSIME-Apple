# Preserve the historical regression entry while testing the Client pipeline.
# The legacy component build scripts no longer exist in this repository.
& (Join-Path $PSScriptRoot 'installer_entry.ps1')
