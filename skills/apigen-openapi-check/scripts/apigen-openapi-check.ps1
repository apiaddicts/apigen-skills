#!/usr/bin/env pwsh
# Thin wrapper around apigen_openapi_check.py -- validates that an OpenAPI
# spec has what ApiGen's generator actually needs (ground-truth x-apigen-*
# rules, not just what the example specs suggest).
#
# Usage: ./apigen-openapi-check.ps1 -Spec <openapi-path>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Spec
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $py) {
    Write-Error "No se encontro python/python3 en el PATH. Este validador requiere Python 3 + PyYAML (pip install pyyaml)."
    exit 2
}

& $py.Source (Join-Path $ScriptDir "apigen_openapi_check.py") $Spec
exit $LASTEXITCODE
