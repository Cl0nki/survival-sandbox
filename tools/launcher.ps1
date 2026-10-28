# Survival Sandbox session window.
# Double-click tools\launcher.vbs so no console stays open.
# Smoke check (starts and stops a server on a free port):
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File tools\launcher.ps1 -Smoke

param([switch]$Smoke)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:Project = Split-Path -Parent $PSScriptRoot
$GodotDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
$script:Gui = if ($env:GODOT_GUI) { $env:GODOT_GUI } else { Join-Path $GodotDir "Godot_v4.7.2-stable_win64.exe" }
$script:Console = if ($env:GODOT_CONSOLE) { $env:GODOT_CONSOLE } else { Join-Path $GodotDir "Godot_v4.7.2-stable_win64_console.exe" }
$script:StatusPath = ""
$script:ClientSlot = 0
$script:Busy = $false
$script:Slots = @(
    @(40, 40),
    @(720, 40),
    @(40, 460),
    @(720, 460)
)

function Write-Log {
    param([string]$Message)
    $line = "{0:HH:mm:ss}  {1}" -f (Get-Date), $Message
    if ($script:LogBox) {
        $script:LogBox.AppendText($line + [Environment]::NewLine)
    } else {
        Write-Host $line
    }
}

function Get-ProjectProcesses {
    param([string]$Role, [string]$StatusFile = "")
    $found = @()
    $procs = Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" -ErrorAction SilentlyContinue
    foreach ($proc in $procs) {
        $cmd = [string]$proc.CommandLine
        if (-not $cmd) { continue }
        if ($cmd -notlike "*$($script:Project)*") { continue }
        if ($cmd -notlike "*--$Role*") { continue }
        if ($StatusFile -and $cmd -notlike "*$StatusFile*") { continue }
        $found += $proc
    }
    return $found
}

function Stop-ProjectProcesses {
    param([string]$Role, [string]$StatusFile = "")
    $procs = @(Get-ProjectProcesses -Role $Role -StatusFile $StatusFile)
    foreach ($proc in $procs) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
    if ($procs.Count -gt 0) {
        Start-Sleep -Milliseconds 400
    }
    return $procs.Count
}

function Read-PortFromCommand {
    param([string]$Command)
    if ($Command -match "--port\s+(\d+)") {
        return [int]$Matches[1]
    }
    return 0
}

function Read-StatusFromCommand {
    param([string]$Command)
    if ($Command -match "--status-file\s+(\S+)") {
        return $Matches[1].Trim('"')
    }
    return ""
}

function Get-ServerState {
    $procs = @(Get-ProjectProcesses -Role "server")
    if ($procs.Count -eq 0) {
        return @{ Running = $false; Port = 0; StatusFile = ""; Count = 0; Ready = $false }
    }
    $cmd = [string]$procs[0].CommandLine
    $port = Read-PortFromCommand $cmd
    $status = Read-StatusFromCommand $cmd
    if ($status) { $script:StatusPath = $status }
    $ready = $false
    if ($status -and (Test-Path $status)) {
        $text = Get-Content -Path $status -Raw -ErrorAction SilentlyContinue
        $ready = $text -and $text.Contains("SERVER_READY")
    }
    $ports = @($procs | ForEach-Object { Read-PortFromCommand ([string]$_.CommandLine) } | Where-Object { $_ -gt 0 } | Select-Object -Unique)
    return @{ Running = $true; Port = $port; Ports = $ports; StatusFile = $status; Count = $procs.Count; Ready = $ready }
}

function Wait-ServerReady {
    param([string]$Path, [int]$TimeoutSec = 20)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ($script:LogBox) { [System.Windows.Forms.Application]::DoEvents() }
        if (Test-Path $Path) {
            $text = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
            if ($text -and $text.Contains("SERVER_READY")) { return "ready" }
            if ($text -and $text.Contains("SERVER_FAILED")) { return "failed" }
        }
        Start-Sleep -Milliseconds 150
    }
    return "timeout"
}

function Start-SandboxServer {
    param([int]$Port, [switch]$AllowExisting)
    if (-not (Test-Path $script:Console)) {
        Write-Log "Godot console build was not found."
        return $false
    }
    if (-not $AllowExisting) {
        $existing = Get-ServerState
        if ($existing.Running) {
            Write-Log "A server is already running on port $($existing.Port). Use Restart to replace it."
            return $false
        }
    }
    $script:StatusPath = Join-Path $env:TEMP ("survival-sandbox-launcher-{0}-server.txt" -f $Port)
    if (Test-Path $script:StatusPath) { Remove-Item $script:StatusPath -Force -ErrorAction SilentlyContinue }
    Write-Log "Starting server on port $Port."
    $args = @(
        "--headless", "--path", $script:Project, "--",
        "--server", "--port", "$Port", "--status-file", $script:StatusPath
    )
    Start-Process -FilePath $script:Console -ArgumentList $args -WorkingDirectory $script:Project -WindowStyle Hidden | Out-Null
    $result = Wait-ServerReady -Path $script:StatusPath
    if ($result -eq "ready") {
        Write-Log "Server is ready on port $Port."
        return $true
    }
    $detail = ""
    if (Test-Path $script:StatusPath) {
        $detail = (Get-Content -Path $script:StatusPath -Raw -ErrorAction SilentlyContinue)
    }
    Write-Log "Server did not start ($result). $detail"
    Stop-ProjectProcesses -Role "server" -StatusFile $script:StatusPath | Out-Null
    return $false
}

function Restart-SandboxServer {
    param([int]$Port)
    Write-Log "Restarting server."
    $removed = Stop-ProjectProcesses -Role "server"
    if ($removed -gt 0) { Write-Log "Stopped $removed server process(es)." }
    return Start-SandboxServer -Port $Port
}

function Start-SandboxClient {
    param([string]$Address, [int]$Port)
    if (-not (Test-Path $script:Gui)) {
        Write-Log "Godot player build was not found."
        return $false
    }
    $slot = $script:Slots[$script:ClientSlot % $script:Slots.Count]
    $script:ClientSlot++
    $status = Join-Path $env:TEMP ("survival-sandbox-launcher-client-{0}.txt" -f ([guid]::NewGuid().ToString("N")))
    $args = @(
        "--path", $script:Project, "--",
        "--client", "--address", $Address, "--port", "$Port",
        "--window-x", "$($slot[0])", "--window-y", "$($slot[1])",
        "--status-file", $status
    )
    Start-Process -FilePath $script:Gui -ArgumentList $args -WorkingDirectory $script:Project | Out-Null
    Write-Log "Opened a client for ${Address}:${Port}."
    return $true
}

## No network flags: the arena runs in local mode, the only mode with building.
function Start-SandboxLocal {
    if (-not (Test-Path $script:Gui)) {
        Write-Log "Godot player build was not found."
        return $false
    }
    Start-Process -FilePath $script:Gui -ArgumentList @("--path", $script:Project) -WorkingDirectory $script:Project | Out-Null
    Write-Log "Opened a local game. Building works here."
    return $true
}

function Update-StatusLabel {
    if (-not $script:StatusLabel) { return }
    $state = Get-ServerState
    $clients = @(Get-ProjectProcesses -Role "client").Count
    if (-not $state.Running) {
        $script:StatusLabel.Text = "Server stopped. Clients open: $clients"
        $script:StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(120, 40, 40)
        return
    }
    $readyText = if ($state.Ready) { "ready" } else { "starting" }
    $ports = @($state.Ports)
    $extra = if ($ports.Count -gt 1) { " Warning: servers on ports $($ports -join ', ')." } else { "" }
    $script:StatusLabel.Text = "Server $readyText on port $($state.Port). Clients open: $clients$extra"
    $script:StatusLabel.ForeColor = if ($state.Ready) {
        [System.Drawing.Color]::FromArgb(20, 90, 40)
    } else {
        [System.Drawing.Color]::FromArgb(120, 80, 20)
    }
}

function Read-LaunchFields {
    $address = $script:AddressBox.Text.Trim()
    $portText = $script:PortBox.Text.Trim()
    if (-not $address) { throw "Address is empty." }
    if ($portText -notmatch "^\d+$") { throw "Port must be a number." }
    $port = [int]$portText
    if ($port -lt 1 -or $port -gt 65535) { throw "Port must be 1-65535." }
    return @{ Address = $address; Port = $port }
}

function Invoke-LauncherAction {
    param([scriptblock]$Action)
    if ($script:Busy) { return }
    $script:Busy = $true
    try {
        & $Action
    } catch {
        Write-Log $_.Exception.Message
    } finally {
        $script:Busy = $false
        Update-StatusLabel
    }
}

if ($Smoke) {
    function Get-FreeUdpPort {
        $udp = New-Object System.Net.Sockets.UdpClient(0)
        $selected = ([System.Net.IPEndPoint]$udp.Client.LocalEndPoint).Port
        $udp.Close()
        return $selected
    }
    $port = Get-FreeUdpPort
    if (-not (Start-SandboxServer -Port $port -AllowExisting)) { exit 1 }
    $owned = $script:StatusPath
    $match = @(Get-ProjectProcesses -Role "server" -StatusFile $owned)
    if ($match.Count -lt 1) {
        Write-Log "Smoke server was not visible."
        exit 1
    }
    Stop-ProjectProcesses -Role "server" -StatusFile $owned | Out-Null
    if (-not (Start-SandboxServer -Port $port -AllowExisting)) { exit 1 }
    $owned = $script:StatusPath
    $stopped = Stop-ProjectProcesses -Role "server" -StatusFile $owned
    if ($stopped -lt 1) {
        Write-Log "Smoke stop did not find the server."
        exit 1
    }
    Write-Log "LAUNCHER_SMOKE_OK"
    exit 0
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Survival Sandbox"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.ClientSize = New-Object System.Drawing.Size(520, 510)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(244, 242, 236)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Survival Sandbox"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20, 16)
$form.Controls.Add($title)

$hint = New-Object System.Windows.Forms.Label
$hint.Text = "Multiplayer: start the server, then open a client. Building is local-only for now: use Play local.`r`nBuild Tool (hotbar 2): LMB place  RMB cancel  R rotate  PgUp/PgDn level  [ ] (Ue +) blueprint  F3 debug"
$hint.AutoSize = $false
$hint.Size = New-Object System.Drawing.Size(476, 60)
$hint.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
$hint.Location = New-Object System.Drawing.Point(22, 48)
$form.Controls.Add($hint)

$addressLabel = New-Object System.Windows.Forms.Label
$addressLabel.Text = "Address"
$addressLabel.AutoSize = $true
$addressLabel.Location = New-Object System.Drawing.Point(22, 120)
$form.Controls.Add($addressLabel)

$script:AddressBox = New-Object System.Windows.Forms.TextBox
$script:AddressBox.Text = "127.0.0.1"
$script:AddressBox.Location = New-Object System.Drawing.Point(90, 116)
$script:AddressBox.Size = New-Object System.Drawing.Size(180, 28)
$form.Controls.Add($script:AddressBox)

$portLabel = New-Object System.Windows.Forms.Label
$portLabel.Text = "Port"
$portLabel.AutoSize = $true
$portLabel.Location = New-Object System.Drawing.Point(290, 120)
$form.Controls.Add($portLabel)

$script:PortBox = New-Object System.Windows.Forms.TextBox
$script:PortBox.Text = "7777"
$script:PortBox.Location = New-Object System.Drawing.Point(330, 116)
$script:PortBox.Size = New-Object System.Drawing.Size(80, 28)
$form.Controls.Add($script:PortBox)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.AutoSize = $false
$script:StatusLabel.Size = New-Object System.Drawing.Size(476, 24)
$script:StatusLabel.Location = New-Object System.Drawing.Point(22, 154)
$form.Controls.Add($script:StatusLabel)

function New-ActionButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [scriptblock]$OnClick)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, 34)
    $button.FlatStyle = "Flat"
    $button.BackColor = [System.Drawing.Color]::White
    $button.Add_Click($OnClick)
    return $button
}

$form.Controls.Add((New-ActionButton "Start server" 22 188 150 {
    Invoke-LauncherAction {
        $fields = Read-LaunchFields
        Start-SandboxServer -Port $fields.Port | Out-Null
    }
}))
$form.Controls.Add((New-ActionButton "Restart server" 182 188 156 {
    Invoke-LauncherAction {
        $fields = Read-LaunchFields
        Restart-SandboxServer -Port $fields.Port | Out-Null
    }
}))
$form.Controls.Add((New-ActionButton "Stop server" 348 188 150 {
    Invoke-LauncherAction {
        $removed = Stop-ProjectProcesses -Role "server"
        if ($removed -eq 0) { Write-Log "No server was running." }
        else { Write-Log "Stopped the server." }
    }
}))
$form.Controls.Add((New-ActionButton "Start client" 22 234 150 {
    Invoke-LauncherAction {
        $fields = Read-LaunchFields
        Start-SandboxClient -Address $fields.Address -Port $fields.Port | Out-Null
    }
}))
$form.Controls.Add((New-ActionButton "Start two clients" 182 234 156 {
    Invoke-LauncherAction {
        $fields = Read-LaunchFields
        Start-SandboxClient -Address $fields.Address -Port $fields.Port | Out-Null
        Start-Sleep -Milliseconds 400
        Start-SandboxClient -Address $fields.Address -Port $fields.Port | Out-Null
    }
}))
$form.Controls.Add((New-ActionButton "Close clients" 348 234 150 {
    Invoke-LauncherAction {
        $removed = Stop-ProjectProcesses -Role "client"
        if ($removed -eq 0) { Write-Log "No clients were open." }
        else { Write-Log "Closed $removed client process(es)." }
    }
}))
$form.Controls.Add((New-ActionButton "Play local (building)" 22 280 476 {
    Invoke-LauncherAction { Start-SandboxLocal | Out-Null }
}))

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Multiline = $true
$script:LogBox.ReadOnly = $true
$script:LogBox.ScrollBars = "Vertical"
$script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$script:LogBox.Location = New-Object System.Drawing.Point(22, 328)
$script:LogBox.Size = New-Object System.Drawing.Size(476, 156)
$script:LogBox.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($script:LogBox)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 800
$timer.Add_Tick({ Update-StatusLabel })
$timer.Start()
$form.Add_Shown({
    Update-StatusLabel
    Write-Log "Launcher ready."
    # launcher.vbs starts PowerShell hidden. Show this window anyway.
    $show = Add-Type -Namespace Native -Name Win32Show -PassThru -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
"@
    [void]$show::ShowWindow($form.Handle, 9)
    [void]$show::SetForegroundWindow($form.Handle)
    $form.Activate()
})
$form.Add_FormClosed({ $timer.Stop() })

[void]$form.ShowDialog()
exit 0
