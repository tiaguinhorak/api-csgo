# Dev: site local + CS na VPS — sync clutch_skins.txt via SCP
# Usage: .\sync-clutch-skins-dev.ps1
# Env (or set before run):
#   $env:CSGO_SKINS_SYNC_KEY = "..."
#   $env:CLUTCH_SITE_URL = "http://127.0.0.1:3000"
#   $env:CLUTCH_SSH_TARGET = "csgo@188.220.168.233"

$ErrorActionPreference = "Stop"

$SiteUrl = if ($env:CLUTCH_SITE_URL) { $env:CLUTCH_SITE_URL } else { "http://127.0.0.1:3000" }
$SyncKey = $env:CSGO_SKINS_SYNC_KEY
$SshTarget = if ($env:CLUTCH_SSH_TARGET) { $env:CLUTCH_SSH_TARGET } else { "csgo@188.220.168.233" }
$RemotePath = if ($env:CLUTCH_SSH_REMOTE) { $env:CLUTCH_SSH_REMOTE } else { "/home/csgo/server/csgo/addons/sourcemod/data/clutch_skins.txt" }
$LocalTmp = Join-Path $PSScriptRoot ".clutch_skins.tmp"

if (-not $SyncKey) {
  Write-Error "Set CSGO_SKINS_SYNC_KEY (same as site/.env)"
}

$exportUrl = "$SiteUrl/api/csgo/skins/export"
Write-Host "Fetching $exportUrl ..."

Invoke-WebRequest -Uri $exportUrl -Headers @{ "x-skins-sync-key" = $SyncKey } -OutFile $LocalTmp -UseBasicParsing

if ((Get-Item $LocalTmp).Length -eq 0) {
  Remove-Item $LocalTmp -Force
  Write-Error "Export empty — equip a skin on the local site first."
}

$remoteTmp = "${RemotePath}.tmp"
Write-Host "Uploading to ${SshTarget}:${RemotePath} ..."
scp $LocalTmp "${SshTarget}:${remoteTmp}"
ssh $SshTarget "mv -f '$remoteTmp' '$RemotePath' && chmod 644 '$RemotePath'"

Remove-Item $LocalTmp -Force
Write-Host "OK. On server console: sm_reloadclutchskins"
