# Clutch local dev bootstrap (Windows — site + api-csgo; CS:GO in WSL)
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$SiteRoot = Join-Path (Split-Path -Parent $RepoRoot) "site"

Write-Host "=== Clutch setup-local-dev (Windows) ===" -ForegroundColor Cyan

$ApiEnvLocal = Join-Path $RepoRoot ".env.local.example"
$ApiEnv = Join-Path $RepoRoot ".env"
if (-not (Test-Path $ApiEnv)) {
  if (Test-Path $ApiEnvLocal) { Copy-Item $ApiEnvLocal $ApiEnv }
  else { Copy-Item (Join-Path $RepoRoot ".env.example") $ApiEnv }
  Write-Host "Created api-csgo/.env"
} else {
  Write-Host "api-csgo/.env exists"
}

if (Test-Path $SiteRoot) {
  $SiteEnvLocal = Join-Path $SiteRoot ".env.local.example"
  $SiteEnv = Join-Path $SiteRoot ".env"
  if (-not (Test-Path $SiteEnv) -and (Test-Path $SiteEnvLocal)) {
    Copy-Item $SiteEnvLocal $SiteEnv
    Write-Host "Created site/.env — edit DATABASE_URL and STEAM_API_KEY"
  }
}

Push-Location $RepoRoot
npm install
npm run build
Pop-Location

Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. WSL: install CS:GO — see LOCAL-DEV.md"
Write-Host "  2. Edit site/.env and api-csgo/.env (same CSGO_SKINS_SYNC_KEY)"
Write-Host "  3. api-csgo: npm run pm2:start  (or run in WSL for simpler paths)"
Write-Host "  4. site: npm run dev"
Write-Host "  5. WSL: bash scripts/verify-local-stack.sh"
Write-Host ""
Write-Host "Guide: CsgoPage/LOCAL-DEV.md"
