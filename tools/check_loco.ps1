# Rebuild shared loco library (optional) and run headless loco QA.
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\check_loco.ps1
#   powershell -ExecutionPolicy Bypass -File tools\check_loco.ps1 -Rebuild
#   powershell -ExecutionPolicy Bypass -File tools\check_loco.ps1 -Capture

param(
    [switch]$Rebuild,
    [switch]$Capture
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$GodotDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
$Console = if ($env:GODOT_CONSOLE) { $env:GODOT_CONSOLE } else { Join-Path $GodotDir "Godot_v4.7.2-stable_win64_console.exe" }
$Gui = if ($env:GODOT_GUI) { $env:GODOT_GUI } else { Join-Path $GodotDir "Godot_v4.7.2-stable_win64.exe" }

if (-not (Test-Path $Console)) {
    throw "Godot console not found: $Console"
}

Push-Location $Root
try {
    if ($Rebuild) {
        Write-Host "=== rebuild loco library ==="
        & $Console --path $Root --headless -s res://tools/merge_ual_pro_crouch.gd
        if ($LASTEXITCODE -ne 0) { throw "merge_ual_pro_crouch failed ($LASTEXITCODE)" }
        & $Console --path $Root --headless -s res://tools/merge_ual2_strafe_clips.gd
        if ($LASTEXITCODE -ne 0) { throw "merge_ual2_strafe_clips failed ($LASTEXITCODE)" }
    }

    Write-Host "=== loco QA (headless) ==="
    & $Console --path $Root --headless --script res://tests/loco_qa.gd
    $qa = $LASTEXITCODE
    if ($qa -ne 0) {
        Write-Host "LOCO_QA failed with exit $qa"
    }

    if ($Capture) {
        if (-not (Test-Path $Gui)) { throw "Godot GUI not found for capture: $Gui" }
        Write-Host "=== loco capture (needs window) ==="
        & $Gui --path $Root --resolution 1280x720 --script res://tests/loco_capture.gd
        Write-Host "Shots: $env:APPDATA\Godot\app_userdata\Survival Sandbox\loco_shots  (or project user://loco_shots)"
    }

    Write-Host "Preview scene: res://scenes/debug/loco_preview.tscn"
    exit $qa
}
finally {
    Pop-Location
}
