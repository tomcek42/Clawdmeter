<#
.SYNOPSIS
    Kompiliert die Clawdmeter-Firmware für das Waveshare ESP32-S3-Touch-LCD-1.54
    und flasht sie auf das angeschlossene Gerät.

.PARAMETER Rotation
    Optional: Display-Drehung 0-3 (0 = Original, 1 = 90° im Uhrzeigersinn,
    2 = 180°, 3 = 90° gegen den Uhrzeigersinn). Ohne Angabe gilt der Wert
    aus board.h (LCD_ROTATION).

.PARAMETER Port
    Optional: COM-Port, z. B. COM5. Ohne Angabe wird ein ESP32-S3 (USB-VID 303A)
    automatisch gesucht.

.PARAMETER BuildOnly
    Nur kompilieren, nicht flashen.

.PARAMETER Monitor
    Nach dem Flashen den seriellen Monitor öffnen (Beenden mit Strg+C).

.EXAMPLE
    .\tools\flash-lcd154.ps1
    .\tools\flash-lcd154.ps1 -Rotation 1
    .\tools\flash-lcd154.ps1 -Port COM7 -Monitor
    .\tools\flash-lcd154.ps1 -BuildOnly
#>
[CmdletBinding()]
param(
    [ValidateRange(0, 3)]
    [Nullable[int]]$Rotation,
    [string]$Port,
    [switch]$BuildOnly,
    [switch]$Monitor
)

$ErrorActionPreference = 'Stop'
$Env       = 'waveshare_lcd_154'
$RepoDir   = Split-Path $PSScriptRoot -Parent   # tools/ -> repo root
$Firmware  = Join-Path $RepoDir 'firmware'

# --- PlatformIO finden ---
$pio = (Get-Command pio -ErrorAction SilentlyContinue).Source
if (-not $pio) {
    $candidate = Join-Path $env:USERPROFILE '.local\bin\pio.exe'
    if (Test-Path $candidate) { $pio = $candidate }
}
if (-not $pio) {
    throw "PlatformIO (pio) nicht gefunden. Installieren mit: uv tool install --python 3.13 platformio"
}
if (-not (Test-Path (Join-Path $Firmware 'platformio.ini'))) {
    throw "Firmware-Verzeichnis nicht gefunden: $Firmware"
}

# Der ESP-Toolinstaller verweigert MSYS/Git-Bash-Umgebungen.
Remove-Item Env:MSYSTEM -ErrorAction SilentlyContinue

# --- Optionale Drehung als Build-Flag (überschreibt board.h) ---
if ($null -ne $Rotation) {
    $env:PLATFORMIO_BUILD_FLAGS = "-DLCD_ROTATION=$Rotation"
    Write-Host "Drehung: LCD_ROTATION=$Rotation (überschreibt board.h)" -ForegroundColor Cyan
} else {
    Remove-Item Env:PLATFORMIO_BUILD_FLAGS -ErrorAction SilentlyContinue
    Write-Host "Drehung: Wert aus board.h" -ForegroundColor Cyan
}

# --- Kompilieren ---
Write-Host "`n==> Kompiliere $Env ..." -ForegroundColor Yellow
& $pio run -d $Firmware -e $Env
if ($LASTEXITCODE -ne 0) { throw "Kompilieren fehlgeschlagen (Exit-Code $LASTEXITCODE)." }

$buildDir = Join-Path $Firmware ".pio\build\$Env"
Write-Host "Firmware: $buildDir\firmware.factory.bin" -ForegroundColor Green

if ($BuildOnly) { return }

# --- Port ermitteln ---
if (-not $Port) {
    $devices = & $pio device list --json-output | ConvertFrom-Json
    $esp = @($devices | Where-Object { $_.hwid -match 'VID:PID=303A:' })
    if ($esp.Count -eq 0) {
        throw "Kein ESP32-S3 gefunden. Gerät per USB-C anschließen (ggf. BOOT-Taste beim Einstecken halten) oder -Port angeben."
    }
    if ($esp.Count -gt 1) {
        Write-Warning "Mehrere ESP32 gefunden: $($esp.port -join ', ') - nehme $($esp[0].port). Mit -Port gezielt wählen."
    }
    $Port = $esp[0].port
}
Write-Host "Port: $Port" -ForegroundColor Cyan

# --- Flashen ---
Write-Host "`n==> Flashe auf $Port ..." -ForegroundColor Yellow
& $pio run -d $Firmware -e $Env -t upload --upload-port $Port
if ($LASTEXITCODE -ne 0) { throw "Flashen fehlgeschlagen (Exit-Code $LASTEXITCODE)." }
Write-Host "`nFertig." -ForegroundColor Green

if ($Monitor) {
    & $pio device monitor -d $Firmware -e $Env -p $Port
}
