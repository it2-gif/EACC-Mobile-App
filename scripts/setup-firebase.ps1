# Run from project root after enabling Firebase Storage in the console.
# See scripts/SETUP.md for full instructions.

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

Set-Location $ProjectRoot

Write-Host "EACC Chat - Firebase setup" -ForegroundColor Cyan
Write-Host ""

Write-Host "Step 1: Deploy Firestore + Storage rules..." -ForegroundColor Yellow
& "$env:APPDATA\npm\firebase.cmd" deploy --only firestore:rules,storage --project eacc-mobile-app
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Storage deploy failed. Enable Storage first:" -ForegroundColor Red
    Write-Host "https://console.firebase.google.com/project/eacc-mobile-app/storage" -ForegroundColor White
    Write-Host ""
    Write-Host "Then run this script again." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Step 2: Configure Storage CORS..." -ForegroundColor Yellow

if (Get-Command gsutil -ErrorAction SilentlyContinue) {
    gsutil cors set storage.cors.json gs://eacc-mobile-app.firebasestorage.app
    gsutil cors get gs://eacc-mobile-app.firebasestorage.app
} else {
    Write-Host "gsutil not found on this machine." -ForegroundColor Yellow
    Write-Host "Use Google Cloud Shell instead:" -ForegroundColor Yellow
    Write-Host "  gsutil cors set storage.cors.json gs://eacc-mobile-app.firebasestorage.app"
    Write-Host ""
    Write-Host "See scripts/SETUP.md for details." -ForegroundColor White
}

Write-Host ""
Write-Host "Done. Run: flutter run -d chrome" -ForegroundColor Green
