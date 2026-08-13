#!/usr/bin/env pwsh
# Wrapper around ApiGen's REST API (POST /generator/file).
# Usage: ./apigen-api.ps1 -Spec <openapi-path> -OutDir <outdir> [-Url <api-url>] [-Unzip]
#
# Required env var: $env:APIGEN_API_KEY (sent as the `apikey` header). Never
# pass the key as a script parameter or hardcode it here — it must only ever
# live in the environment.
# Required (env var or param): the target URL. $env:APIGEN_API_URL, or -Url.
# No default — there is no "well-known" endpoint; caller must always say
# which deployment to hit.

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Spec,

    [Alias('o')]
    [string]$OutDir = "./out",

    [string]$Url = $env:APIGEN_API_URL,

    [switch]$Unzip
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Spec -PathType Leaf)) {
    Write-Error "Spec not found: $Spec"
    exit 1
}

if (-not $env:APIGEN_API_KEY) {
    Write-Error 'APIGEN_API_KEY is not set. Set it before running this script: $env:APIGEN_API_KEY = "<your-key>"'
    exit 1
}

if (-not $Url) {
    Write-Error 'No target URL given. Set $env:APIGEN_API_URL or pass -Url <deployed-endpoint>.'
    exit 1
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$name = [System.IO.Path]::GetFileNameWithoutExtension($Spec)
$zipPath = Join-Path $OutDir "$name.zip"

Write-Host "POST $Url"
Write-Host "  file=$Spec"

try {
    Invoke-WebRequest -Uri $Url -Method Post -Headers @{ apikey = $env:APIGEN_API_KEY; accept = "*/*" } `
        -Form @{ file = Get-Item $Spec } -OutFile $zipPath
} catch {
    $resp = $_.Exception.Response
    if ($resp) {
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        Write-Error "Request failed ($($resp.StatusCode)): $($reader.ReadToEnd())"
    } else {
        Write-Error $_.Exception.Message
    }
    exit 1
}

Write-Host "OK -> $zipPath"

if ($Unzip) {
    $dest = Join-Path $OutDir $name
    Expand-Archive -Path $zipPath -DestinationPath $dest -Force
    Write-Host "Unzipped -> $dest"
}
