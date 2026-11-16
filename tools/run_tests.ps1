# Runs every headless regression test and prints one PASS/FAIL line each.
#   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
#   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -Only milestone8
#   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -Refresh   (rebuild the class cache first)
#   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -Slow      (adds stress tests)
#   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -Strict    (known baseline failures count)
# Capture tests (they render and write PNGs) and the two-process check are not
# included. Run `tools\start_multiplayer.ps1 -Automated` for the latter.
# Exit code is the number of failed tests.

param(
    [string]$Only = "",
    [switch]$Slow,
    [switch]$Refresh,
    [switch]$Strict,
    [int]$TimeoutSec = 120
)

$ErrorActionPreference = "Stop"
$Project = Split-Path -Parent $PSScriptRoot
$GodotDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
$Console = if ($env:GODOT_CONSOLE) { $env:GODOT_CONSOLE } else { Join-Path $GodotDir "Godot_v4.7.2-stable_win64_console.exe" }
if (-not (Test-Path $Console)) {
    Write-Error "Godot console build not found: $Console"
}

# script name, success marker ("" means exit code 0 is the only signal)
$Tests = @(
    @("milestone1_smoke", "MILESTONE1_SMOKE_OK"),
    @("milestone2_net", "MILESTONE2_NET_OK"),
    @("milestone3_visibility", "MILESTONE3_VISIBILITY_OK"),
    @("milestone4_inventory", "MILESTONE4_INVENTORY_OK"),
    @("milestone7_persist", "MILESTONE7_PERSIST_OK"),
    @("milestone8_death", "MILESTONE8_DEATH_OK"),
    @("milestone9_hog", "MILESTONE9_HOG_OK"),
    @("items_catalog", "ITEMS_CATALOG_OK"),
    @("crafting", "CRAFTING_OK"),
    @("smelting", "SMELTING_OK"),
    @("deployables", "DEPLOYABLES_OK"),
    @("fill_stations", "FILL_STATIONS_OK"),
    @("ground_deposits", "GROUND_DEPOSITS_OK"),
    @("harvest_nodes", "HARVEST_NODES_OK"),
    @("world_props", "WORLD_PROPS_OK"),
    @("survival_map_smoke", "SURVIVAL_MAP_SMOKE_OK"),
    @("machine_shop_fit_smoke", "MACHINE_SHOP_FIT_OK"),
    @("workbench_art_smoke", "WORKBENCH_ART_OK"),
    @("pickup_visual", "PICKUP_VISUAL_OK"),
    @("held_firearm", ""),
    @("sfx", "SFX_OK"),
    @("building_phase1", "BUILDING_PHASE1_OK"),
    @("building_phase2", "BUILDING_PHASE2_OK"),
    @("building_phase3", "BUILDING_PHASE3_OK"),
    @("building_phase4", "BUILDING_PHASE4_OK")
)
# Tests that are known to fail, as name = reason. They print KNOWN and are not
# counted, so a new regression is the only thing that turns the run red.
# -Strict counts them. Empty on purpose: add a line only for a failure you accept
# for now, and delete it when the test is fixed.
$Known = @{}
if ($Slow) {
    $Tests += , @("building_stress", "BUILDING_STRESS_OK")
}
if ($Only -ne "") {
    $Tests = @($Tests | Where-Object { $_[0] -like "*$Only*" })
}

function Invoke-Godot([string[]]$GodotArgs, [string]$LogPath, [int]$Timeout) {
    $err = "$LogPath.err"
    $proc = Start-Process -FilePath $Console -ArgumentList $GodotArgs -NoNewWindow -PassThru `
        -RedirectStandardOutput $LogPath -RedirectStandardError $err
    # Without touching the handle, ExitCode can come back empty after WaitForExit.
    $null = $proc.Handle
    if (-not $proc.WaitForExit($Timeout * 1000)) {
        try { $proc.Kill() } catch {}
        return -999
    }
    return $proc.ExitCode
}

if ($Refresh) {
    Write-Host "Refreshing class cache..."
    $log = Join-Path $env:TEMP "survival-sandbox-refresh.txt"
    [void](Invoke-Godot @("--headless", "--editor", "--quit", "--path", $Project) $log 180)
}

$failed = 0
$knownCount = 0
$ran = 0
foreach ($test in $Tests) {
    $name = $test[0]
    $marker = $test[1]
    $script = Join-Path $Project "tests\$name.gd"
    if (-not (Test-Path $script)) {
        # milestone8_death arrives with Phase 1. Anything else missing is a mistake.
        if ($name -like "milestone8*") { continue }
        Write-Host ("SKIP  {0}  (missing)" -f $name)
        continue
    }
    $ran++
    $log = Join-Path $env:TEMP "survival-sandbox-test-$name.txt"
    $started = Get-Date
    $code = Invoke-Godot @("--headless", "--path", $Project, "--script", "res://tests/$name.gd") $log $TimeoutSec
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    $text = ""
    if (Test-Path $log) { $text = Get-Content $log -Raw }
    $ok = ($code -eq 0)
    if ($ok -and $marker -ne "") { $ok = $text -match [regex]::Escape($marker) }
    if ($ok) {
        Write-Host ("PASS  {0}  ({1}s)" -f $name, $seconds)
    } else {
        $why = if ($code -eq -999) { "timeout" } elseif ($code -ne 0) { "exit $code" } else { "marker $marker missing" }
        if ($Known.ContainsKey($name) -and -not $Strict) {
            $knownCount++
            Write-Host ("KNOWN {0}  ({1}s, {2})  baseline: {3}" -f $name, $seconds, $why, $Known[$name])
        } else {
            $failed++
            Write-Host ("FAIL  {0}  ({1}s, {2})  log: {3}" -f $name, $seconds, $why, $log)
        }
    }
}
Write-Host ("{0} run, {1} failed, {2} known baseline failures" -f $ran, $failed, $knownCount)
exit $failed
