$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Error "Flutter SDK not found. Install Flutter and add it to PATH, then re-run."
  exit 1
}
Set-Location $root
flutter create . --platforms=android --project-name walkietalkie_mobile
