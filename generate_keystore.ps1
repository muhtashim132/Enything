<#
.SYNOPSIS
Generates an Android release keystore (upload-keystore.jks) securely.
.DESCRIPTION
This script uses the Java keytool to generate a keystore for Google Play Store upload.
Make sure you have Java installed and 'keytool' is in your PATH.
#>

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Enything - Android Keystore Generator" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT: Remember the passwords you set here!" -ForegroundColor Yellow
Write-Host "They must match the ones you put in android/key.properties" -ForegroundColor Yellow
Write-Host ""

$appDir = "android/app"
$keystorePath = "$appDir/upload-keystore.jks"

if (Test-Path $keystorePath) {
    Write-Host "ERROR: $keystorePath already exists!" -ForegroundColor Red
    Write-Host "Delete it first if you want to generate a new one." -ForegroundColor Red
    exit 1
}

keytool -genkey -v -keystore $keystorePath -keyalg RSA -keysize 2048 -validity 10000 -alias upload

if ($?) {
    Write-Host "`nSUCCESS: Keystore generated at $keystorePath" -ForegroundColor Green
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Open android/key.properties"
    Write-Host "2. Fill in the passwords you just created."
} else {
    Write-Host "`nERROR: Keystore generation failed. Ensure Java is installed." -ForegroundColor Red
}
