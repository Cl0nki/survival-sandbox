# Launches one dedicated server and two clients for Survival Sandbox.
# Manual play (two windows):
#   powershell -ExecutionPolicy Bypass -File tools\start_multiplayer.ps1
# Headless connection check:
#   powershell -ExecutionPolicy Bypass -File tools\start_multiplayer.ps1 -Automated

param(
    [int]$Port = 7777,
    [string]$Address = "127.0.0.1",
    [switch]$Automated
)

$ErrorActionPreference = "Stop"
$Project = Split-Path -Parent $PSScriptRoot
$GodotDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
$Gui = if ($env:GODOT_GUI) { $env:GODOT_GUI } else { Join-Path $GodotDir "Godot_v4.7.2-stable_win64.exe" }
$Console = if ($env:GODOT_CONSOLE) { $env:GODOT_CONSOLE } else { Join-Path $GodotDir "Godot_v4.7.2-stable_win64_console.exe" }

if (-not (Test-Path $Console)) {
    Write-Error "Godot console build not found: $Console"
}
if (-not $Automated -and -not (Test-Path $Gui)) {
    Write-Error "Godot editor/player build not found: $Gui"
}

function Get-FreeUdpPort {
    $udp = New-Object System.Net.Sockets.UdpClient(0)
    $selected = ([System.Net.IPEndPoint]$udp.Client.LocalEndPoint).Port
    $udp.Close()
    return $selected
}

if ($Automated -and -not $PSBoundParameters.ContainsKey("Port")) {
    $Port = Get-FreeUdpPort
}

$RunId = [guid]::NewGuid().ToString("N")
$ServerStatus = Join-Path $env:TEMP "survival-sandbox-$RunId-server.txt"
$ClientAStatus = Join-Path $env:TEMP "survival-sandbox-$RunId-client-a.txt"
$ClientBStatus = Join-Path $env:TEMP "survival-sandbox-$RunId-client-b.txt"
$ServerOut = Join-Path $env:TEMP "survival-sandbox-$RunId-server.out"
$ServerErr = Join-Path $env:TEMP "survival-sandbox-$RunId-server.err"
$ClientAOut = Join-Path $env:TEMP "survival-sandbox-$RunId-client-a.out"
$ClientAErr = Join-Path $env:TEMP "survival-sandbox-$RunId-client-a.err"
$ClientBOut = Join-Path $env:TEMP "survival-sandbox-$RunId-client-b.out"
$ClientBErr = Join-Path $env:TEMP "survival-sandbox-$RunId-client-b.err"

$ServerArgs = @(
    "--headless", "--path", $Project, "--",
    "--server", "--port", "$Port", "--status-file", $ServerStatus
)
$ClientExecutable = if ($Automated) { $Console } else { $Gui }
$ClientPrefix = @("--path", $Project, "--")
if ($Automated) {
    $ClientPrefix = @("--headless", "--path", $Project, "--")
}
$ClientAArgs = $ClientPrefix + @(
    "--client", "--address", $Address, "--port", "$Port",
    "--window-x", "40", "--window-y", "40",
    "--status-file", $ClientAStatus
)
$ClientBArgs = $ClientPrefix + @(
    "--client", "--address", $Address, "--port", "$Port",
    "--window-x", "700", "--window-y", "40",
    "--status-file", $ClientBStatus
)
if ($Automated) {
    $ClientAArgs += @("--bot", "--expect-peers", "2")
    $ClientBArgs += @("--bot", "--expect-peers", "2")
}

Write-Host "Server:"
Write-Host "$Console $($ServerArgs -join ' ')"
Write-Host "Client A:"
Write-Host "$ClientExecutable $($ClientAArgs -join ' ')"
Write-Host "Client B:"
Write-Host "$ClientExecutable $($ClientBArgs -join ' ')"

$processes = @()

function Stop-TrackedProcesses {
    foreach ($proc in $processes) {
        if ($null -ne $proc -and -not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

function Wait-ForText {
    param([string]$Path, [string]$Pattern, [int]$TimeoutSec)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $Path) {
            $text = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
            if ($text -and $text.Contains($Pattern)) {
                return $text
            }
        }
        Start-Sleep -Milliseconds 200
    }
    return $null
}

try {
    $server = Start-Process -FilePath $Console -ArgumentList $ServerArgs -WorkingDirectory $Project -WindowStyle Hidden -RedirectStandardOutput $ServerOut -RedirectStandardError $ServerErr -PassThru
    $processes += $server
    $ready = Wait-ForText -Path $ServerStatus -Pattern "SERVER_READY" -TimeoutSec 25
    if (-not $ready) {
        $failed = ""
        if (Test-Path $ServerStatus) { $failed = Get-Content -Path $ServerStatus -Raw -ErrorAction SilentlyContinue }
        Write-Host "Server did not become ready."
        Write-Host $failed
        if (Test-Path $ServerErr) { Get-Content $ServerErr -ErrorAction SilentlyContinue | Write-Host }
        if (Test-Path $ServerOut) { Get-Content $ServerOut -ErrorAction SilentlyContinue | Write-Host }
        exit 1
    }
    Write-Host $ready.Trim()

    $clientA = $null
    $clientB = $null
    if ($Automated) {
        $clientA = Start-Process -FilePath $Console -ArgumentList $ClientAArgs -WorkingDirectory $Project -WindowStyle Hidden -RedirectStandardOutput $ClientAOut -RedirectStandardError $ClientAErr -PassThru
        $processes += $clientA
        Start-Sleep -Milliseconds 400
        $clientB = Start-Process -FilePath $Console -ArgumentList $ClientBArgs -WorkingDirectory $Project -WindowStyle Hidden -RedirectStandardOutput $ClientBOut -RedirectStandardError $ClientBErr -PassThru
        $processes += $clientB
    } else {
        $clientA = Start-Process -FilePath $Gui -ArgumentList $ClientAArgs -WorkingDirectory $Project -PassThru
        $processes += $clientA
        Start-Sleep -Milliseconds 400
        $clientB = Start-Process -FilePath $Gui -ArgumentList $ClientBArgs -WorkingDirectory $Project -PassThru
        $processes += $clientB
    }

    if (-not $Automated) {
        Write-Host "Server PID $($server.Id), client A PID $($clientA.Id), client B PID $($clientB.Id)."
        Write-Host "Close the client windows to disconnect. Stop the server with: Stop-Process -Id $($server.Id)"
        exit 0
    }

    $resultA = Wait-ForText -Path $ClientAStatus -Pattern "BOT_" -TimeoutSec 25
    $resultB = Wait-ForText -Path $ClientBStatus -Pattern "BOT_" -TimeoutSec 25
    $textA = if ($resultA) { $resultA } else { "" }
    $textB = if ($resultB) { $resultB } else { "" }
    if ($textA -notlike "*BOT_OK*" -or $textB -notlike "*BOT_OK*") {
        Write-Host "Automated clients failed."
        Write-Host "CLIENT A: $textA"
        Write-Host "CLIENT B: $textB"
        foreach ($log in @($ClientAErr, $ClientAOut, $ClientBErr, $ClientBOut, $ServerErr, $ServerOut, $ServerStatus)) {
            if (Test-Path $log) {
                Write-Host "---- $log"
                Get-Content $log -ErrorAction SilentlyContinue | Write-Host
            }
        }
        exit 1
    }
    Write-Host $textA.Trim()
    Write-Host $textB.Trim()

    $exitDeadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $exitDeadline -and (-not $clientA.HasExited -or -not $clientB.HasExited)) {
        Start-Sleep -Milliseconds 200
    }
    $disconnected = Wait-ForText -Path $ServerStatus -Pattern "peer disconnected" -TimeoutSec 8
    $despawned = Wait-ForText -Path $ServerStatus -Pattern "despawned player" -TimeoutSec 2
    if ($server.HasExited) {
        Write-Host "Server exited during the client disconnect."
        if (Test-Path $ServerErr) { Get-Content $ServerErr | Write-Host }
        exit 1
    }
    if (-not $disconnected -or -not $despawned) {
        Write-Host "Server did not record a disconnect."
        if (Test-Path $ServerStatus) { Get-Content $ServerStatus | Write-Host }
        exit 1
    }
    Write-Host "Server still running after client disconnect."
    Write-Host "AUTOMATED_MULTIPLAYER_OK"
    exit 0
}
finally {
    if ($Automated) {
        Stop-TrackedProcesses
    }
}
