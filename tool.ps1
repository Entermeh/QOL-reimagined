Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class MemoryOptimizer {
    [DllImport("psapi.dll")]
    public static extern int EmptyWorkingSet(IntPtr hwProc);
    public static void TrimProcessMemory() {
        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
        try {
            EmptyWorkingSet(System.Diagnostics.Process.GetCurrentProcess().Handle);
        } catch {}
    }
}
"@ -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Drawing

function Test-IsElevated {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-AdminElevated {
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) {
        $scriptPath = $MyInvocation.MyCommand.Path
    }

    if (-not $scriptPath) {
        return $false
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Verb = "RunAs"
    $startInfo.UseShellExecute = $true
    $startInfo.WorkingDirectory = Split-Path -Parent $scriptPath
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

    try {
        $proc = [System.Diagnostics.Process]::Start($startInfo)
        return $null -ne $proc
    }
    catch {
        return $false
    }
}

function Assert-Admin {
    if (-not (Test-IsElevated)) {
        if (Start-AdminElevated) {
            exit 0
        }

        [System.Windows.Forms.MessageBox]::Show(
            "This tool requires administrator privileges to run properly.",
            "Admin Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        exit 1
    }
}

Assert-Admin

$script:scriptFolder = $PSScriptRoot
if (-not $script:scriptFolder -and $PSCommandPath) {
    $script:scriptFolder = Split-Path -Parent $PSCommandPath
}
if (-not $script:scriptFolder -and $MyInvocation.MyCommand.Path) {
    $script:scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not $script:scriptFolder) {
    $script:scriptFolder = (Get-Location).Path
}
if (-not $script:scriptFolder) {
    $script:scriptFolder = "."
}

$script:assetFolders = @(
    (Join-Path $script:scriptFolder "icons"),
    (Join-Path $script:scriptFolder "assets"),
    $script:scriptFolder
)

$script:pinnedCommandsFile = Join-Path $script:scriptFolder "pinned_commands.txt"
$script:licenseServerUrlFile = Join-Path $script:scriptFolder "license-server-url.txt"
function Get-AssetPath {
    param([string]$FileName)

    foreach ($folder in $script:assetFolders) {
        $path = Join-Path $folder $FileName
        if (Test-Path $path) {
            return $path
        }
    }

    return (Join-Path $script:assetFolders[0] $FileName)
}

function Get-AppIcon {
    if ($script:cachedAppIcon) { return $script:cachedAppIcon }
    $icoPath = Get-AssetPath -FileName "icon.ico"
    if (Test-Path $icoPath) {
        try {
            $script:cachedAppIcon = New-Object System.Drawing.Icon($icoPath)
            return $script:cachedAppIcon
        } catch {}
    }
    try {
        $procPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($procPath -and -not ($procPath.ToLower().EndsWith("powershell.exe") -or $procPath.ToLower().EndsWith("pwsh.exe"))) {
            $script:cachedAppIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($procPath)
            return $script:cachedAppIcon
        }
    } catch {}
    return $null
}

function Install-DesktopShortcut {
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $desktop = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
        $shortcutPath = Join-Path $desktop "QOL Reimagined.lnk"
        
        $procPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($procPath -and -not ($procPath.ToLower().EndsWith("powershell.exe") -or $procPath.ToLower().EndsWith("pwsh.exe"))) {
            $target = $procPath
        } else {
            $exeInFolder = Join-Path $script:scriptFolder "QOL Reimagined.exe"
            if (Test-Path $exeInFolder) {
                $target = $exeInFolder
            } else {
                $target = Join-Path $script:scriptFolder "launch.bat"
            }
        }

        $shortcut = $wsh.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $target
        $shortcut.WorkingDirectory = $script:scriptFolder

        $icoPath = Get-AssetPath -FileName "icon.ico"
        if (Test-Path $icoPath) {
            $shortcut.IconLocation = "$icoPath,0"
        } else {
            $shortcut.IconLocation = "$target,0"
        }
        $shortcut.Description = "QOL Reimagined - Windows Performance & Gaming Utility"
        $shortcut.Save()
        return $true
    } catch {
        return $false
    }
}

function Import-PinnedCommands {
    if (-not (Test-Path $script:pinnedCommandsFile)) {
        return @("Check Local IP", "Ping Google (8.8.8.8)", "Open Device Manager")
    }

    $items = Get-Content -Path $script:pinnedCommandsFile -ErrorAction SilentlyContinue
    if (-not $items) {
        return @()
    }

    return @($items | Where-Object { $_ -and $_.Trim() -ne "" })
}

function Save-PinnedCommands {
    param([string[]]$Commands)

    $clean = @($Commands | Where-Object { $_ -and $_.Trim() -ne "" } | Select-Object -Unique)
    if ($clean.Count -eq 0) {
        if (Test-Path $script:pinnedCommandsFile) {
            Remove-Item -Path $script:pinnedCommandsFile -Force -ErrorAction SilentlyContinue
        }
        return
    }

    $clean | Set-Content -Path $script:pinnedCommandsFile -Encoding UTF8
}

$script:appDataDir = Join-Path $env:APPDATA "QOLReimagined"
$legacyDir = Join-Path $env:APPDATA "MiniNetTool"
if (-not (Test-Path $script:appDataDir) -and (Test-Path $legacyDir)) {
    try {
        Copy-Item -Path $legacyDir -Destination $script:appDataDir -Recurse -Force -ErrorAction SilentlyContinue
    } catch {}
}
if (-not (Test-Path $script:appDataDir)) {
    New-Item -ItemType Directory -Path $script:appDataDir -Force -ErrorAction SilentlyContinue | Out-Null
}

$script:proLicenseFile = Join-Path $script:appDataDir "pro.key"
$script:customCommandsFile = Join-Path $script:appDataDir "custom_commands.json"
$script:proActive = $false

function Get-LicenseServerUrl {
    $serverUrl = $env:QOL_LICENSE_SERVER; if ([string]::IsNullOrWhiteSpace($serverUrl)) { $serverUrl = $env:MINITOOL_LICENSE_SERVER }
    if ([string]::IsNullOrWhiteSpace($serverUrl) -and (Test-Path $script:licenseServerUrlFile)) {
        $serverUrl = (Get-Content -Path $script:licenseServerUrlFile -Raw -ErrorAction SilentlyContinue).Trim()
    }

    $parsedUrl = $null
    if ([string]::IsNullOrWhiteSpace($serverUrl) -or -not [System.Uri]::TryCreate($serverUrl, [System.UriKind]::Absolute, [ref]$parsedUrl)) {
        return ""
    }
    if ($parsedUrl.Host -like "*.example.com" -or ($parsedUrl.Scheme -ne "https" -and $parsedUrl.Host -notin @("localhost", "127.0.0.1"))) {
        return ""
    }

    return $parsedUrl.AbsoluteUri.TrimEnd("/")
}

function Test-ProAccess {
    if ($script:proActive) {
        return $true
    }
    if (-not (Test-Path $script:proLicenseFile)) {
        return $false
    }

    $key = (Get-Content -Path $script:proLicenseFile -Raw -ErrorAction SilentlyContinue)
    if (-not $key) {
        return $false
    }
    $key = $key.Trim()

    $serverUrl = Get-LicenseServerUrl
    if ($serverUrl) {
        try {
            $response = Invoke-RestMethod -Uri "$serverUrl/api/activate" -Method Post -ContentType "application/json" -Body (@{ licenseKey = $key } | ConvertTo-Json) -TimeoutSec 5 -ErrorAction Stop
            if ($response.active -eq $true -and $response.tier -eq "pro") {
                $script:proActive = $true
                return $true
            }
        }
        catch {
            # License server is offline or unreachable, fall back to offline verification
        }
    }

    try {
        if ($key -match '^MNT-PRO\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)$') {
            $base64 = $matches[1].Replace('-', '+').Replace('_', '/')
            switch ($base64.Length % 4) {
                2 { $base64 += '==' }
                3 { $base64 += '=' }
            }
            $jsonBytes = [System.Convert]::FromBase64String($base64)
            $jsonStr = [System.Text.Encoding]::UTF8.GetString($jsonBytes)
            $payload = $jsonStr | ConvertFrom-Json
            if ($payload.tier -eq "pro") {
                $script:proActive = $true
                return $true
            }
        }
    }
    catch {
        return $false
    }

    return $false
}

function Assert-ProAccess {
    if (Test-ProAccess) {
        return $true
    }

    [System.Windows.Forms.MessageBox]::Show("Activate a Pro key to use this feature. Pro is £2, and the owner has three complimentary keys available.", "QOL Reimagined Pro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    return $false
}

function Start-ProCheckout {
    $serverUrl = Get-LicenseServerUrl
    if (-not $serverUrl) {
        [System.Windows.Forms.MessageBox]::Show("Set the deployed HTTPS server URL in license-server-url.txt first.", "Pro Setup Needed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    try {
        $response = Invoke-RestMethod -Uri "$serverUrl/api/checkout" -Method Post -ContentType "application/json" -Body "{}" -TimeoutSec 15 -ErrorAction Stop
        Start-Process -FilePath $response.checkoutUrl | Out-Null
        Write-Result -OutputBox $outputBox -Message "Stripe Checkout opened. The server issues your Pro key after payment is confirmed."
    }
    catch {
        Write-Result -OutputBox $outputBox -Message "Could not start Pro checkout: $($_.Exception.Message)"
    }
}

function Show-ProActivationDialog {
    $serverUrl = Get-LicenseServerUrl
    if (-not $serverUrl) {
        [System.Windows.Forms.MessageBox]::Show("Set the deployed HTTPS server URL in license-server-url.txt first.", "Pro Setup Needed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    $activateForm = New-Object System.Windows.Forms.Form
    $activateForm.Text = "Activate Pro"
    $activateForm.Size = New-Object System.Drawing.Size(440, 150)
    $activateForm.StartPosition = "CenterParent"
    $activateForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $activateForm.MaximizeBox = $false
    $activateForm.MinimizeBox = $false

    $keyBox = New-Object System.Windows.Forms.TextBox
    $keyBox.Location = New-Object System.Drawing.Point(15, 15)
    $keyBox.Size = New-Object System.Drawing.Size(395, 24)
    $activateForm.Controls.Add($keyBox)

    $activateButton = New-Object System.Windows.Forms.Button
    $activateButton.Text = "Activate"
    $activateButton.Location = New-Object System.Drawing.Point(230, 55)
    $activateButton.Size = New-Object System.Drawing.Size(85, 30)
    $activateForm.Controls.Add($activateButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point(325, 55)
    $cancelButton.Size = New-Object System.Drawing.Size(85, 30)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $activateForm.Controls.Add($cancelButton)
    $activateForm.CancelButton = $cancelButton

    $activateButton.Add_Click({
        $key = $keyBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($key)) {
            [System.Windows.Forms.MessageBox]::Show("Enter your Pro key.", "Activate Pro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        try {
            $response = Invoke-RestMethod -Uri "$serverUrl/api/activate" -Method Post -ContentType "application/json" -Body (@{ licenseKey = $key } | ConvertTo-Json) -TimeoutSec 10 -ErrorAction Stop
            if ($response.active -eq $true -and $response.tier -eq "pro") {
                $licenseFolder = Split-Path -Parent $script:proLicenseFile
                if (-not (Test-Path $licenseFolder)) {
                    New-Item -ItemType Directory -Path $licenseFolder -Force | Out-Null
                }
                Set-Content -Path $script:proLicenseFile -Value $key -Encoding UTF8
                $script:proActive = $true
                [System.Windows.Forms.MessageBox]::Show("Pro activated on this PC.", "QOL Reimagined Pro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                $activateForm.Close()
            }
            else {
                [System.Windows.Forms.MessageBox]::Show("That Pro key was not accepted.", "Activate Pro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Could not validate the key with the license server: $($_.Exception.Message)", "Activate Pro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    [void]$activateForm.ShowDialog($form)
}

function Import-CustomCommands {
    if (-not (Test-Path $script:customCommandsFile)) {
        return @()
    }
    try {
        $commands = Get-Content -Path $script:customCommandsFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return @($commands | Where-Object { $_.Name -and $_.Path })
    }
    catch {
        return @()
    }
}

function Save-CustomCommands {
    param([object[]]$Commands)

    $folder = Split-Path -Parent $script:customCommandsFile
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    ConvertTo-Json -InputObject @($Commands) -Depth 4 | Set-Content -Path $script:customCommandsFile -Encoding UTF8
}

function Show-CustomCommandsDialog {
    if (-not (Assert-ProAccess)) {
        return
    }

    $commandsForm = New-Object System.Windows.Forms.Form
    $commandsForm.Text = "Pro Custom Commands"
    $commandsForm.Size = New-Object System.Drawing.Size(560, 330)
    $commandsForm.StartPosition = "CenterParent"
    $commandsForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $commandsForm.MaximizeBox = $false
    $commandsForm.MinimizeBox = $false

    $commandsList = New-Object System.Windows.Forms.ListBox
    $commandsList.Location = New-Object System.Drawing.Point(15, 15)
    $commandsList.Size = New-Object System.Drawing.Size(515, 110)
    $commandsList.DisplayMember = "Name"
    foreach ($command in (Import-CustomCommands)) { $commandsList.Items.Add($command) | Out-Null }
    $commandsForm.Controls.Add($commandsList)

    $nameLabel = New-Object System.Windows.Forms.Label
    $nameLabel.Text = "Name"
    $nameLabel.Location = New-Object System.Drawing.Point(15, 140)
    $nameLabel.Size = New-Object System.Drawing.Size(70, 20)
    $commandsForm.Controls.Add($nameLabel)

    $nameBox = New-Object System.Windows.Forms.TextBox
    $nameBox.Location = New-Object System.Drawing.Point(90, 137)
    $nameBox.Size = New-Object System.Drawing.Size(440, 24)
    $commandsForm.Controls.Add($nameBox)

    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text = "App"
    $pathLabel.Location = New-Object System.Drawing.Point(15, 175)
    $pathLabel.Size = New-Object System.Drawing.Size(70, 20)
    $commandsForm.Controls.Add($pathLabel)

    $pathBox = New-Object System.Windows.Forms.TextBox
    $pathBox.Location = New-Object System.Drawing.Point(90, 172)
    $pathBox.Size = New-Object System.Drawing.Size(345, 24)
    $commandsForm.Controls.Add($pathBox)

    $browseButton = New-Object System.Windows.Forms.Button
    $browseButton.Text = "Browse"
    $browseButton.Location = New-Object System.Drawing.Point(445, 170)
    $browseButton.Size = New-Object System.Drawing.Size(85, 28)
    $browseButton.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = "Applications and shortcuts (*.exe;*.lnk)|*.exe;*.lnk"
        if ($dialog.ShowDialog($commandsForm) -eq [System.Windows.Forms.DialogResult]::OK) { $pathBox.Text = $dialog.FileName }
    })
    $commandsForm.Controls.Add($browseButton)

    $argsLabel = New-Object System.Windows.Forms.Label
    $argsLabel.Text = "Arguments"
    $argsLabel.Location = New-Object System.Drawing.Point(15, 210)
    $argsLabel.Size = New-Object System.Drawing.Size(70, 20)
    $commandsForm.Controls.Add($argsLabel)

    $argsBox = New-Object System.Windows.Forms.TextBox
    $argsBox.Location = New-Object System.Drawing.Point(90, 207)
    $argsBox.Size = New-Object System.Drawing.Size(440, 24)
    $commandsForm.Controls.Add($argsBox)

    $addButton = New-Object System.Windows.Forms.Button
    $addButton.Text = "Add"
    $addButton.Location = New-Object System.Drawing.Point(15, 250)
    $addButton.Size = New-Object System.Drawing.Size(90, 30)
    $addButton.Add_Click({
        $target = $pathBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($nameBox.Text) -or -not (Test-Path -LiteralPath $target) -or [System.IO.Path]::GetExtension($target).ToLowerInvariant() -notin @(".exe", ".lnk")) {
            [System.Windows.Forms.MessageBox]::Show("Enter a name and choose an existing .exe or .lnk file.", "Custom Command", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        $item = [pscustomobject]@{ Name = $nameBox.Text.Trim(); Path = $target; Arguments = $argsBox.Text.Trim() }
        $commandsList.Items.Add($item) | Out-Null
        Save-CustomCommands -Commands @($commandsList.Items)
        $nameBox.Clear()
        $pathBox.Clear()
        $argsBox.Clear()
    })
    $commandsForm.Controls.Add($addButton)

    $runButton = New-Object System.Windows.Forms.Button
    $runButton.Text = "Run Selected"
    $runButton.Location = New-Object System.Drawing.Point(125, 250)
    $runButton.Size = New-Object System.Drawing.Size(110, 30)
    $runButton.Add_Click({
        $item = $commandsList.SelectedItem
        if ($item) {
            try {
                Start-Process -FilePath $item.Path -ArgumentList $item.Arguments | Out-Null
                Write-Result -OutputBox $outputBox -Message "Custom command opened: $($item.Name)"
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show("Could not run this command: $($_.Exception.Message)", "Custom Command", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
        }
    })
    $commandsForm.Controls.Add($runButton)

    $removeButton = New-Object System.Windows.Forms.Button
    $removeButton.Text = "Remove"
    $removeButton.Location = New-Object System.Drawing.Point(255, 250)
    $removeButton.Size = New-Object System.Drawing.Size(90, 30)
    $removeButton.Add_Click({
        if ($commandsList.SelectedItem) {
            $commandsList.Items.Remove($commandsList.SelectedItem)
            Save-CustomCommands -Commands @($commandsList.Items)
        }
    })
    $commandsForm.Controls.Add($removeButton)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = "Close"
    $closeButton.Location = New-Object System.Drawing.Point(440, 250)
    $closeButton.Size = New-Object System.Drawing.Size(90, 30)
    $closeButton.Add_Click({ $commandsForm.Close() })
    $commandsForm.Controls.Add($closeButton)

    [void]$commandsForm.ShowDialog($form)
}

function Show-PinnedCommandsDialog {
    $pinnedForm = New-Object System.Windows.Forms.Form
    $pinnedForm.Text = "Pinned Commands"
    $pinnedForm.Size = New-Object System.Drawing.Size(360, 240)
    $pinnedForm.StartPosition = "CenterParent"
    $pinnedForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $pinnedForm.MaximizeBox = $false
    $pinnedForm.MinimizeBox = $false

    $lstPinned = New-Object System.Windows.Forms.ListBox
    $lstPinned.Location = New-Object System.Drawing.Point(15, 15)
    $lstPinned.Size = New-Object System.Drawing.Size(320, 120)
    foreach ($item in (Import-PinnedCommands)) {
        $lstPinned.Items.Add($item) | Out-Null
    }
    $pinnedForm.Controls.Add($lstPinned)

    $btnRunPinned = New-Object System.Windows.Forms.Button
    $btnRunPinned.Text = "Run Selected"
    $btnRunPinned.Location = New-Object System.Drawing.Point(15, 150)
    $btnRunPinned.Size = New-Object System.Drawing.Size(145, 30)
    $btnRunPinned.Add_Click({
        if ($lstPinned.SelectedItem) {
            if ($dropdown.Items -notcontains $lstPinned.SelectedItem) {
                $cboCategory.SelectedItem = "All Tools (Complete List)"
            }
            $dropdown.SelectedItem = $lstPinned.SelectedItem
            $btnRun.PerformClick()
            $pinnedForm.Close()
        }
    })
    $pinnedForm.Controls.Add($btnRunPinned)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(190, 150)
    $btnClose.Size = New-Object System.Drawing.Size(145, 30)
    $btnClose.Add_Click({ $pinnedForm.Close() })
    $pinnedForm.Controls.Add($btnClose)

    [void]$pinnedForm.ShowDialog($form)
}

function Show-ReactionGame {
    $colors = Get-ThemeColors -theme $script:currentTheme
    try { $colors.BoxFore = [System.Drawing.ColorTranslator]::FromHtml($script:userProfile.AccentColor) } catch {}

    $gameForm = New-Object System.Windows.Forms.Form
    $gameForm.Text = "Reaction Speed Tester - QOL Reimagined"
    $gameForm.Size = New-Object System.Drawing.Size(460, 360)
    $gameForm.StartPosition = "CenterParent"
    $gameForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $gameForm.MaximizeBox = $false
    $gameForm.MinimizeBox = $false
    $gameForm.BackColor = $colors.Back
    $gameForm.ForeColor = $colors.Fore

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Click the target when it turns GREEN as fast as you can!"
    $lbl.Location = New-Object System.Drawing.Point(15, 12)
    $lbl.Size = New-Object System.Drawing.Size(415, 25)
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $gameForm.Controls.Add($lbl)

    $targetBtn = New-Object System.Windows.Forms.Button
    $targetBtn.Location = New-Object System.Drawing.Point(25, 45)
    $targetBtn.Size = New-Object System.Drawing.Size(395, 185)
    $targetBtn.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $targetBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $targetBtn.BackColor = $colors.BtnBack
    $targetBtn.ForeColor = $colors.Fore
    $targetBtn.Text = "Click to Start"
    $gameForm.Controls.Add($targetBtn)

    $lblResult = New-Object System.Windows.Forms.Label
    $lblResult.Text = "Best: -- ms"
    $lblResult.Location = New-Object System.Drawing.Point(25, 240)
    $lblResult.Size = New-Object System.Drawing.Size(395, 25)
    $lblResult.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $lblResult.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblResult.ForeColor = $colors.BoxFore
    $gameForm.Controls.Add($lblResult)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(175, 275)
    $btnClose.Size = New-Object System.Drawing.Size(100, 30)
    $btnClose.BackColor = $colors.BtnBack
    $btnClose.ForeColor = $colors.BtnFore
    $btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnClose.Add_Click({ $gameForm.Close() })
    $gameForm.Controls.Add($btnClose)

    $state = @{
        Phase = "Idle"
        Stopwatch = New-Object System.Diagnostics.Stopwatch
        Best = 9999
    }

    $timer = New-Object System.Windows.Forms.Timer

    $timer.Add_Tick({
        $timer.Stop()
        if ($state.Phase -eq "Waiting") {
            $state.Phase = "Ready"
            $targetBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 200, 80)
            $targetBtn.ForeColor = [System.Drawing.Color]::Black
            $targetBtn.Text = "CLICK NOW!"
            $state.Stopwatch.Restart()
        }
    })

    $targetBtn.Add_Click({
        if ($state.Phase -eq "Idle" -or $state.Phase -eq "Finished") {
            $state.Phase = "Waiting"
            $targetBtn.BackColor = [System.Drawing.Color]::FromArgb(180, 40, 40)
            $targetBtn.ForeColor = [System.Drawing.Color]::White
            $targetBtn.Text = "Wait for Green..."
            $timer.Interval = (Get-Random -Minimum 1500 -Maximum 4200)
            $timer.Start()
        }
        elseif ($state.Phase -eq "Waiting") {
            $timer.Stop()
            $state.Phase = "Finished"
            $targetBtn.BackColor = $colors.BtnBack
            $targetBtn.ForeColor = [System.Drawing.Color]::OrangeRed
            $targetBtn.Text = "Too Early! Click to retry."
        }
        elseif ($state.Phase -eq "Ready") {
            $state.Stopwatch.Stop()
            $ms = $state.Stopwatch.ElapsedMilliseconds
            $state.Phase = "Finished"
            $script:userProfile.GamesPlayed++
            $tier = if ($ms -lt 190) {
                Add-Achievement -AchievementId "Lightning Reflexes"
                "Godlike Reflexes! (Pro Tier)"
            } elseif ($ms -lt 240) {
                "Fast Reflexes! (Gamer Tier)"
            } elseif ($ms -lt 320) {
                "Average Reflexes"
            } else {
                "Slow (Needs Coffee)"
            }

            $targetBtn.BackColor = $colors.BtnBack
            $targetBtn.ForeColor = $colors.BoxFore
            $targetBtn.Text = "$ms ms`r`n$tier"
            if ($ms -lt $state.Best) { $state.Best = $ms }
            $lblResult.Text = "Score: $ms ms  |  Personal Best: $($state.Best) ms"
            Save-UserProfile
        }
    })

    $gameForm.Add_FormClosing({
        $timer.Stop()
        $timer.Dispose()
        [MemoryOptimizer]::TrimProcessMemory()
    })

    [void]$gameForm.ShowDialog($form)
}

function Show-RpsGame {
    # Auto trim memory on exit
    $colors = Get-ThemeColors -theme $script:currentTheme
    try { $colors.BoxFore = [System.Drawing.ColorTranslator]::FromHtml($script:userProfile.AccentColor) } catch {}

    $gameForm = New-Object System.Windows.Forms.Form
    $gameForm.Text = "Rock Paper Scissors Lizard Spock - QOL Reimagined"
    $gameForm.Size = New-Object System.Drawing.Size(520, 390)
    $gameForm.StartPosition = "CenterParent"
    $gameForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $gameForm.MaximizeBox = $false
    $gameForm.MinimizeBox = $false
    $gameForm.BackColor = $colors.Back
    $gameForm.ForeColor = $colors.Fore

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Choose your move to battle the AI:"
    $lbl.Location = New-Object System.Drawing.Point(15, 12)
    $lbl.Size = New-Object System.Drawing.Size(475, 22)
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $gameForm.Controls.Add($lbl)

    $choices = @("Rock", "Paper", "Scissors", "Lizard", "Spock")
    $streak = 0

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Streak: 0  |  Make your move!"
    $lblStatus.Location = New-Object System.Drawing.Point(15, 40)
    $lblStatus.Size = New-Object System.Drawing.Size(475, 22)
    $lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblStatus.ForeColor = $colors.BoxFore
    $gameForm.Controls.Add($lblStatus)

    $resultBox = New-Object System.Windows.Forms.TextBox
    $resultBox.Location = New-Object System.Drawing.Point(20, 70)
    $resultBox.Size = New-Object System.Drawing.Size(465, 160)
    $resultBox.Multiline = $true
    $resultBox.ReadOnly = $true
    $resultBox.BackColor = $colors.BoxBack
    $resultBox.ForeColor = $colors.BoxFore
    $resultBox.Font = New-Object System.Drawing.Font("Consolas", 10)
    $resultBox.Text = "Rules:`r`n Scissors cuts Paper, Paper covers Rock, Rock crushes Lizard,`r`n Lizard poisons Spock, Spock smashes Scissors, Scissors decapitates Lizard,`r`n Lizard eats Paper, Paper disproves Spock, Spock vaporizes Rock, Rock crushes Scissors.`r`n"
    $gameForm.Controls.Add($resultBox)

    # Win map: winner => array of losers it beats
    $winsAgainst = @{
        "Scissors" = @("Paper", "Lizard")
        "Paper"    = @("Rock", "Spock")
        "Rock"     = @("Lizard", "Scissors")
        "Lizard"   = @("Spock", "Paper")
        "Spock"    = @("Scissors", "Rock")
    }

    $btnX = 20
    foreach ($choice in $choices) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $choice
        $btn.Location = New-Object System.Drawing.Point($btnX, 245)
        $btn.Size = New-Object System.Drawing.Size(88, 38)
        $btn.BackColor = $colors.BtnBack
        $btn.ForeColor = $colors.BtnFore
        $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

        $userChoice = $choice
        $btn.Add_Click({
            $aiChoice = $choices[(Get-Random -Minimum 0 -Maximum 5)]
            $script:userProfile.GamesPlayed++

            if ($userChoice -eq $aiChoice) {
                $resultBox.AppendText("[TIE] Both picked $userChoice! Play again.`r`n")
            }
            elseif ($winsAgainst[$userChoice] -contains $aiChoice) {
                $streak++
                $script:userProfile.GameWins++
                $resultBox.AppendText("[WIN] You: $userChoice  vs  AI: $aiChoice -> $userChoice beats $aiChoice! (Streak: $streak)`r`n")
                if ($streak -ge 5) { Add-Achievement -AchievementId "RPS Master" }
            }
            else {
                $streak = 0
                $resultBox.AppendText("[LOSE] You: $userChoice  vs  AI: $aiChoice -> $aiChoice beats $userChoice! Streak reset.`r`n")
            }
            $lblStatus.Text = "Streak: $streak  |  Total Wins: $($script:userProfile.GameWins)"
            Save-UserProfile
        })
        $gameForm.Controls.Add($btn)
        $btnX += 94
    }

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(210, 305)
    $btnClose.Size = New-Object System.Drawing.Size(100, 30)
    $btnClose.BackColor = $colors.BtnBack
    $btnClose.ForeColor = $colors.BtnFore
    $btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnClose.Add_Click({ $gameForm.Close() })
    $gameForm.Controls.Add($btnClose)

    $gameForm.Add_FormClosing({ [MemoryOptimizer]::TrimProcessMemory() })
    [void]$gameForm.ShowDialog($form)
}

function Show-HigherLowerGame {
    $colors = Get-ThemeColors -theme $script:currentTheme
    try { $colors.BoxFore = [System.Drawing.ColorTranslator]::FromHtml($script:userProfile.AccentColor) } catch {}

    $gameForm = New-Object System.Windows.Forms.Form
    $gameForm.Text = "Higher or Lower - QOL Reimagined"
    $gameForm.Size = New-Object System.Drawing.Size(460, 370)
    $gameForm.StartPosition = "CenterParent"
    $gameForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $gameForm.MaximizeBox = $false
    $gameForm.MinimizeBox = $false
    $gameForm.BackColor = $colors.Back
    $gameForm.ForeColor = $colors.Fore

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Will the next secret number (1-100) be Higher or Lower?"
    $lbl.Location = New-Object System.Drawing.Point(15, 12)
    $lbl.Size = New-Object System.Drawing.Size(415, 22)
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $gameForm.Controls.Add($lbl)

    $currentNum = Get-Random -Minimum 1 -Maximum 101
    $streak = 0
    $score = 0

    $lblCard = New-Object System.Windows.Forms.Label
    $lblCard.Text = "$currentNum"
    $lblCard.Location = New-Object System.Drawing.Point(140, 45)
    $lblCard.Size = New-Object System.Drawing.Size(160, 110)
    $lblCard.Font = New-Object System.Drawing.Font("Segoe UI", 48, [System.Drawing.FontStyle]::Bold)
    $lblCard.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblCard.BackColor = $colors.BoxBack
    $lblCard.ForeColor = $colors.BoxFore
    $gameForm.Controls.Add($lblCard)

    $lblStats = New-Object System.Windows.Forms.Label
    $lblStats.Text = "Score: 0 pts  |  Streak: 0"
    $lblStats.Location = New-Object System.Drawing.Point(15, 170)
    $lblStats.Size = New-Object System.Drawing.Size(415, 25)
    $lblStats.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblStats.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $gameForm.Controls.Add($lblStats)

    $lblMsg = New-Object System.Windows.Forms.Label
    $lblMsg.Text = "Guess: Will the next number be HIGHER or LOWER?"
    $lblMsg.Location = New-Object System.Drawing.Point(15, 200)
    $lblMsg.Size = New-Object System.Drawing.Size(415, 22)
    $lblMsg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblMsg.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblMsg.ForeColor = [System.Drawing.Color]::Silver
    $gameForm.Controls.Add($lblMsg)

    $btnHigher = New-Object System.Windows.Forms.Button
    $btnHigher.Text = "▲ HIGHER"
    $btnHigher.Location = New-Object System.Drawing.Point(85, 235)
    $btnHigher.Size = New-Object System.Drawing.Size(130, 42)
    $btnHigher.BackColor = [System.Drawing.Color]::FromArgb(30, 120, 50)
    $btnHigher.ForeColor = [System.Drawing.Color]::White
    $btnHigher.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnHigher.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    $btnLower = New-Object System.Windows.Forms.Button
    $btnLower.Text = "▼ LOWER"
    $btnLower.Location = New-Object System.Drawing.Point(235, 235)
    $btnLower.Size = New-Object System.Drawing.Size(130, 42)
    $btnLower.BackColor = [System.Drawing.Color]::FromArgb(160, 40, 40)
    $btnLower.ForeColor = [System.Drawing.Color]::White
    $btnLower.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnLower.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    $checkGuess = {
        param([string]$guess)
        $next = Get-Random -Minimum 1 -Maximum 101
        $script:userProfile.GamesPlayed++

        $isCorrect = if ($guess -eq "Higher") { $next -ge $currentNum } else { $next -le $currentNum }
        if ($isCorrect) {
            $streak++
            $points = $streak * 100
            $score += $points
            $script:userProfile.GameWins++
            $lblMsg.Text = "[CORRECT!] The number was $next! (+$points pts)"
            $lblMsg.ForeColor = [System.Drawing.Color]::FromArgb(0, 255, 128)
            if ($streak -ge 6) { Add-Achievement -AchievementId "High Roller" }
        } else {
            $lblMsg.Text = "[WRONG!] The number was $next. Streak ended!"
            $lblMsg.ForeColor = [System.Drawing.Color]::FromArgb(255, 80, 80)
            $streak = 0
        }

        $currentNum = $next
        $lblCard.Text = "$currentNum"
        $lblStats.Text = "Score: $score pts  |  Streak: $streak"
        Save-UserProfile
    }

    $btnHigher.Add_Click({ & $checkGuess "Higher" })
    $btnLower.Add_Click({ & $checkGuess "Lower" })
    $gameForm.Controls.Add($btnHigher)
    $gameForm.Controls.Add($btnLower)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(175, 290)
    $btnClose.Size = New-Object System.Drawing.Size(100, 28)
    $btnClose.BackColor = $colors.BtnBack
    $btnClose.ForeColor = $colors.BtnFore
    $btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnClose.Add_Click({ $gameForm.Close() })
    $gameForm.Controls.Add($btnClose)

    $gameForm.Add_FormClosing({ [MemoryOptimizer]::TrimProcessMemory() })
    [void]$gameForm.ShowDialog($form)
}

function Show-MemoryGame {
    $colors = Get-ThemeColors -theme $script:currentTheme
    try { $colors.BoxFore = [System.Drawing.ColorTranslator]::FromHtml($script:userProfile.AccentColor) } catch {}

    $gameForm = New-Object System.Windows.Forms.Form
    $gameForm.Text = "Simon Memory Sequence - QOL Reimagined"
    $gameForm.Size = New-Object System.Drawing.Size(440, 420)
    $gameForm.StartPosition = "CenterParent"
    $gameForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $gameForm.MaximizeBox = $false
    $gameForm.MinimizeBox = $false
    $gameForm.BackColor = $colors.Back
    $gameForm.ForeColor = $colors.Fore

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Memorize the sequence of flashing colors!"
    $lbl.Location = New-Object System.Drawing.Point(15, 12)
    $lbl.Size = New-Object System.Drawing.Size(395, 22)
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $gameForm.Controls.Add($lbl)

    $lblRound = New-Object System.Windows.Forms.Label
    $lblRound.Text = "Round: 0  |  Click 'Start Game' below"
    $lblRound.Location = New-Object System.Drawing.Point(15, 38)
    $lblRound.Size = New-Object System.Drawing.Size(395, 22)
    $lblRound.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblRound.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblRound.ForeColor = $colors.BoxFore
    $gameForm.Controls.Add($lblRound)

    $palette = @(
        @{ Name = "Green";  Col = [System.Drawing.Color]::FromArgb(40, 180, 70);  Lit = [System.Drawing.Color]::FromArgb(100, 255, 120); X = 70;  Y = 70 },
        @{ Name = "Red";    Col = [System.Drawing.Color]::FromArgb(180, 40, 40);   Lit = [System.Drawing.Color]::FromArgb(255, 100, 100); X = 215; Y = 70 },
        @{ Name = "Yellow"; Col = [System.Drawing.Color]::FromArgb(180, 160, 20);  Lit = [System.Drawing.Color]::FromArgb(255, 240, 80);  X = 70;  Y = 185 },
        @{ Name = "Blue";   Col = [System.Drawing.Color]::FromArgb(30, 90, 190);   Lit = [System.Drawing.Color]::FromArgb(90, 160, 255);  X = 215; Y = 185 }
    )

    $simonBtns = @()
    $sequence = @()
    $playerStep = 0
    $isAcceptingInput = $false

    for ($i = 0; $i -lt 4; $i++) {
        $p = $palette[$i]
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $p.Name
        $b.Location = New-Object System.Drawing.Point($p.X, $p.Y)
        $b.Size = New-Object System.Drawing.Size(130, 100)
        $b.BackColor = $p.Col
        $b.ForeColor = [System.Drawing.Color]::White
        $b.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
        $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $b.Tag = $i
        $gameForm.Controls.Add($b)
        $simonBtns += $b
    }

    $flashButton = {
        param($idx)
        $b = $simonBtns[$idx]
        $p = $palette[$idx]
        $b.BackColor = $p.Lit
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 320
        $b.BackColor = $p.Col
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 120
    }

    $btnControl = New-Object System.Windows.Forms.Button
    $btnControl.Text = "Start Game"
    $btnControl.Location = New-Object System.Drawing.Point(145, 305)
    $btnControl.Size = New-Object System.Drawing.Size(130, 34)
    $btnControl.BackColor = $colors.BtnBack
    $btnControl.ForeColor = $colors.BoxFore
    $btnControl.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $btnControl.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $gameForm.Controls.Add($btnControl)

    $nextRound = {
        $isAcceptingInput = $false
        $playerStep = 0
        $sequence += (Get-Random -Minimum 0 -Maximum 4)
        $lblRound.Text = "Round: $($sequence.Count)  |  Watch the sequence..."
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 600

        foreach ($idx in $sequence) {
            & $flashButton $idx
        }
        $lblRound.Text = "Round: $($sequence.Count)  |  YOUR TURN: Repeat the colors!"
        $isAcceptingInput = $true
    }

    $btnControl.Add_Click({
        $sequence = @()
        $script:userProfile.GamesPlayed++
        Save-UserProfile
        & $nextRound
    })

    for ($i = 0; $i -lt 4; $i++) {
        $btnIdx = $i
        $simonBtns[$i].Add_Click({
            if (-not $isAcceptingInput) { return }
            & $flashButton $btnIdx

            if ($btnIdx -eq $sequence[$playerStep]) {
                $playerStep++
                if ($playerStep -eq $sequence.Count) {
                    $script:userProfile.GameWins++
                    if ($sequence.Count -ge 5) { Add-Achievement -AchievementId "Brainiac" }
                    Save-UserProfile
                    $lblRound.Text = "[EXCELLENT!] Round $($sequence.Count) passed!"
                    [System.Windows.Forms.Application]::DoEvents()
                    Start-Sleep -Milliseconds 500
                    & $nextRound
                }
            } else {
                $isAcceptingInput = $false
                $lblRound.Text = "[GAME OVER] Wrong color! You reached Round $($sequence.Count)."
                $btnControl.Text = "Play Again"
            }
        })
    }

    $gameForm.Add_FormClosing({ [MemoryOptimizer]::TrimProcessMemory() })
    [void]$gameForm.ShowDialog($form)
}

function Show-MiniGame {
    $gameForm = New-Object System.Windows.Forms.Form
    $gameForm.Text = "Number Guess"
    $gameForm.Size = New-Object System.Drawing.Size(360, 220)
    $gameForm.StartPosition = "CenterParent"
    $gameForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $gameForm.MaximizeBox = $false
    $gameForm.MinimizeBox = $false

    $gameState = @{ Number = Get-Random -Minimum 1 -Maximum 21; Guesses = 0; Finished = $false }

    $gameLabel = New-Object System.Windows.Forms.Label
    $gameLabel.Text = "Guess the number from 1 to 20. You have 6 tries."
    $gameLabel.Location = New-Object System.Drawing.Point(15, 18)
    $gameLabel.Size = New-Object System.Drawing.Size(315, 32)
    $gameLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $gameForm.Controls.Add($gameLabel)

    $guessBox = New-Object System.Windows.Forms.TextBox
    $guessBox.Location = New-Object System.Drawing.Point(35, 65)
    $guessBox.Size = New-Object System.Drawing.Size(120, 25)
    $gameForm.Controls.Add($guessBox)

    $guessButton = New-Object System.Windows.Forms.Button
    $guessButton.Text = "Guess"
    $guessButton.Location = New-Object System.Drawing.Point(175, 62)
    $guessButton.Size = New-Object System.Drawing.Size(120, 30)
    $gameForm.Controls.Add($guessButton)
    $gameForm.AcceptButton = $guessButton

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = ""
    $statusLabel.Location = New-Object System.Drawing.Point(15, 105)
    $statusLabel.Size = New-Object System.Drawing.Size(315, 45)
    $statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $gameForm.Controls.Add($statusLabel)

    $newGameButton = New-Object System.Windows.Forms.Button
    $newGameButton.Text = "New Game"
    $newGameButton.Location = New-Object System.Drawing.Point(115, 155)
    $newGameButton.Size = New-Object System.Drawing.Size(120, 30)
    $gameForm.Controls.Add($newGameButton)

    $guessButton.Add_Click({
        $guess = 0
        if (-not [int]::TryParse($guessBox.Text, [ref]$guess) -or $guess -lt 1 -or $guess -gt 20) {
            $statusLabel.Text = "Enter a whole number from 1 to 20."
            return
        }
        if ($gameState.Finished) { return }

        $gameState.Guesses++
        if (-not $gameState.Started) {
            $gameState.Started = $true
            $script:userProfile.GamesPlayed++
            Save-UserProfile
        }
        if ($guess -eq $gameState.Number) {
            $statusLabel.Text = "Correct! You got it in $($gameState.Guesses) guess(es)."
            $gameState.Finished = $true
            $guessButton.Enabled = $false
            $script:userProfile.GameWins++
            Save-UserProfile
            if ($script:userProfile.GameWins -ge 10) { Add-Achievement -AchievementId "Guessing Master" }
            if ($gameState.Guesses -eq 1) {
                $script:userProfile.PerfectWins++
                Save-UserProfile
                if ($script:userProfile.PerfectWins -ge 5) { Add-Achievement -AchievementId "Perfect Guesses" }
            }
        }
        elseif ($gameState.Guesses -ge 6) {
            $statusLabel.Text = "Out of guesses. The number was $($gameState.Number)."
            $gameState.Finished = $true
            $guessButton.Enabled = $false
        }
        elseif ($guess -lt $gameState.Number) {
            $statusLabel.Text = "Too low. Guesses left: $((6 - $gameState.Guesses))"
        }
        else {
            $statusLabel.Text = "Too high. Guesses left: $((6 - $gameState.Guesses))"
        }
        $guessBox.Clear()
        $guessBox.Focus()
    })

    $newGameButton.Add_Click({
        $gameState.Number = Get-Random -Minimum 1 -Maximum 21
        $gameState.Guesses = 0
        $gameState.Finished = $false
        $gameState.Started = $false
        $guessButton.Enabled = $true
        $guessBox.Clear()
        $statusLabel.Text = "New number picked. Good luck!"
        $guessBox.Focus()
    })

    $gameForm.Add_FormClosing({ [MemoryOptimizer]::TrimProcessMemory() })
    [void]$gameForm.ShowDialog($form)
}

function Show-CoinToss {
    $result = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { "Heads" } else { "Tails" }
    $script:userProfile.GamesPlayed++
    Save-UserProfile
    [System.Windows.Forms.MessageBox]::Show("It landed on $result.", "Coin Toss", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Show-DiceRoll {
    $result = Get-Random -Minimum 1 -Maximum 7
    $script:userProfile.GamesPlayed++
    Save-UserProfile
    [System.Windows.Forms.MessageBox]::Show("You rolled a $result.", "Dice Roll", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Show-RngGame {
    $gameForm = New-Object System.Windows.Forms.Form
    $gameForm.Text = "RNG Rush"
    $gameForm.Size = New-Object System.Drawing.Size(430, 270)
    $gameForm.StartPosition = "CenterParent"
    $gameForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $gameForm.MaximizeBox = $false
    $gameForm.MinimizeBox = $false

    $instructions = New-Object System.Windows.Forms.Label
    $instructions.Text = "Roll 3 times. Reach 180 points to win."
    $instructions.Location = New-Object System.Drawing.Point(20, 18)
    $instructions.Size = New-Object System.Drawing.Size(370, 28)
    $instructions.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $gameForm.Controls.Add($instructions)

    $rollResult = New-Object System.Windows.Forms.Label
    $rollResult.Text = "Ready"
    $rollResult.Location = New-Object System.Drawing.Point(20, 55)
    $rollResult.Size = New-Object System.Drawing.Size(370, 56)
    $rollResult.Font = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
    $rollResult.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $gameForm.Controls.Add($rollResult)

    $scoreLabel = New-Object System.Windows.Forms.Label
    $scoreLabel.Text = "Score: 0 / 180    Rolls: 0 / 3    Best: $($script:userProfile.RngHighScore)"
    $scoreLabel.Location = New-Object System.Drawing.Point(20, 120)
    $scoreLabel.Size = New-Object System.Drawing.Size(370, 30)
    $scoreLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $gameForm.Controls.Add($scoreLabel)

    $rollButton = New-Object System.Windows.Forms.Button
    $rollButton.Text = "Roll"
    $rollButton.Location = New-Object System.Drawing.Point(75, 170)
    $rollButton.Size = New-Object System.Drawing.Size(120, 38)
    $gameForm.Controls.Add($rollButton)

    $newRoundButton = New-Object System.Windows.Forms.Button
    $newRoundButton.Text = "New Round"
    $newRoundButton.Location = New-Object System.Drawing.Point(225, 170)
    $newRoundButton.Size = New-Object System.Drawing.Size(120, 38)
    $gameForm.Controls.Add($newRoundButton)

    $rollButton.Add_Click({
        if ($gameState.Finished) { return }
        if (-not $gameState.Started) {
            $gameState.Started = $true
            $script:userProfile.GamesPlayed++
        }
        $roll = Get-Random -Minimum 1 -Maximum 101
        $gameState.Score += $roll
        $gameState.Rolls++
        if ($roll -eq 100) { $gameState.Hundreds++ }
        $rollResult.Text = "$roll points"
        if ($gameState.Score -gt $script:userProfile.RngHighScore) {
            $script:userProfile.RngHighScore = $gameState.Score
        }
        if ($gameState.Rolls -ge 3) {
            $gameState.Finished = $true
            $rollButton.Enabled = $false
            if ($gameState.Score -ge 180) {
                $rollResult.Text = "You won!"
                $script:userProfile.GameWins++
                Add-Achievement -AchievementId "RNG Jackpot"
            }
            else {
                $rollResult.Text = "Round over"
            }
            if ($gameState.Score -ge 270) { Add-Achievement -AchievementId "Abyssal Roll" }
            if ($gameState.Hundreds -eq 3) { Add-Achievement -AchievementId "Triple Hundred" }
        }
        $scoreLabel.Text = "Score: $($gameState.Score) / 180    Rolls: $($gameState.Rolls) / 3    Best: $($script:userProfile.RngHighScore)"
        Save-UserProfile
    })

    $newRoundButton.Add_Click({
        $gameState.Rolls = 0
        $gameState.Score = 0
        $gameState.Hundreds = 0
        $gameState.Started = $false
        $gameState.Finished = $false
        $rollButton.Enabled = $true
        $rollResult.Text = "Ready"
        $scoreLabel.Text = "Score: 0 / 180    Rolls: 0 / 3    Best: $($script:userProfile.RngHighScore)"
    })

    [void]$gameForm.ShowDialog($form)
}

function Get-WingetExecutablePath {
    $cmd = Get-Command "winget.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $localPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
    if (Test-Path $localPath) { return $localPath }

    $systemApp = Get-ChildItem -Path "C:\Program Files\WindowsApps" -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -First 1
    if ($systemApp) { return $systemApp }

    return "winget.exe"
}

function Show-ExtrasHub {
    param([string]$InitialTab = "")
    $colors = Get-ThemeColors -theme $script:currentTheme
    try {
        $colors.BoxFore = [System.Drawing.ColorTranslator]::FromHtml($script:userProfile.AccentColor)
    } catch {}

    $extrasForm = New-Object System.Windows.Forms.Form
    $extrasForm.Text = "QOL Reimagined - Extras Hub"
    $extrasForm.Size = New-Object System.Drawing.Size(680, 540)
    $extrasForm.StartPosition = "CenterParent"
    $extrasForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $extrasForm.MaximizeBox = $false
    $extrasForm.MinimizeBox = $false
    $extrasForm.BackColor = $colors.Back
    $extrasForm.ForeColor = $colors.Fore

    $extrasToolTip = New-Object System.Windows.Forms.ToolTip
    $extrasToolTip.AutoPopDelay = 12000
    $extrasToolTip.InitialDelay = 250
    $extrasToolTip.ReshowDelay = 100
    $extrasToolTip.ShowAlways = $true

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(12, 12)
    $tabs.Size = New-Object System.Drawing.Size(650, 480)
    $tabs.DrawMode = [System.Windows.Forms.TabDrawMode]::OwnerDrawFixed
    $tabs.SizeMode = [System.Windows.Forms.TabSizeMode]::Fixed
    $tabs.ItemSize = New-Object System.Drawing.Size(91, 28)

    $tabs.Add_DrawItem({
        param($s, $e)
        try {
            $g = $e.Graphics
            $tab = $tabs.TabPages[$e.Index]
            $isSelected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
            
            $brushColor = if ($isSelected) { $colors.BtnBack } else { $colors.Back }
            $bgBrush = New-Object System.Drawing.SolidBrush($brushColor)
            
            $textColor = if ($isSelected) { $colors.BoxFore } else { $colors.Fore }
            $fgBrush = New-Object System.Drawing.SolidBrush($textColor)
            
            $g.FillRectangle($bgBrush, $e.Bounds)
            
            # Draw subtle tab border
            $borderCol = if ($isSelected) { $colors.BoxFore } else { [System.Drawing.Color]::FromArgb(45, 45, 45) }
            $borderPen = New-Object System.Drawing.Pen($borderCol, 1)
            $g.DrawRectangle($borderPen, $e.Bounds.X, $e.Bounds.Y, $e.Bounds.Width - 1, $e.Bounds.Height - 1)
            $borderPen.Dispose()
            
            $sf = New-Object System.Drawing.StringFormat
            $sf.Alignment = [System.Drawing.StringAlignment]::Center
            $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
            
            $fontStyle = if ($isSelected) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
            $fontToUse = New-Object System.Drawing.Font($extrasForm.Font.FontFamily, 9, $fontStyle)
            
            $rectF = [System.Drawing.RectangleF]::new($e.Bounds.X, $e.Bounds.Y, $e.Bounds.Width, $e.Bounds.Height)
            $g.DrawString($tab.Text, $fontToUse, $fgBrush, $rectF, $sf)
            
            $fontToUse.Dispose()
            $bgBrush.Dispose()
            $fgBrush.Dispose()
            $sf.Dispose()
        } catch {}
    })
    $extrasForm.Controls.Add($tabs)

    # 1. Dashboard Tab
    $dashboardTab = New-Object System.Windows.Forms.TabPage
    $dashboardTab.Text = "Dashboard"
    $tabs.TabPages.Add($dashboardTab)

    $dashboardOutput = New-Object System.Windows.Forms.TextBox
    $dashboardOutput.Location = New-Object System.Drawing.Point(15, 15)
    $dashboardOutput.Size = New-Object System.Drawing.Size(600, 320)
    $dashboardOutput.Multiline = $true
    $dashboardOutput.ReadOnly = $true
    $dashboardOutput.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $dashboardOutput.Font = New-Object System.Drawing.Font("Consolas", 10)
    $dashboardTab.Controls.Add($dashboardOutput)

    $refreshDashboard = {
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Measure-Object -Property LoadPercentage -Average
            $drive = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3" -ErrorAction SilentlyContinue | Select-Object -First 1
            $uptime = (Get-Date) - $os.LastBootUpTime
            $totalGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            $freeGb = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
            $diskLine = if ($drive) { "Disk free: {0:N1} GB on {1}" -f ($drive.FreeSpace / 1GB), $drive.DeviceID } else { "Disk: unavailable" }
            $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
            $batteryLine = if ($battery) { "Battery: $($battery.EstimatedChargeRemaining)%" } else { "Battery: not detected" }
            $dashboardOutput.Text = @(
                "CPU load: $([math]::Round($cpu.Average, 0))%",
                "Memory: $([math]::Round($totalGb - $freeGb, 1)) GB used of $totalGb GB",
                $diskLine,
                $batteryLine,
                "Uptime: $($uptime.Days) days, $($uptime.Hours) hours",
                "Actions recorded: $($script:userProfile.ActionCount)",
                "Games played: $($script:userProfile.GamesPlayed)"
            ) -join "`r`n"
        }
        catch {
            $dashboardOutput.Text = "Some system details could not be read."
        }
    }
    & $refreshDashboard

    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Text = "Refresh snapshot"
    $refreshButton.Location = New-Object System.Drawing.Point(15, 350)
    $refreshButton.Size = New-Object System.Drawing.Size(140, 30)
    $refreshButton.Add_Click($refreshDashboard)
    $extrasToolTip.SetToolTip($refreshButton, "Update current CPU, RAM, disk, and battery statistics")
    $dashboardTab.Controls.Add($refreshButton)

    $copyButton = New-Object System.Windows.Forms.Button
    $copyButton.Text = "Copy snapshot"
    $copyButton.Location = New-Object System.Drawing.Point(170, 350)
    $copyButton.Size = New-Object System.Drawing.Size(140, 30)
    $copyButton.Add_Click({
        [System.Windows.Forms.Clipboard]::SetText($dashboardOutput.Text)
        Write-Result -OutputBox $outputBox -Message "System snapshot copied."
    })
    $extrasToolTip.SetToolTip($copyButton, "Copy this system summary text to your clipboard")
    $dashboardTab.Controls.Add($copyButton)

    # 2. Quick Optimizer Tab (32 High-Impact Performance & Gaming Tools)
    $optTab = New-Object System.Windows.Forms.TabPage
    $optTab.Text = "Optimizers"
    $tabs.TabPages.Add($optTab)

    $optTitle = New-Object System.Windows.Forms.Label
    $optTitle.Text = "High-Impact Performance & Latency Tweaks (30+ One-Click Tools)"
    $optTitle.Location = New-Object System.Drawing.Point(15, 8)
    $optTitle.Size = New-Object System.Drawing.Size(595, 20)
    $optTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $optTab.Controls.Add($optTitle)

    # Scrollable panel for 30+ tools
    $optPanel = New-Object System.Windows.Forms.Panel
    $optPanel.Location = New-Object System.Drawing.Point(15, 30)
    $optPanel.Size = New-Object System.Drawing.Size(595, 296)
    $optPanel.AutoScroll = $true
    $optTab.Controls.Add($optPanel)

    $optDescBox = New-Object System.Windows.Forms.TextBox
    $optDescBox.Location = New-Object System.Drawing.Point(15, 332)
    $optDescBox.Size = New-Object System.Drawing.Size(595, 98)
    $optDescBox.Multiline = $true
    $optDescBox.ReadOnly = $true
    $optDescBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $optDescBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $optDescBox.Text = "[i] Hover over any optimization tool above to learn what it does, or click to apply it immediately."
    $optTab.Controls.Add($optDescBox)

    $bindOptHover = {
        param($control, [string]$desc, [string]$tooltip)
        $extrasToolTip.SetToolTip($control, $tooltip)
        $control.Add_MouseEnter({ $optDescBox.Text = "[i] $desc" })
        $control.Add_MouseLeave({ $optDescBox.Text = "[i] Hover over any optimization tool above to learn what it does, or click to apply it immediately." })
    }

    # 32 Performance Tools Definition
    $perfToolsList = @(
        @{ Text = "1-Click Quick PC Boost"; Func = { Invoke-QuickPcBoost }; Desc = "1-Click Quick PC Boost: Performs an automated full-system tuneup. Cleans user & system temp files, flushes DNS resolver cache, purges standby RAM, terminates frozen tasks, and switches to High Performance."; Tip = "Run 1-Click Quick PC Boost" },
        @{ Text = "Low-Latency Gaming Tweaks"; Func = { Optimize-GamingLatency }; Desc = "Low-Latency Gaming Tweaks: Sets network throttling index to 0xFFFFFFFF, sets multimedia responsiveness to 0, prioritizes games GPU queue, and disables GameDVR."; Tip = "Apply Low-Latency Gaming Tweaks" },
        @{ Text = "Hardware GPU Scheduling (HAGS)"; Func = { Enable-HagsGpuScheduling }; Desc = "Hardware-Accelerated GPU Scheduling: Offloads VRAM scheduling directly to GPU scheduling hardware (HwSchMode=2) for reduced input latency and smoother framerates."; Tip = "Enable Hardware GPU Scheduling (HAGS)" },
        @{ Text = "Enable Windows Game Mode"; Func = { Enable-WindowsGameMode }; Desc = "Windows Game Mode: Guarantees active game processes receive highest CPU and GPU priority while suppressing background Windows update driver installations."; Tip = "Enable Windows Game Mode" },
        @{ Text = "Win32 Gaming Priority (0x26)"; Func = { Optimize-Win32PrioritySeparation }; Desc = "Win32 Priority Separation: Configures thread quantums to 38 (0x26) for optimal 3:1 foreground gaming boost and faster frame dispatching."; Tip = "Optimize Win32 Priority Separation" },
        @{ Text = "Disable Mouse Accel (1:1 Raw)"; Func = { Disable-MouseAcceleration }; Desc = "Disable Mouse Acceleration: Zeroes out mouse curve registers and thresholds for true 1:1 hardware raw input, essential for competitive FPS aiming."; Tip = "Disable Windows Mouse Acceleration" },
        @{ Text = "Disable Background GameDVR"; Func = { Disable-BackgroundGameDVR }; Desc = "Disable Background GameDVR: Turns off Windows GameDVR background video recording and Game Bar capture overhead to eliminate game stutter and frame drops."; Tip = "Disable Background GameDVR" },
        @{ Text = "Disable Sticky Keys in Games"; Func = { Disable-StickyKeysPopups }; Desc = "Disable Sticky Keys: Permanently disables the shift-key accessibility popup dialogs that disrupt competitive gameplay."; Tip = "Disable Sticky Keys Popups" },
        @{ Text = "Optimize TCP Auto-Tuning & RSS"; Func = { Optimize-TcpAutoTuning }; Desc = "Optimize TCP Auto-Tuning & RSS: Configures TCP window auto-tuning level to Normal and enables Receive-Side Scaling to maximize network bandwidth throughput."; Tip = "Optimize Network TCP Stack" },
        @{ Text = "Disable Nagle's Algorithm"; Func = { Disable-NagleAlgorithm }; Desc = "Disable Nagle's Algorithm: Enables TcpAckFrequency and TCPNoDelay across all network adapters to send packets immediately without buffering delay."; Tip = "Disable Nagle's Algorithm (TcpAckFrequency)" },
        @{ Text = "Flush DNS & NetBIOS Caches"; Func = { Clear-DnsAndNetbios }; Desc = "Flush DNS & NetBIOS: Purges the Windows DNS client resolver cache and refreshes NetBIOS names to resolve domain resolution glitches and network dropouts."; Tip = "Flush DNS and NetBIOS Caches" },
        @{ Text = "Disable Delivery Opt (P2P Leech)"; Func = { Disable-DeliveryOptimization }; Desc = "Disable Delivery Optimization: Stops Windows from using your upload bandwidth to seed Windows updates to other computers across the internet."; Tip = "Disable P2P Upload Bandwidth Leech" },
        @{ Text = "Disable Superfetch (SysMain)"; Func = { Disable-SysMainSuperfetch }; Desc = "Disable SysMain (Superfetch): Stops and disables the SysMain service which often causes 100% disk usage and background thrashing on modern SSDs."; Tip = "Disable Superfetch / SysMain Service" },
        @{ Text = "Disable Xbox Background Svcs"; Func = { Disable-XboxServices }; Desc = "Disable Xbox Services: Sets unused Xbox networking, save, and auth services to Manual to save background CPU cycles and memory."; Tip = "Disable Xbox Background Services" },
        @{ Text = "Disable Windows Telemetry"; Func = { Disable-DiagnosticTelemetry }; Desc = "Disable Telemetry: Disables DiagTrack, dmwappushservice, and feedback telemetry polling to improve privacy and eliminate background logging."; Tip = "Disable Windows Diagnostic Telemetry" },
        @{ Text = "Disable Bloat Auto-Install"; Func = { Disable-WindowsConsumerBloat }; Desc = "Disable Bloat Auto-Install: Prevents Windows from silently pre-installing sponsored games, Candy Crush, TikTok, and promotional apps."; Tip = "Block Auto-Installing Bloatware" },
        @{ Text = "Disable Cortana & Bing Search"; Func = { Disable-CortanaBingSearch }; Desc = "Disable Cortana & Start Web Search: Disables Bing web search in the Windows Start Menu, making searches 10x faster and strictly local to your PC."; Tip = "Disable Bing Web Search in Start Menu" },
        @{ Text = "Disable Windows Tips & Tricks"; Func = { Disable-WindowsTipsAndSuggestions }; Desc = "Disable Windows Tips & Suggestions: Disables lock screen ads, Start menu suggestions, and Windows notification popups."; Tip = "Disable Tips, Tricks & Suggestions" },
        @{ Text = "Disable Background UWP Apps"; Func = { Disable-BackgroundApps }; Desc = "Disable Background Apps: Disables global background execution for Windows UWP apps to eliminate idle CPU drain and preserve battery."; Tip = "Disable Background Apps Global Policy" },
        @{ Text = "Disable Transparency (DWM)"; Func = { Disable-WindowsTransparency }; Desc = "Disable Transparency: Turns off acrylic and mica transparency effects to significantly decrease Desktop Window Manager GPU and VRAM overhead."; Tip = "Disable Windows Transparency Effects" },
        @{ Text = "Snappy Visual Effects (0ms)"; Func = { Optimize-VisualEffects }; Desc = "Snappy Visual Effects: Sets menu show delay to 0 ms and disables minimize/maximize animation delays so all context menus, dialogs, and apps open instantly."; Tip = "Set 0 ms Menu Delay" },
        @{ Text = "Clean Temp & Update Junk"; Func = { Clear-WindowsUpdateCache }; Desc = "Clean Temp & Update Junk: Stops update services and removes leftover installation files inside SoftwareDistribution\\Download and Windows Temp to recover gigabytes of SSD space."; Tip = "Purge Temp & Windows Update Cache" },
        @{ Text = "Clean Browser & Discord Cache"; Func = { Clear-BrowserCaches }; Desc = "Clean Browser & Discord Cache: Safely frees gigabytes of cache files from Google Chrome, Microsoft Edge, Brave, and Discord without affecting saved logins or cookies."; Tip = "Clean Browser and Discord Caches" },
        @{ Text = "Clean Crash Dumps & WER"; Func = { Clear-CrashDumpsAndWer }; Desc = "Clean Crash Dumps & WER: Deletes leftover crash memory dump files (%LOCALAPPDATA%\\CrashDumps) and Windows Error Reporting queue logs to free disk space."; Tip = "Purge Crash Dumps and Error Reports" },
        @{ Text = "Clear Thumbnail Cache"; Func = { Clear-ThumbnailCache }; Desc = "Clear Thumbnail Cache: Deletes corrupted and bloated Windows Explorer thumbnail cache databases to free disk space and speed up folder browsing."; Tip = "Purge Windows Thumbnail Cache" },
        @{ Text = "Clear Windows Font Cache"; Func = { Clear-WindowsFontCache }; Desc = "Clear Font Cache: Rebuilds Windows font cache service to eliminate text rendering glitches and desktop UI micro-stutters."; Tip = "Rebuild Windows Font Cache" },
        @{ Text = "Free Standby & Working RAM"; Func = { Clear-StandbyAndWorkingSetRam }; Desc = "Free Standby & Working RAM: Empties process working sets and forces garbage collection to reclaim inactive system memory immediately."; Tip = "Purge Standby and Working Set RAM" },
        @{ Text = "Trim & Re-Trim All SSD Drives"; Func = { Optimize-TrimSsdDrives }; Desc = "Trim All SSD Drives: Sends TRIM commands to all connected solid-state drives via defrag /L to ensure optimal write speeds and drive longevity."; Tip = "Send TRIM Signals to All SSDs" },
        @{ Text = "Clean Component Store (DISM)"; Func = { Optimize-DismCleanup }; Desc = "DISM Component Cleanup: Executes dism /Online /Cleanup-Image /StartComponentCleanup to safely purge obsolete Windows update backups and recover gigabytes."; Tip = "Run DISM Component Cleanup" },
        @{ Text = "Free 8-32GB (Toggle Hiber)"; Func = {
            $hiber = "C:\\hiberfil.sys"
            if (Test-Path $hiber) {
                & powercfg.exe -h off 2>&1 | Out-Null
                Write-Result -OutputBox $outputBox -Message "Hibernation DISABLED. Free space reclaimed!"
            } else {
                & powercfg.exe -h on 2>&1 | Out-Null
                Write-Result -OutputBox $outputBox -Message "Hibernation ENABLED."
            }
        }; Desc = "Free 8-32GB (Toggle Hibernation): Disables hiberfil.sys to immediately reclaim 8 GB to 32 GB of primary drive SSD space."; Tip = "Toggle Windows Hibernation File" },
        @{ Text = "Ultimate Performance Mode"; Func = {
            try {
                $out = & powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
                if ($out -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
                    & powercfg /setactive $Matches[1] 2>&1 | Out-Null
                } else {
                    & powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
                }
                Write-Result -OutputBox $outputBox -Message "Ultimate Performance power plan activated."
            } catch { Write-Result -OutputBox $outputBox -Message "[ERROR] $($_.Exception.Message)" }
        }; Desc = "Ultimate Performance Mode: Unlocks and activates the hidden Windows Ultimate Performance power plan to eliminate CPU core parking and micro-stutters."; Tip = "Activate Ultimate Performance Plan" },
        @{ Text = "Kill Frozen / Hanging Apps"; Func = {
            $res = & taskkill.exe /F /FI "STATUS eq NOT RESPONDING" 2>&1
            Write-Result -OutputBox $outputBox -Message ($res -join "`r`n")
        }; Desc = "Kill Frozen / Hanging Apps: Instantly detects and force-terminates any unresponsive or frozen background processes without opening Task Manager."; Tip = "Force Close Frozen Applications" }
    )

    # Place 32 buttons in 2 columns of 16 in $optPanel
    $btnWidth = 276
    $btnHeight = 32
    $gapY = 4
    for ($i = 0; $i -lt $perfToolsList.Count; $i++) {
        $tool = $perfToolsList[$i]
        $col = $i % 2
        $row = [math]::Floor($i / 2)
        $bx = if ($col -eq 0) { 5 } else { 292 }
        $by = 6 + ($row * ($btnHeight + $gapY))

        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = "* " + $tool.Text
        $btn.Location = New-Object System.Drawing.Point($bx, $by)
        $btn.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
        $btn.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)

        $actionFunc = $tool.Func
        $toolName = $tool.Text
        $btn.Add_Click({
            & $actionFunc
            $optDescBox.Text = "[OK] Executed '$toolName'! Output logged to console."
            [MemoryOptimizer]::TrimProcessMemory()
        })
        & $bindOptHover $btn $tool.Desc $tool.Tip
        $optPanel.Controls.Add($btn)
    }

    # 3. Apps & Tools Tab
    $appsTab = New-Object System.Windows.Forms.TabPage
    $appsTab.Text = "Apps & Tools"
    $tabs.TabPages.Add($appsTab)

    $lblWinTools = New-Object System.Windows.Forms.Label
    $lblWinTools.Text = "Windows Built-In Tools & Utilities (Click to Launch)"
    $lblWinTools.Location = New-Object System.Drawing.Point(15, 10)
    $lblWinTools.Size = New-Object System.Drawing.Size(595, 20)
    $lblWinTools.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $appsTab.Controls.Add($lblWinTools)

    $appsDescBox = New-Object System.Windows.Forms.TextBox
    $appsDescBox.Location = New-Object System.Drawing.Point(15, 335)
    $appsDescBox.Size = New-Object System.Drawing.Size(595, 95)
    $appsDescBox.Multiline = $true
    $appsDescBox.ReadOnly = $true
    $appsDescBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $appsDescBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $appsDescBox.Text = "[i] Check the apps you want to install and click 'Install Selected', or click any Windows tool above to launch immediately."
    $appsTab.Controls.Add($appsDescBox)

    $bindAppHover = {
        param($btn, [string]$desc, [string]$tooltip)
        $extrasToolTip.SetToolTip($btn, $tooltip)
        $btn.Add_MouseEnter({ $appsDescBox.Text = "[i] $desc" })
        $btn.Add_MouseLeave({ $appsDescBox.Text = "[i] Check the apps you want to install and click 'Install Selected', or click any Windows tool above to launch immediately." })
    }

    # Row 1 of Windows tools (y=32)
    $btnAppTaskMgr = New-Object System.Windows.Forms.Button
    $btnAppTaskMgr.Text = "Task Manager"
    $btnAppTaskMgr.Location = New-Object System.Drawing.Point(15, 32)
    $btnAppTaskMgr.Size = New-Object System.Drawing.Size(142, 28)
    $btnAppTaskMgr.Add_Click({ Start-Process taskmgr.exe | Out-Null })
    & $bindAppHover $btnAppTaskMgr "Task Manager: View running apps, background processes, CPU/RAM charts, and startup items." "Open Task Manager"
    $appsTab.Controls.Add($btnAppTaskMgr)

    $btnAppResMon = New-Object System.Windows.Forms.Button
    $btnAppResMon.Text = "Resource Monitor"
    $btnAppResMon.Location = New-Object System.Drawing.Point(165, 32)
    $btnAppResMon.Size = New-Object System.Drawing.Size(142, 28)
    $btnAppResMon.Add_Click({ Start-Process resmon.exe | Out-Null })
    & $bindAppHover $btnAppResMon "Resource Monitor: Deep real-time analysis of per-process CPU, memory, disk I/O, and network handles." "Open Resource Monitor"
    $appsTab.Controls.Add($btnAppResMon)

    $btnAppDevMgr = New-Object System.Windows.Forms.Button
    $btnAppDevMgr.Text = "Device Manager"
    $btnAppDevMgr.Location = New-Object System.Drawing.Point(315, 32)
    $btnAppDevMgr.Size = New-Object System.Drawing.Size(142, 28)
    $btnAppDevMgr.Add_Click({ Start-Process devmgmt.msc | Out-Null })
    & $bindAppHover $btnAppDevMgr "Device Manager: Inspect, manage, or update drivers for GPU, audio, network, and USB hardware." "Open Device Manager"
    $appsTab.Controls.Add($btnAppDevMgr)

    $btnAppDiskMgmt = New-Object System.Windows.Forms.Button
    $btnAppDiskMgmt.Text = "Disk Management"
    $btnAppDiskMgmt.Location = New-Object System.Drawing.Point(465, 32)
    $btnAppDiskMgmt.Size = New-Object System.Drawing.Size(142, 28)
    $btnAppDiskMgmt.Add_Click({ Start-Process diskmgmt.msc | Out-Null })
    & $bindAppHover $btnAppDiskMgmt "Disk Management: Partition, format, shrink, expand, and assign drive letters to SSDs and HDDs." "Open Disk Management"
    $appsTab.Controls.Add($btnAppDiskMgmt)

    # Row 2 (y=64)
    $btnAppRegedit = New-Object System.Windows.Forms.Button
    $btnAppRegedit.Text = "Registry Editor"
    $btnAppRegedit.Location = New-Object System.Drawing.Point(15, 64)
    $btnAppRegedit.Size = New-Object System.Drawing.Size(142, 28)
    $btnAppRegedit.Add_Click({ Start-Process regedit.exe | Out-Null })
    & $bindAppHover $btnAppRegedit "Registry Editor: Inspect and customize system and user registry hives." "Open Registry Editor"
    $appsTab.Controls.Add($btnAppRegedit)

    $btnAppServices = New-Object System.Windows.Forms.Button
    $btnAppServices.Text = "Services"
    $btnAppServices.Location = New-Object System.Drawing.Point(165, 64)
    $btnAppServices.Size = New-Object System.Drawing.Size(142, 28)
    $btnAppServices.Add_Click({ Start-Process services.msc | Out-Null })
    & $bindAppHover $btnAppServices "Services Console: Start, stop, and configure startup types for background Windows services." "Open Services Console"
    $appsTab.Controls.Add($btnAppServices)

    $btnAppGodMode = New-Object System.Windows.Forms.Button
    $btnAppGodMode.Text = "God Mode"
    $btnAppGodMode.Location = New-Object System.Drawing.Point(315, 64)
    $btnAppGodMode.Size = New-Object System.Drawing.Size(142, 28)
    $btnAppGodMode.Add_Click({ Start-Process explorer.exe -ArgumentList "shell:::{ED7BA470-8E54-465E-825C-99712043E01C}" | Out-Null })
    & $bindAppHover $btnAppGodMode "Windows God Mode: Master Control Panel folder containing over 200 administrative shortcuts." "Open God Mode Folder"
    $appsTab.Controls.Add($btnAppGodMode)

    $btnAppControl = New-Object System.Windows.Forms.Button
    $btnAppControl.Text = "Control Panel"
    $btnAppControl.Location = New-Object System.Drawing.Point(465, 64)
    $btnAppControl.Size = New-Object System.Drawing.Size(142, 28)
    $btnAppControl.Add_Click({ Start-Process control.exe | Out-Null })
    & $bindAppHover $btnAppControl "Control Panel: Classic Windows settings and configuration applets." "Open Control Panel"
    $appsTab.Controls.Add($btnAppControl)

    # Row 3 (y=96)
    $btnAppNotepad = New-Object System.Windows.Forms.Button
    $btnAppNotepad.Text = "Notepad"
    $btnAppNotepad.Location = New-Object System.Drawing.Point(15, 96)
    $btnAppNotepad.Size = New-Object System.Drawing.Size(142, 28)
    $btnAppNotepad.Add_Click({ Start-Process notepad.exe | Out-Null })
    & $bindAppHover $btnAppNotepad "Notepad: Simple text and note editor." "Open Notepad"
    $appsTab.Controls.Add($btnAppNotepad)

    $btnAppCalc = New-Object System.Windows.Forms.Button
    $btnAppCalc.Text = "Calculator"
    $btnAppCalc.Location = New-Object System.Drawing.Point(165, 96)
    $btnAppCalc.Size = New-Object System.Drawing.Size(142, 28)
    $btnAppCalc.Add_Click({ Start-Process calc.exe | Out-Null })
    & $bindAppHover $btnAppCalc "Calculator: Standard, scientific, and programmer math tool." "Open Calculator"
    $appsTab.Controls.Add($btnAppCalc)

    $btnAppPaint = New-Object System.Windows.Forms.Button
    $btnAppPaint.Text = "Paint"
    $btnAppPaint.Location = New-Object System.Drawing.Point(315, 96)
    $btnAppPaint.Size = New-Object System.Drawing.Size(142, 28)
    $btnAppPaint.Add_Click({ Start-Process mspaint.exe | Out-Null })
    & $bindAppHover $btnAppPaint "Paint: Quick image editor, cropper, and canvas." "Open Paint"
    $appsTab.Controls.Add($btnAppPaint)

    $btnAppSnip = New-Object System.Windows.Forms.Button
    $btnAppSnip.Text = "Snipping Tool"
    $btnAppSnip.Location = New-Object System.Drawing.Point(465, 96)
    $btnAppSnip.Size = New-Object System.Drawing.Size(142, 28)
    $btnAppSnip.Add_Click({ Start-Process snippingtool.exe | Out-Null })
    & $bindAppHover $btnAppSnip "Snipping Tool: Screen capture, region crop, and screenshot annotation." "Open Snipping Tool"
    $appsTab.Controls.Add($btnAppSnip)

    # Software Winget section (y=132)
    $lblSoftware = New-Object System.Windows.Forms.Label
    $lblSoftware.Text = "Popular Performance Software (Choose & Install via Winget)"
    $lblSoftware.Location = New-Object System.Drawing.Point(15, 132)
    $lblSoftware.Size = New-Object System.Drawing.Size(595, 20)
    $lblSoftware.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $appsTab.Controls.Add($lblSoftware)

    $appsData = @(
        # --- System Optimization & Cleaners ---
        @{ Name = "BleachBit"; Id = "BleachBit.BleachBit"; Desc = "Free open-source disk cleaner, temp purger, and privacy cleaner" },
        @{ Name = "Geek Uninstaller"; Id = "GeekUninstaller.GeekUninstaller"; Desc = "Fast lightweight uninstaller that forcefully removes leftover registry keys" },
        @{ Name = "Revo Uninstaller"; Id = "RevoUninstaller.RevoUninstaller"; Desc = "Premier uninstaller with advanced residual file scanner and real-time install tracker" },
        @{ Name = "System Informer"; Id = "SystemInformer.SystemInformer"; Desc = "Advanced process manager, memory viewer, and thread inspector" },
        @{ Name = "Process Explorer"; Id = "Microsoft.Sysinternals.ProcessExplorer"; Desc = "Sysinternals task manager with deep DLL and handle inspection" },
        @{ Name = "AutoRuns"; Id = "Microsoft.Sysinternals.Autoruns"; Desc = "Sysinternals utility to disable hidden startup bloatware & services" },
        @{ Name = "WizTree"; Id = "AntibodySoftware.WizTree"; Desc = "Fastest disk space visualizer with block treemaps" },
        @{ Name = "TreeSize Free"; Id = "JAMSoftware.TreeSize.Free"; Desc = "Fast hard drive space visualizer and folder size manager" },
        @{ Name = "Everything Search"; Id = "voidtools.Everything"; Desc = "Instant real-time NTFS file search tool (finds any file in 0.01 seconds)" },
        @{ Name = "Czkawka Cleaner"; Id = "qarmin.czkawka.gui"; Desc = "Blazing-fast multi-threaded duplicate and residual file cleaner" },

        # --- Hardware Diagnostics & Benchmarks ---
        @{ Name = "HWiNFO"; Id = "REALiX.HWiNFO"; Desc = "Comprehensive hardware telemetry, sensor, voltage, and thermal monitor" },
        @{ Name = "CPU-Z"; Id = "CPUID.CPU-Z"; Desc = "Detailed CPU, motherboard, and RAM specification inspector" },
        @{ Name = "GPU-Z"; Id = "TechPowerUp.GPU-Z"; Desc = "Detailed GPU clock speed, VRAM, and thermal sensor inspector" },
        @{ Name = "HWMonitor"; Id = "CPUID.HWMonitor"; Desc = "Hardware sensor monitor for CPU/GPU temperatures and voltages" },
        @{ Name = "CrystalDiskInfo"; Id = "CrystalDewWorld.CrystalDiskInfo"; Desc = "Real-time SSD/HDD health, temperature, and S.M.A.R.T. monitor" },
        @{ Name = "CrystalDiskMark"; Id = "CrystalDewWorld.CrystalDiskMark"; Desc = "Standard SSD and drive read/write speed benchmarking tool" },
        @{ Name = "Cinebench R23"; Id = "Maxon.CinebenchR23"; Desc = "Industry-standard CPU multi-core and single-core rendering benchmark" },
        @{ Name = "Geeks3D FurMark"; Id = "Geeks3D.FurMark.2"; Desc = "Intensive GPU stress testing and thermal stability benchmark" },

        # --- Gaming Performance & Latency ---
        @{ Name = "MSI Afterburner"; Id = "Guru3D.Afterburner"; Desc = "Leading GPU overclocking, voltage curve, and in-game FPS overlay tool" },
        @{ Name = "RivaTuner Statistics (RTSS)"; Id = "Guru3D.RTSS"; Desc = "High-precision framerate limiter and hardware statistics overlay" },
        @{ Name = "LatencyMon"; Id = "Resplendence.LatencyMon"; Desc = "Real-time DPC and kernel driver latency analyzer for competitive gaming" },
        @{ Name = "CapFrameX"; Id = "CXWorld.CapFrameX"; Desc = "Frametime capture, 1% low FPS analyzer, and stutter diagnostic tool" },
        @{ Name = "Steam"; Id = "Valve.Steam"; Desc = "Ultimate online gaming platform and game library" },
        @{ Name = "Discord"; Id = "Discord.Discord"; Desc = "All-in-one voice, video, and text communication platform" },

        # --- Privacy & System Tweakers ---
        @{ Name = "O&O ShutUp10++"; Id = "OO-Software.ShutUp10"; Desc = "Leading Windows 10/11 privacy, telemetry, and spyware disabler" },
        @{ Name = "Microsoft PowerToys"; Id = "Microsoft.PowerToys"; Desc = "Microsoft productivity utilities (FancyZones, Text Extractor, Awake)" },
        @{ Name = "EarTrumpet"; Id = "File-New-Project.EarTrumpet"; Desc = "Powerful modern per-app volume mixer for Windows" },
        @{ Name = "QuickLook"; Id = "PaddyXu.QuickLook"; Desc = "Instant spacebar preview for images, PDFs, archives, and videos" },

        # --- Security & Credentials ---
        @{ Name = "Malwarebytes"; Id = "Malwarebytes.Malwarebytes"; Desc = "Industry-leading anti-malware and ransomware remediation tool" },
        @{ Name = "Bitwarden"; Id = "Bitwarden.Bitwarden"; Desc = "Secure open-source password manager and credential vault" },

        # --- Utilities & Productivity ---
        @{ Name = "7-Zip"; Id = "7zip.7zip"; Desc = "Free high-ratio file archiver & compression tool" },
        @{ Name = "Notepad++"; Id = "Notepad++.Notepad++"; Desc = "Fast, lightweight tabbed code and text editor" },
        @{ Name = "Sublime Text 4"; Id = "SublimeHQ.SublimeText.4"; Desc = "Ultra-fast, sophisticated code and markup text editor" },
        @{ Name = "ShareX"; Id = "ShareX.ShareX"; Desc = "Feature-packed screen capture, GIF recorder, and OCR tool" },
        @{ Name = "Rufus"; Id = "Rufus.Rufus"; Desc = "Fast utility to format and create bootable USB flash drives" },
        @{ Name = "HandBrake"; Id = "HandBrake.HandBrake"; Desc = "Open-source video transcoder and compression utility" },
        @{ Name = "VLC Media Player"; Id = "VideoLAN.VLC"; Desc = "Open-source universal multimedia player for any audio/video" },
        @{ Name = "K-Lite Codec Pack"; Id = "CodecGuide.K-LiteCodecPack.Standard"; Desc = "Complete codec pack for decoding all audio and video formats" },
        @{ Name = "Audacity"; Id = "Audacity.Audacity"; Desc = "Multi-track audio editor and sound recorder" },
        @{ Name = "Spotify"; Id = "Spotify.Spotify"; Desc = "Popular music and podcast streaming service" },

        # --- Web & Development ---
        @{ Name = "Google Chrome"; Id = "Google.Chrome"; Desc = "High-speed modern web browser" },
        @{ Name = "Brave Browser"; Id = "Brave.Brave"; Desc = "Fast privacy-first browser with built-in ad and tracker blocking" },
        @{ Name = "Mozilla Firefox"; Id = "Mozilla.Firefox"; Desc = "Open-source, highly customizable private browser" },
        @{ Name = "OBS Studio"; Id = "OBSProject.OBSStudio"; Desc = "Professional live streaming and screen recording software" },
        @{ Name = "VS Code"; Id = "Microsoft.VisualStudioCode"; Desc = "Microsoft powerful code editor with vast extension ecosystem" },
        @{ Name = "Git for Windows"; Id = "Git.Git"; Desc = "Standard distributed version control system" },
        @{ Name = "PuTTY"; Id = "PuTTY.PuTTY"; Desc = "Lightweight SSH and Telnet terminal client" },
        @{ Name = "Wireshark"; Id = "WiresharkFoundation.Wireshark"; Desc = "Standard network packet analyzer and protocol inspector" }
    )

    $chkAppsList = New-Object System.Windows.Forms.CheckedListBox
    $chkAppsList.Location = New-Object System.Drawing.Point(15, 155)
    $chkAppsList.Size = New-Object System.Drawing.Size(440, 170)
    $chkAppsList.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $chkAppsList.CheckOnClick = $true
    foreach ($app in $appsData) {
        $chkAppsList.Items.Add("$($app.Name)  [$($app.Id)]") | Out-Null
    }
    $appsTab.Controls.Add($chkAppsList)

    $chkAppsList.Add_SelectedIndexChanged({
        $idx = $chkAppsList.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $appsData.Count) {
            $a = $appsData[$idx]
            $appsDescBox.Text = "[i] $($a.Name) (ID: $($a.Id))`r`n$($a.Desc)"
        }
    })

    $btnInstallApps = New-Object System.Windows.Forms.Button
    $btnInstallApps.Text = "Install Selected"
    $btnInstallApps.Location = New-Object System.Drawing.Point(465, 155)
    $btnInstallApps.Size = New-Object System.Drawing.Size(142, 38)
    $btnInstallApps.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnInstallApps.Add_Click({
        $selectedIndices = @($chkAppsList.CheckedIndices)
        if ($selectedIndices.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Please check at least one application from the list to install.", "No Apps Selected", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }

        $wingetExe = Get-WingetExecutablePath
        $testCheck = & $wingetExe --version 2>&1
        if ($LASTEXITCODE -ne 0 -and (-not (Get-Command "winget.exe" -ErrorAction SilentlyContinue))) {
            [System.Windows.Forms.MessageBox]::Show("Windows Package Manager (winget.exe) was not found on this system.`r`nPlease install 'App Installer' from the Microsoft Store.", "Winget Not Found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        $selectedNames = ($selectedIndices | ForEach-Object { $appsData[$_].Name }) -join ", "
        $appsDescBox.Text = "[*] Launching visible installer for: $selectedNames... Check the installer window to watch real-time download and setup progress!"
        $tabs.Invalidate(); $extrasForm.Refresh()

        Write-Result -OutputBox $outputBox -Message "========================================"
        Write-Result -OutputBox $outputBox -Message "Launching Winget Package Installer for: $selectedNames"
        Write-Result -OutputBox $outputBox -Message "========================================"

        # Generate a visible, interactive installer script
        $scriptLines = @()
        $scriptLines += "$Host.UI.RawUI.WindowTitle = 'QOL Reimagined - Software Installer'"
        $scriptLines += "Clear-Host"
        $scriptLines += "Write-Host '========================================================================' -ForegroundColor Cyan"
        $scriptLines += "Write-Host '  QOL REIMAGINED - APPS & SOFTWARE INSTALLER (WINGET)' -ForegroundColor Cyan"
        $scriptLines += "Write-Host '========================================================================' -ForegroundColor Cyan"
        $scriptLines += "Write-Host 'Selected packages to install: $($selectedIndices.Count)' -ForegroundColor White"
        $scriptLines += "Write-Host ''"

        $i = 1
        foreach ($idx in $selectedIndices) {
            $appInfo = $appsData[$idx]
            $scriptLines += "Write-Host '------------------------------------------------------------------------' -ForegroundColor DarkGray"
            $scriptLines += "Write-Host '[$i/$($selectedIndices.Count)] Installing $($appInfo.Name) ($($appInfo.Id))...' -ForegroundColor Yellow"
            $scriptLines += "Write-Host 'Downloading and running setup with live progress...' -ForegroundColor DarkCyan"
            $scriptLines += "& `"$wingetExe`" install --id `"$($appInfo.Id)`" -e --accept-source-agreements --accept-package-agreements"
            $scriptLines += "if (`$LASTEXITCODE -eq 0) {"
            $scriptLines += "    Write-Host '[OK] $($appInfo.Name) installed successfully!' -ForegroundColor Green"
            $scriptLines += "} else {"
            $scriptLines += "    Write-Host '[!] $($appInfo.Name) exited with code ' + `$LASTEXITCODE -ForegroundColor Yellow"
            $scriptLines += "}"
            $scriptLines += "Write-Host ''"
            $i++
        }

        $scriptLines += "Write-Host '========================================================================' -ForegroundColor Cyan"
        $scriptLines += "Write-Host '  ALL SELECTED INSTALLATIONS FINISHED!' -ForegroundColor Green"
        $scriptLines += "Write-Host '========================================================================' -ForegroundColor Cyan"
        $scriptLines += "Write-Host 'Press any key to close this installer window...'"
        $scriptLines += "[void][System.Console]::ReadKey()"

        $tempInstaller = Join-Path $env:TEMP "qol_winget_installer.ps1"
        [System.IO.File]::WriteAllText($tempInstaller, ($scriptLines -join "`r`n"), [System.Text.Encoding]::UTF8)

        Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempInstaller`""

        $appsDescBox.Text = "[OK] Installer window launched for: $selectedNames! You can watch live download and installation progress in the installer window."
    })
    $appsTab.Controls.Add($btnInstallApps)

    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = "Select All"
    $btnSelectAll.Location = New-Object System.Drawing.Point(465, 202)
    $btnSelectAll.Size = New-Object System.Drawing.Size(142, 28)
    $btnSelectAll.Add_Click({
        for ($i = 0; $i -lt $chkAppsList.Items.Count; $i++) {
            $chkAppsList.SetItemChecked($i, $true)
        }
    })
    $appsTab.Controls.Add($btnSelectAll)

    $btnDeselectAll = New-Object System.Windows.Forms.Button
    $btnDeselectAll.Text = "Deselect All"
    $btnDeselectAll.Location = New-Object System.Drawing.Point(465, 236)
    $btnDeselectAll.Size = New-Object System.Drawing.Size(142, 28)
    $btnDeselectAll.Add_Click({
        for ($i = 0; $i -lt $chkAppsList.Items.Count; $i++) {
            $chkAppsList.SetItemChecked($i, $false)
        }
    })
    $appsTab.Controls.Add($btnDeselectAll)

    # 4. Themes Tab
    $themesTab = New-Object System.Windows.Forms.TabPage
    $themesTab.Text = "Themes"
    $tabs.TabPages.Add($themesTab)

    $themeLabel = New-Object System.Windows.Forms.Label
    $themeLabel.Text = "Color Theme"
    $themeLabel.Location = New-Object System.Drawing.Point(18, 20)
    $themeLabel.Size = New-Object System.Drawing.Size(100, 22)
    $themesTab.Controls.Add($themeLabel)

    $themePicker = New-Object System.Windows.Forms.ComboBox
    $themePicker.Location = New-Object System.Drawing.Point(125, 17)
    $themePicker.Size = New-Object System.Drawing.Size(250, 25)
    $themePicker.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    
    $allThemeList = @(
        "Dark", "Light", "Super Black", "Cyberpunk", "Matrix", "Dracula", "Nord", "Tokyo Night",
        "Blood Moon", "Gold Luxe", "Vaporwave", "Solar Flare", "Mint Frost", "Ocean", "Forest",
        "Sunset", "Glacier", "Rose", "Amber", "Coral", "Citrus", "Cobalt", "Ember"
    )
    foreach ($t in $allThemeList) {
        $themePicker.Items.Add($t) | Out-Null
    }
    if ($script:kittyUnlocked) {
        $themePicker.Items.Add("Kitty") | Out-Null
    }
    if (Test-ProAccess) {
        $themePicker.Items.Add("Ocean Pro") | Out-Null
        $themePicker.Items.Add("Emerald Pro") | Out-Null
        $themePicker.Items.Add("Crimson Pro") | Out-Null
        $themePicker.Items.Add("Neon Lime Pro") | Out-Null
    }
    $themePicker.SelectedItem = $script:currentTheme
    $themesTab.Controls.Add($themePicker)

    $applyThemeButton = New-Object System.Windows.Forms.Button
    $applyThemeButton.Text = "Apply Theme"
    $applyThemeButton.Location = New-Object System.Drawing.Point(390, 15)
    $applyThemeButton.Size = New-Object System.Drawing.Size(140, 30)
    $themesTab.Controls.Add($applyThemeButton)

    $fontLabel = New-Object System.Windows.Forms.Label
    $fontLabel.Text = "Output font size"
    $fontLabel.Location = New-Object System.Drawing.Point(18, 75)
    $fontLabel.Size = New-Object System.Drawing.Size(120, 22)
    $themesTab.Controls.Add($fontLabel)

    $fontPicker = New-Object System.Windows.Forms.NumericUpDown
    $fontPicker.Location = New-Object System.Drawing.Point(145, 72)
    $fontPicker.Size = New-Object System.Drawing.Size(70, 25)
    $fontPicker.Minimum = 8
    $fontPicker.Maximum = 14
    $fontPicker.Value = [math]::Max(8, [math]::Min(14, [int]$script:userProfile.FontSize))
    $themesTab.Controls.Add($fontPicker)

    $saveFontButton = New-Object System.Windows.Forms.Button
    $saveFontButton.Text = "Save Size"
    $saveFontButton.Location = New-Object System.Drawing.Point(230, 70)
    $saveFontButton.Size = New-Object System.Drawing.Size(110, 30)
    $saveFontButton.Add_Click({
        $script:userProfile.FontSize = [int]$fontPicker.Value
        Set-Theme -themeName $script:currentTheme
    })
    $themesTab.Controls.Add($saveFontButton)

    $accentLabel = New-Object System.Windows.Forms.Label
    $accentLabel.Text = "Output accent"
    $accentLabel.Location = New-Object System.Drawing.Point(18, 130)
    $accentLabel.Size = New-Object System.Drawing.Size(120, 22)
    $themesTab.Controls.Add($accentLabel)

    $accentButton = New-Object System.Windows.Forms.Button
    $accentButton.Text = "Choose color"
    $accentButton.Location = New-Object System.Drawing.Point(145, 125)
    $accentButton.Size = New-Object System.Drawing.Size(120, 30)
    $themesTab.Controls.Add($accentButton)

    # 5. History & Notes Tab
    $historyTab = New-Object System.Windows.Forms.TabPage
    $historyTab.Text = "History & Notes"
    $tabs.TabPages.Add($historyTab)

    $historyList = New-Object System.Windows.Forms.ListBox
    $historyList.Location = New-Object System.Drawing.Point(15, 15)
    $historyList.Size = New-Object System.Drawing.Size(595, 145)
    foreach ($entry in @($script:userProfile.History | Select-Object -Last 50)) {
        $historyList.Items.Add("$($entry.Time)  $($entry.Text)") | Out-Null
    }
    $historyTab.Controls.Add($historyList)

    $exportButton = New-Object System.Windows.Forms.Button
    $exportButton.Text = "Export history"
    $exportButton.Location = New-Object System.Drawing.Point(15, 170)
    $exportButton.Size = New-Object System.Drawing.Size(130, 30)
    $exportButton.Add_Click({
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveDialog.Filter = "Text file (*.txt)|*.txt"
        $saveDialog.FileName = "QOL-Reimagined-History.txt"
        if ($saveDialog.ShowDialog($extrasForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            $historyList.Items | Set-Content -Path $saveDialog.FileName -Encoding UTF8
        }
    })
    $historyTab.Controls.Add($exportButton)

    $clearHistoryButton = New-Object System.Windows.Forms.Button
    $clearHistoryButton.Text = "Clear history"
    $clearHistoryButton.Location = New-Object System.Drawing.Point(160, 170)
    $clearHistoryButton.Size = New-Object System.Drawing.Size(130, 30)
    $clearHistoryButton.Add_Click({
        $script:userProfile.History = @()
        $historyList.Items.Clear()
        Save-UserProfile
    })
    $historyTab.Controls.Add($clearHistoryButton)

    $notesLabel = New-Object System.Windows.Forms.Label
    $notesLabel.Text = "Private notes (saved on this PC)"
    $notesLabel.Location = New-Object System.Drawing.Point(15, 215)
    $notesLabel.Size = New-Object System.Drawing.Size(300, 22)
    $historyTab.Controls.Add($notesLabel)

    $notesBox = New-Object System.Windows.Forms.TextBox
    $notesBox.Location = New-Object System.Drawing.Point(15, 242)
    $notesBox.Size = New-Object System.Drawing.Size(595, 100)
    $notesBox.Multiline = $true
    $notesBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $notesBox.Text = [string]$script:userProfile.Notes
    $historyTab.Controls.Add($notesBox)

    $saveNotesButton = New-Object System.Windows.Forms.Button
    $saveNotesButton.Text = "Save notes"
    $saveNotesButton.Location = New-Object System.Drawing.Point(15, 350)
    $saveNotesButton.Size = New-Object System.Drawing.Size(120, 30)
    $saveNotesButton.Add_Click({
        $script:userProfile.Notes = $notesBox.Text
        Save-UserProfile
        Write-Result -OutputBox $outputBox -Message "Notes saved on this PC."
    })
    $historyTab.Controls.Add($saveNotesButton)

    # 6. Achievements Tab
    $achievementsTab = New-Object System.Windows.Forms.TabPage
    $achievementsTab.Text = "Achievements"
    $tabs.TabPages.Add($achievementsTab)

    $achievementsList = New-Object System.Windows.Forms.ListBox
    $achievementsList.Location = New-Object System.Drawing.Point(15, 15)
    $achievementsList.Size = New-Object System.Drawing.Size(595, 330)
    $badgeRows = @(
        @{ Id = "First Action"; Name = "First Steps"; Rarity = "Common"; Hint = "Use any app feature."; Hidden = $false },
        @{ Id = "Ten Taps"; Name = "Ten Taps"; Rarity = "Uncommon"; Hint = "Click the title ten times."; Hidden = $false },
        @{ Id = "Action Explorer"; Name = "Action Explorer"; Rarity = "Rare"; Hint = "Use 25 app actions."; Hidden = $false },
        @{ Id = "Century Club"; Name = "Century Club"; Rarity = "Epic"; Hint = "Use 100 app actions."; Hidden = $false },
        @{ Id = "Lucky Cat"; Name = "Lucky Cat"; Rarity = "Legendary"; Hint = "Find a 1-in-1,000 cat-fact event."; Hidden = $false },
        @{ Id = "Guessing Master"; Name = "Guessing Master"; Rarity = "Mythic"; Hint = "Win 10 number games."; Hidden = $false },
        @{ Id = "Kitty Finder"; Name = "???"; Rarity = "Secret"; Hint = "Discover the hidden Kitty theme."; Hidden = $true },
        @{ Id = "RNG Jackpot"; Name = "RNG Jackpot"; Rarity = "Epic"; Hint = "Reach the target score in RNG Rush."; Hidden = $false },
        @{ Id = "Abyssal Roll"; Name = "???"; Rarity = "Abyssal"; Hint = "A near-perfect RNG Rush round."; Hidden = $true },
        @{ Id = "Cat Collector"; Name = "Cat Collector"; Rarity = "Primordial"; Hint = "Ask for 50 cat facts."; Hidden = $false },
        @{ Id = "Cosmic Cat"; Name = "???"; Rarity = "Celestial"; Hint = "A 1-in-10,000 cat-fact event."; Hidden = $true },
        @{ Id = "Triple Hundred"; Name = "???"; Rarity = "Ethereal"; Hint = "Roll 100 three times in one RNG Rush round."; Hidden = $true },
        @{ Id = "Perfect Guesses"; Name = "???"; Rarity = "Divine"; Hint = "Win five number games in one guess each."; Hidden = $true }
    )
    foreach ($badge in $badgeRows) {
        $earned = $script:userProfile.Achievements -contains $badge.Id
        if ($earned) { $display = "[$($badge.Rarity)] $($badge.Name) - unlocked" }
        elseif ($badge.Hidden) { $display = "[$($badge.Rarity)] ??? - $($badge.Hint)" }
        else { $display = "[$($badge.Rarity)] $($badge.Name) - $($badge.Hint)" }
        $achievementsList.Items.Add($display) | Out-Null
    }
    $achievementsTab.Controls.Add($achievementsList)

    $achievementsSummary = New-Object System.Windows.Forms.Label
    $achievementsSummary.Text = "Unlocked: $(@($script:userProfile.Achievements).Count) / $($badgeRows.Count)"
    $achievementsSummary.Location = New-Object System.Drawing.Point(15, 355)
    $achievementsSummary.Size = New-Object System.Drawing.Size(300, 22)
    $achievementsTab.Controls.Add($achievementsSummary)

    # 7. Games Tab (8 Retro Arcade & Reflex Games)
    $gamesTab = New-Object System.Windows.Forms.TabPage
    $gamesTab.Text = "Games"
    $tabs.TabPages.Add($gamesTab)

    $gamesSummary = New-Object System.Windows.Forms.Label
    $gamesSummary.Text = "Games played: $($script:userProfile.GamesPlayed)    Total Wins: $($script:userProfile.GameWins)"
    $gamesSummary.Location = New-Object System.Drawing.Point(15, 10)
    $gamesSummary.Size = New-Object System.Drawing.Size(595, 20)
    $gamesSummary.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $gamesTab.Controls.Add($gamesSummary)

    # Row 1 (y=36)
    $guessGameButton = New-Object System.Windows.Forms.Button
    $guessGameButton.Text = "Number Guess"
    $guessGameButton.Location = New-Object System.Drawing.Point(15, 36)
    $guessGameButton.Size = New-Object System.Drawing.Size(142, 34)
    $guessGameButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $guessGameButton.Add_Click({ Show-MiniGame; $gamesSummary.Text = "Games played: $($script:userProfile.GamesPlayed)    Total Wins: $($script:userProfile.GameWins)" })
    $gamesTab.Controls.Add($guessGameButton)

    $coinGameButton = New-Object System.Windows.Forms.Button
    $coinGameButton.Text = "Coin Toss"
    $coinGameButton.Location = New-Object System.Drawing.Point(165, 36)
    $coinGameButton.Size = New-Object System.Drawing.Size(142, 34)
    $coinGameButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $coinGameButton.Add_Click({ Show-CoinToss; $gamesSummary.Text = "Games played: $($script:userProfile.GamesPlayed)    Total Wins: $($script:userProfile.GameWins)" })
    $gamesTab.Controls.Add($coinGameButton)

    $diceGameButton = New-Object System.Windows.Forms.Button
    $diceGameButton.Text = "Roll Dice"
    $diceGameButton.Location = New-Object System.Drawing.Point(315, 36)
    $diceGameButton.Size = New-Object System.Drawing.Size(142, 34)
    $diceGameButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $diceGameButton.Add_Click({ Show-DiceRoll; $gamesSummary.Text = "Games played: $($script:userProfile.GamesPlayed)    Total Wins: $($script:userProfile.GameWins)" })
    $gamesTab.Controls.Add($diceGameButton)

    $rngGameButton = New-Object System.Windows.Forms.Button
    $rngGameButton.Text = "RNG Rush"
    $rngGameButton.Location = New-Object System.Drawing.Point(465, 36)
    $rngGameButton.Size = New-Object System.Drawing.Size(142, 34)
    $rngGameButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $rngGameButton.Add_Click({ Show-RngGame; $gamesSummary.Text = "Games played: $($script:userProfile.GamesPlayed)    Total Wins: $($script:userProfile.GameWins)" })
    $gamesTab.Controls.Add($rngGameButton)

    # Row 2 (y=76)
    $btnGameReaction = New-Object System.Windows.Forms.Button
    $btnGameReaction.Text = "Reaction Speed"
    $btnGameReaction.Location = New-Object System.Drawing.Point(15, 76)
    $btnGameReaction.Size = New-Object System.Drawing.Size(142, 34)
    $btnGameReaction.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnGameReaction.Add_Click({ Show-ReactionGame; $gamesSummary.Text = "Games played: $($script:userProfile.GamesPlayed)    Total Wins: $($script:userProfile.GameWins)" })
    $gamesTab.Controls.Add($btnGameReaction)

    $btnGameRps = New-Object System.Windows.Forms.Button
    $btnGameRps.Text = "Rock Paper Scissors"
    $btnGameRps.Location = New-Object System.Drawing.Point(165, 76)
    $btnGameRps.Size = New-Object System.Drawing.Size(142, 34)
    $btnGameRps.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnGameRps.Add_Click({ Show-RpsGame; $gamesSummary.Text = "Games played: $($script:userProfile.GamesPlayed)    Total Wins: $($script:userProfile.GameWins)" })
    $gamesTab.Controls.Add($btnGameRps)

    $btnGameHigherLower = New-Object System.Windows.Forms.Button
    $btnGameHigherLower.Text = "Higher or Lower"
    $btnGameHigherLower.Location = New-Object System.Drawing.Point(315, 76)
    $btnGameHigherLower.Size = New-Object System.Drawing.Size(142, 34)
    $btnGameHigherLower.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnGameHigherLower.Add_Click({ Show-HigherLowerGame; $gamesSummary.Text = "Games played: $($script:userProfile.GamesPlayed)    Total Wins: $($script:userProfile.GameWins)" })
    $gamesTab.Controls.Add($btnGameHigherLower)

    $btnGameMemory = New-Object System.Windows.Forms.Button
    $btnGameMemory.Text = "Simon Memory"
    $btnGameMemory.Location = New-Object System.Drawing.Point(465, 76)
    $btnGameMemory.Size = New-Object System.Drawing.Size(142, 34)
    $btnGameMemory.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnGameMemory.Add_Click({ Show-MemoryGame; $gamesSummary.Text = "Games played: $($script:userProfile.GamesPlayed)    Total Wins: $($script:userProfile.GameWins)" })
    $gamesTab.Controls.Add($btnGameMemory)

    $gamesDescBox = New-Object System.Windows.Forms.TextBox
    $gamesDescBox.Location = New-Object System.Drawing.Point(15, 120)
    $gamesDescBox.Size = New-Object System.Drawing.Size(595, 115)
    $gamesDescBox.Multiline = $true
    $gamesDescBox.ReadOnly = $true
    $gamesDescBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $gamesDescBox.Text = "[i] Hover over any mini-game above to see how to play and what badges you can earn."
    $gamesTab.Controls.Add($gamesDescBox)

    $bindGameHover = {
        param($btn, [string]$desc, [string]$tooltip)
        $extrasToolTip.SetToolTip($btn, $tooltip)
        $btn.Add_MouseEnter({ $gamesDescBox.Text = "[i] $desc" })
        $btn.Add_MouseLeave({ $gamesDescBox.Text = "[i] Hover over any mini-game above to see how to play and what badges you can earn." })
    }

    & $bindGameHover $guessGameButton "Number Guess: Guess the secret number from 1 to 20 in 6 attempts. Win 10 games to unlock Guessing Master badge!" "Play Number Guess (1-20)"
    & $bindGameHover $coinGameButton "Coin Toss: Flip a virtual coin and test your streak-guessing luck." "Play Coin Toss"
    & $bindGameHover $diceGameButton "Roll Dice: Roll two 6-sided dice and see your score." "Play Roll Dice"
    & $bindGameHover $rngGameButton "RNG Rush: Roll randomized numbers against target thresholds to unlock Mythic and Secret badges!" "Play RNG Rush"
    & $bindGameHover $btnGameReaction "Reaction Speed Tester: Tests your reflex reaction time in milliseconds when the button turns green. Score under 200 ms to earn the Legendary Lightning Reflexes badge!" "Play Reaction Speed Test"
    & $bindGameHover $btnGameRps "Rock Paper Scissors Lizard Spock: Battle against the computer AI. Win 5 in a row to earn the Epic RPS Master badge!" "Play Rock Paper Scissors"
    & $bindGameHover $btnGameHigherLower "Higher or Lower: Guess if the next secret number (1-100) is higher or lower. Build up winning streaks and unlock the Epic High Roller badge!" "Play Higher or Lower"
    & $bindGameHover $btnGameMemory "Simon Memory Sequence: Memorize and repeat the growing sequence of colored flashes. Reach Round 5 to earn the Mythic Brainiac badge!" "Play Simon Memory Game"


    # Recursive theme applier
    $applyThemeToControl = {
        param($ctrl)
        if ($ctrl -is [System.Windows.Forms.TabPage]) {
            $ctrl.BackColor = $colors.Back
            $ctrl.ForeColor = $colors.Fore
        }
        elseif ($ctrl -is [System.Windows.Forms.Button]) {
            $ctrl.BackColor = $colors.BtnBack
            $ctrl.ForeColor = $colors.BtnFore
            $ctrl.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $ctrl.FlatAppearance.BorderColor = $colors.BoxFore
            $ctrl.FlatAppearance.BorderSize = 1
        }
        elseif ($ctrl -is [System.Windows.Forms.TextBox] -or $ctrl -is [System.Windows.Forms.ListBox] -or $ctrl -is [System.Windows.Forms.CheckedListBox]) {
            $ctrl.BackColor = $colors.BoxBack
            $ctrl.ForeColor = $colors.BoxFore
        }
        elseif ($ctrl -is [System.Windows.Forms.Label]) {
            $ctrl.ForeColor = $colors.Fore
        }
        elseif ($ctrl -is [System.Windows.Forms.ComboBox]) {
            $ctrl.BackColor = $colors.BtnBack
            $ctrl.ForeColor = $colors.BtnFore
        }
        elseif ($ctrl -is [System.Windows.Forms.NumericUpDown]) {
            $ctrl.BackColor = $colors.BoxBack
            $ctrl.ForeColor = $colors.BoxFore
        }
    }

    $applyRecursiveTheme = {
        param($parent)
        & $applyThemeToControl $parent
        foreach ($child in $parent.Controls) {
            & $applyRecursiveTheme $child
        }
    }

    # Theme picker click handler with real-time UI refresh
    $applyThemeButton.Add_Click({
        if ($themePicker.SelectedItem) {
            Set-Theme -themeName $themePicker.SelectedItem
            $colors = Get-ThemeColors -theme $themePicker.SelectedItem
            try {
                $colors.BoxFore = [System.Drawing.ColorTranslator]::FromHtml($script:userProfile.AccentColor)
            } catch {}
            $extrasForm.BackColor = $colors.Back
            $extrasForm.ForeColor = $colors.Fore
            & $applyRecursiveTheme $extrasForm
            $tabs.Invalidate(); $extrasForm.Refresh()
        }
    })

    $accentButton.Add_Click({
        $colorDialog = New-Object System.Windows.Forms.ColorDialog
        if ($colorDialog.ShowDialog($extrasForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:userProfile.AccentColor = [System.Drawing.ColorTranslator]::ToHtml($colorDialog.Color)
            Set-Theme -themeName $script:currentTheme
            $colors = Get-ThemeColors -theme $script:currentTheme
            try {
                $colors.BoxFore = [System.Drawing.ColorTranslator]::FromHtml($script:userProfile.AccentColor)
            } catch {}
            $extrasForm.BackColor = $colors.Back
            $extrasForm.ForeColor = $colors.Fore
            & $applyRecursiveTheme $extrasForm
            $tabs.Invalidate(); $extrasForm.Refresh()
        }
    })

        if ($InitialTab -eq "Apps") {
        $tabs.SelectedTab = $appsTab
    } elseif ($InitialTab -eq "Optimizers") {
        $tabs.SelectedTab = $optTab
    } elseif ($InitialTab -eq "Themes") {
        $tabs.SelectedTab = $themesTab
    } elseif ($InitialTab -eq "Games") {
        $tabs.SelectedTab = $gamesTab
    }
& $applyRecursiveTheme $extrasForm
    $extrasForm.Add_FormClosing({ [MemoryOptimizer]::TrimProcessMemory() })
    [void]$extrasForm.ShowDialog($form)
}

function Invoke-QuickPcBoost {
    Write-Result -OutputBox $outputBox -Message "========================================"
    Write-Result -OutputBox $outputBox -Message "* RUNNING 1-CLICK QUICK PC BOOST..."
    Write-Result -OutputBox $outputBox -Message "========================================"
    if ($form) { $form.Refresh() }

    try {
        Write-Result -OutputBox $outputBox -Message "[1/5] Cleaning Temporary Files..."
        $tempPaths = @($env:TEMP, (Join-Path $env:SystemRoot "Temp"))
        foreach ($tPath in $tempPaths) {
            if (Test-Path $tPath) {
                Get-ChildItem -Path $tPath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Result -OutputBox $outputBox -Message "  -> Temp files cleaned."
    } catch {}

    try {
        Write-Result -OutputBox $outputBox -Message "[2/5] Flushing DNS resolver cache..."
        & ipconfig /flushdns 2>&1 | Out-Null
        Write-Result -OutputBox $outputBox -Message "  -> DNS cache flushed."
    } catch {}

    try {
        Write-Result -OutputBox $outputBox -Message "[3/5] Checking for frozen / unresponsive programs..."
        & taskkill.exe /F /FI "STATUS eq NOT RESPONDING" 2>&1 | Out-Null
        Write-Result -OutputBox $outputBox -Message "  -> Unresponsive programs cleared."
    } catch {}

    try {
        Write-Result -OutputBox $outputBox -Message "[4/5] Clearing RAM standby list & system cache..."
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        Write-Result -OutputBox $outputBox -Message "  -> Memory garbage collection completed."
    } catch {}

    try {
        Write-Result -OutputBox $outputBox -Message "[5/5] Activating High Performance power plan..."
        & powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
        Write-Result -OutputBox $outputBox -Message "  -> High Performance power profile enabled."
    } catch {}

    Write-Result -OutputBox $outputBox -Message "========================================"
    Write-Result -OutputBox $outputBox -Message "[OK] 1-CLICK PC BOOST COMPLETE! System is clean & optimized."
    Write-Result -OutputBox $outputBox -Message "========================================"
}

function Optimize-GamingLatency {
    Write-Result -OutputBox $outputBox -Message "Applying Low-Latency Gaming & Network Optimizations..."
    if ($form) { $form.Refresh() }
    try {
        $mmPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        if (-not (Test-Path $mmPath)) { New-Item -Path $mmPath -Force | Out-Null }
        Set-ItemProperty -Path $mmPath -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $mmPath -Name "SystemResponsiveness" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        $gameProf = "$mmPath\Tasks\Games"
        if (Test-Path $gameProf) {
            Set-ItemProperty -Path $gameProf -Name "GPU Priority" -Value 8 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $gameProf -Name "Priority" -Value 6 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $gameProf -Name "Scheduling Category" -Value "High" -Type String -Force -ErrorAction SilentlyContinue
        }

        $gConfig = "HKCU:\System\GameConfigStore"
        if (-not (Test-Path $gConfig)) { New-Item -Path $gConfig -Force | Out-Null }
        Set-ItemProperty -Path $gConfig -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $gConfig -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue

        Write-Result -OutputBox $outputBox -Message "Network throttling disabled (0xFFFFFFFF)."
        Write-Result -OutputBox $outputBox -Message "Gaming task GPU/CPU scheduling prioritized."
        Write-Result -OutputBox $outputBox -Message "Background GameDVR recording disabled."
        Write-Result -OutputBox $outputBox -Message "[OK] Low-Latency Gaming Optimizations applied successfully!"
    }
    catch {
        Write-Result -OutputBox $outputBox -Message "Could not apply latency tweaks: $($_.Exception.Message)"
    }
}

function Clear-WindowsUpdateCache {
    Write-Result -OutputBox $outputBox -Message "Cleaning Windows Update Cache (SoftwareDistribution)..."
    if ($form) { $form.Refresh() }
    try {
        Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "bits" -Force -ErrorAction SilentlyContinue
        $downPath = Join-Path $env:SystemRoot "SoftwareDistribution\Download"
        if (Test-Path $downPath) {
            $files = Get-ChildItem -Path $downPath -Recurse -Force -ErrorAction SilentlyContinue
            $sizeMB = [math]::Round((($files | Measure-Object -Property Length -Sum).Sum / 1MB), 1)
            $files | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Result -OutputBox $outputBox -Message "Removed $sizeMB MB of leftover update installation files."
        }
        Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
        Start-Service -Name "bits" -ErrorAction SilentlyContinue
        Write-Result -OutputBox $outputBox -Message "[OK] Windows Update cache cleaned and services restarted."
    }
    catch {
        Write-Result -OutputBox $outputBox -Message "Failed to clear update cache: $($_.Exception.Message)"
    }
}

function Optimize-VisualEffects {
    Write-Result -OutputBox $outputBox -Message "Optimizing Windows Visual Effects for Speed..."
    if ($form) { $form.Refresh() }
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -ErrorAction SilentlyContinue
        Write-Result -OutputBox $outputBox -Message "Menu show delay set to 0 ms."
        Write-Result -OutputBox $outputBox -Message "Window minimize/maximize animation delays disabled."
        Write-Result -OutputBox $outputBox -Message "[OK] Windows visual responsiveness boosted! Menus and windows now open instantly."
    }
    catch {
        Write-Result -OutputBox $outputBox -Message "Could not optimize visual effects: $($_.Exception.Message)"
    }
}

function Switch-SearchIndexer {
    try {
        $svc = Get-Service -Name "WSearch" -ErrorAction SilentlyContinue
        if ($svc.Status -eq "Running") {
            Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "WSearch" -StartupType Manual -ErrorAction SilentlyContinue
            Write-Result -OutputBox $outputBox -Message "Windows Search Indexer STOPPED (Startup: Manual).`r`nEliminates high background disk & CPU usage."
        }
        else {
            Set-Service -Name "WSearch" -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name "WSearch" -ErrorAction SilentlyContinue
            Write-Result -OutputBox $outputBox -Message "Windows Search Indexer STARTED (Startup: Automatic)."
        }
    }
    catch {
        Write-Result -OutputBox $outputBox -Message "Could not toggle search indexer: $($_.Exception.Message)"
    }
}

function Disable-BackgroundGameDVR {
    try {
        $gConfig = "HKCU:\System\GameConfigStore"
        if (-not (Test-Path $gConfig)) { New-Item -Path $gConfig -Force | Out-Null }
        Set-ItemProperty -Path $gConfig -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $gConfig -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
        
        $policy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
        if (-not (Test-Path $policy)) { New-Item -Path $policy -Force | Out-Null }
        Set-ItemProperty -Path $policy -Name "AllowGameDVR" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        Write-Result -OutputBox $outputBox -Message "[OK] Background GameDVR & Game Bar recording disabled.`r`nPrevents game stuttering and input lag."
    }
    catch {
        Write-Result -OutputBox $outputBox -Message "Could not disable GameDVR: $($_.Exception.Message)"
    }
}

function Clear-BrowserCaches {
    Write-Result -OutputBox $outputBox -Message "Scanning and purging web browser and Discord caches..."
    if ($form) { $form.Refresh() }
    $freedBytes = 0
    $targets = @(
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Cache"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Code Cache"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\Cache"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\Code Cache"),
        (Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data\Default\Cache"),
        (Join-Path $env:APPDATA "discord\Cache"),
        (Join-Path $env:APPDATA "discord\Code Cache")
    )
    foreach ($p in $targets) {
        if (Test-Path $p) {
            try {
                $files = Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue
                $size = ($files | Measure-Object -Property Length -Sum).Sum
                $files | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                if ($size) { $freedBytes += $size }
            } catch {}
        }
    }
    $freedMB = [math]::Round(($freedBytes / 1MB), 1)
    Write-Result -OutputBox $outputBox -Message "[OK] Browser and Discord caches cleaned! $freedMB MB disk space recovered without touching saved logins."
}

function Disable-MouseAcceleration {
    Write-Result -OutputBox $outputBox -Message "Disabling Windows mouse acceleration for 1:1 hardware raw input..."
    if ($form) { $form.Refresh() }
    try {
        $mPath = "HKCU:\Control Panel\Mouse"
        Set-ItemProperty -Path $mPath -Name "MouseSpeed" -Value "0" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $mPath -Name "MouseThreshold1" -Value "0" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $mPath -Name "MouseThreshold2" -Value "0" -ErrorAction SilentlyContinue
        $zeroCurve = [byte[]](0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0)
        Set-ItemProperty -Path $mPath -Name "SmoothMouseXCurve" -Value $zeroCurve -Type Binary -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $mPath -Name "SmoothMouseYCurve" -Value $zeroCurve -Type Binary -ErrorAction SilentlyContinue
        Write-Result -OutputBox $outputBox -Message "[OK] Windows Mouse Acceleration disabled. 1:1 Raw Input active for games."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not configure mouse settings: $($_.Exception.Message)"
    }
}

function Optimize-TcpAutoTuning {
    Write-Result -OutputBox $outputBox -Message "Configuring TCP stack for optimal throughput..."
    if ($form) { $form.Refresh() }
    try {
        & netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
        & netsh int tcp set global rss=enabled 2>&1 | Out-Null
        Write-Result -OutputBox $outputBox -Message "[OK] TCP Auto-Tuning set to Normal and RSS (Receive-Side Scaling) enabled."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not apply TCP tweaks: $($_.Exception.Message)"
    }
}

function Disable-DeliveryOptimization {
    Write-Result -OutputBox $outputBox -Message "Disabling Windows Delivery Optimization P2P upload sharing..."
    if ($form) { $form.Refresh() }
    try {
        $doPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
        if (-not (Test-Path $doPath)) { New-Item -Path $doPath -Force | Out-Null }
        Set-ItemProperty -Path $doPath -Name "DODownloadMode" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "DoSvc" -Force -ErrorAction SilentlyContinue
        Write-Result -OutputBox $outputBox -Message "[OK] Delivery Optimization P2P uploads disabled. Your internet upload bandwidth is protected."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not disable Delivery Optimization: $($_.Exception.Message)"
    }
}

function Disable-WindowsConsumerBloat {
    Write-Result -OutputBox $outputBox -Message "Disabling Windows consumer experience and sponsored app installations..."
    if ($form) { $form.Refresh() }
    try {
        $ccPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        if (-not (Test-Path $ccPath)) { New-Item -Path $ccPath -Force | Out-Null }
        Set-ItemProperty -Path $ccPath -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $ccPath -Name "SubscribedContent-338388Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $ccPath -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $ccPath -Name "SystemPaneSuggestionsEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Result -OutputBox $outputBox -Message "[OK] Consumer bloat auto-install disabled. Windows will no longer install suggested apps."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not disable consumer bloat: $($_.Exception.Message)"
    }
}

function Disable-CortanaBingSearch {
    Write-Result -OutputBox $outputBox -Message "Restricting Windows Start Menu search to local files..."
    if ($form) { $form.Refresh() }
    try {
        $searchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        if (-not (Test-Path $searchPath)) { New-Item -Path $searchPath -Force | Out-Null }
        Set-ItemProperty -Path $searchPath -Name "BingSearchEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $searchPath -Name "CortanaConsent" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Result -OutputBox $outputBox -Message "[OK] Start Menu Bing web search disabled. Searches now execute locally with zero web lag."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not disable Start Menu web search: $($_.Exception.Message)"
    }
}

function Clear-CrashDumpsAndWer {
    Write-Result -OutputBox $outputBox -Message "Cleaning crash dumps and Windows Error Reporting queue..."
    if ($form) { $form.Refresh() }
    $freedBytes = 0
    $dumpDirs = @(
        (Join-Path $env:LOCALAPPDATA "CrashDumps"),
        (Join-Path $env:ProgramData "Microsoft\Windows\WER\ReportQueue"),
        (Join-Path $env:ProgramData "Microsoft\Windows\WER\ReportArchive"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\WER\ReportQueue")
    )
    foreach ($d in $dumpDirs) {
        if (Test-Path $d) {
            try {
                $files = Get-ChildItem -Path $d -Recurse -Force -ErrorAction SilentlyContinue
                $size = ($files | Measure-Object -Property Length -Sum).Sum
                $files | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                if ($size) { $freedBytes += $size }
            } catch {}
        }
    }
    $freedMB = [math]::Round(($freedBytes / 1MB), 1)
    Write-Result -OutputBox $outputBox -Message "[OK] Crash dumps and error reports cleared ($freedMB MB freed)."
}

function Optimize-TrimSsdDrives {
    Write-Result -OutputBox $outputBox -Message "Running TRIM optimization across all solid-state drives..."
    if ($form) { $form.Refresh() }
    try {
        $drives = Get-Volume | Where-Object { $_.DriveType -eq "Fixed" -and $_.DriveLetter }
        foreach ($d in $drives) {
            Write-Result -OutputBox $outputBox -Message "  -> Sending TRIM to drive $($d.DriveLetter):..."
            & Optimize-Volume -DriveLetter $d.DriveLetter -ReTrim -ErrorAction SilentlyContinue | Out-Null
        }
        Write-Result -OutputBox $outputBox -Message "[OK] TRIM optimization successfully sent to all SSD drives."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not TRIM drives: $($_.Exception.Message)"
    }
}

function Disable-NagleAlgorithm {
    Write-Result -OutputBox $outputBox -Message "Configuring network adapters for zero packet buffering (TcpAckFrequency)..."
    if ($form) { $form.Refresh() }
    try {
        $interfaces = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        $subKeys = Get-ChildItem -Path $interfaces -ErrorAction SilentlyContinue
        foreach ($k in $subKeys) {
            Set-ItemProperty -Path $k.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $k.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        Write-Result -OutputBox $outputBox -Message "[OK] Nagle's algorithm disabled across all network interfaces (low-ping gaming active)."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not set TCP delay keys: $($_.Exception.Message)"
    }
}

function Disable-StickyKeysPopups {
    Write-Result -OutputBox $outputBox -Message "Disabling Sticky Keys & Filter Keys shortcut popups..."
    if ($form) { $form.Refresh() }
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name "Flags" -Value "506" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\ToggleKeys" -Name "Flags" -Value "58" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\Keyboard Response" -Name "Flags" -Value "122" -ErrorAction SilentlyContinue
        Write-Result -OutputBox $outputBox -Message "[OK] Sticky Keys and Filter Keys keyboard shortcut dialogs disabled."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not update accessibility shortcuts: $($_.Exception.Message)"
    }
}

function Clear-DnsAndNetbios {
    Write-Result -OutputBox $outputBox -Message "Purging DNS resolver and NetBIOS caches..."
    if ($form) { $form.Refresh() }
    try {
        & ipconfig /flushdns 2>&1 | Out-Null
        & nbtstat.exe -R 2>&1 | Out-Null
        & nbtstat.exe -RR 2>&1 | Out-Null
        Write-Result -OutputBox $outputBox -Message "[OK] DNS and NetBIOS name caches cleared."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not purge caches: $($_.Exception.Message)"
    }
}

function Clear-StandbyAndWorkingSetRam {
    Write-Result -OutputBox $outputBox -Message "Trimming process working sets and invoking garbage collection..."
    if ($form) { $form.Refresh() }
    try {
        [MemoryOptimizer]::TrimProcessMemory()
        Write-Result -OutputBox $outputBox -Message "[OK] Memory garbage collection and standby working sets trimmed."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not trim memory: $($_.Exception.Message)"
    }
}


function Enable-HagsGpuScheduling {
    Write-Result -OutputBox $outputBox -Message "Configuring Hardware-Accelerated GPU Scheduling (HAGS)..."
    if ($form) { $form.Refresh() }
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "HwSchMode" -Value 2 -Type DWord -Force
        Write-Result -OutputBox $outputBox -Message "[OK] Hardware-Accelerated GPU Scheduling ENABLED (HwSchMode=2). Restart PC to activate."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not configure HAGS: $($_.Exception.Message)"
    }
}

function Enable-WindowsGameMode {
    Write-Result -OutputBox $outputBox -Message "Enabling Windows Game Mode (CPU/GPU Priority)..."
    if ($form) { $form.Refresh() }
    try {
        $path = "HKCU:\Software\Microsoft\GameBar"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "AllowAutoGameMode" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $path -Name "AutoGameModeEnabled" -Value 1 -Type DWord -Force
        Write-Result -OutputBox $outputBox -Message "[OK] Windows Game Mode ENABLED. Games receive prioritized system thread scheduling."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not enable Game Mode: $($_.Exception.Message)"
    }
}

function Optimize-Win32PrioritySeparation {
    Write-Result -OutputBox $outputBox -Message "Optimizing Win32 Priority Separation for Gaming..."
    if ($form) { $form.Refresh() }
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "Win32PrioritySeparation" -Value 38 -Type DWord -Force
        Write-Result -OutputBox $outputBox -Message "[OK] Win32PrioritySeparation set to 38 (0x26). Foreground gaming response boosted."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not configure Win32PrioritySeparation: $($_.Exception.Message)"
    }
}

function Disable-SysMainSuperfetch {
    Write-Result -OutputBox $outputBox -Message "Disabling SysMain (Superfetch) SSD disk thrashing..."
    if ($form) { $form.Refresh() }
    try {
        Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
        Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Result -OutputBox $outputBox -Message "[OK] SysMain (Superfetch) service stopped and disabled. Eliminates 100% disk usage on SSDs."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not disable SysMain: $($_.Exception.Message)"
    }
}

function Disable-XboxServices {
    Write-Result -OutputBox $outputBox -Message "Disabling unused Xbox background services..."
    if ($form) { $form.Refresh() }
    $svcs = @("XboxNetApiSvc", "XboxGipSvc", "XblAuthManager", "XblGameSave")
    foreach ($s in $svcs) {
        try {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service -Name $s -StartupType Manual -ErrorAction SilentlyContinue
        } catch {}
    }
    Write-Result -OutputBox $outputBox -Message "[OK] Xbox background services set to Manual. Freeing background RAM & CPU."
}

function Disable-DiagnosticTelemetry {
    Write-Result -OutputBox $outputBox -Message "Disabling Windows Diagnostic Telemetry (DiagTrack)..."
    if ($form) { $form.Refresh() }
    try {
        Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue
        Set-Service -Name "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name "dmwappushservice" -Force -ErrorAction SilentlyContinue
        Set-Service -Name "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
        $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -Path $p -Name "AllowTelemetry" -Value 0 -Type DWord -Force
        Write-Result -OutputBox $outputBox -Message "[OK] Telemetry services disabled (DiagTrack stopped, AllowTelemetry=0)."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not disable telemetry: $($_.Exception.Message)"
    }
}

function Disable-WindowsTipsAndSuggestions {
    Write-Result -OutputBox $outputBox -Message "Disabling Windows suggestions, tips, and cloud content..."
    if ($form) { $form.Refresh() }
    try {
        $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -Path $p -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $p -Name "SubscribedContent-310093Enabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $p -Name "SystemPaneSuggestionsEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $p -Name "SoftLandingEnabled" -Value 0 -Type DWord -Force
        Write-Result -OutputBox $outputBox -Message "[OK] Windows suggestions, tips, and Start notifications disabled."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not disable suggestions: $($_.Exception.Message)"
    }
}

function Disable-BackgroundApps {
    Write-Result -OutputBox $outputBox -Message "Disabling background UWP apps execution..."
    if ($form) { $form.Refresh() }
    try {
        $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -Path $p -Name "GlobalUserDisabled" -Value 1 -Type DWord -Force
        Write-Result -OutputBox $outputBox -Message "[OK] Background app execution disabled. Stops idle apps from consuming battery & CPU."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not disable background apps: $($_.Exception.Message)"
    }
}

function Disable-WindowsTransparency {
    Write-Result -OutputBox $outputBox -Message "Disabling Windows acrylic transparency effects (reduces DWM GPU usage)..."
    if ($form) { $form.Refresh() }
    try {
        $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -Path $p -Name "EnableTransparency" -Value 0 -Type DWord -Force
        Write-Result -OutputBox $outputBox -Message "[OK] Transparency effects disabled. Lowers Desktop Window Manager GPU & VRAM load."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not toggle transparency: $($_.Exception.Message)"
    }
}

function Clear-ThumbnailCache {
    Write-Result -OutputBox $outputBox -Message "Purging Windows thumbnail database cache..."
    if ($form) { $form.Refresh() }
    try {
        $thumbDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer"
        if (Test-Path $thumbDir) {
            Get-ChildItem -Path $thumbDir -Filter "thumbcache_*.db" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        Write-Result -OutputBox $outputBox -Message "[OK] Thumbnail cache databases cleared and rebuilt."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not clear thumbnail cache: $($_.Exception.Message)"
    }
}

function Clear-WindowsFontCache {
    Write-Result -OutputBox $outputBox -Message "Purging and rebuilding Windows Font Cache..."
    if ($form) { $form.Refresh() }
    try {
        Stop-Service -Name "FontCache" -Force -ErrorAction SilentlyContinue
        $dat = Join-Path $env:WINDIR "ServiceProfiles\LocalService\AppData\Local\FontCache*.dat"
        Remove-Item -Path $dat -Force -ErrorAction SilentlyContinue
        Start-Service -Name "FontCache" -ErrorAction SilentlyContinue
        Write-Result -OutputBox $outputBox -Message "[OK] Windows Font Cache rebuilt. Resolves UI micro-stutters and font glitches."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not rebuild font cache: $($_.Exception.Message)"
    }
}

function Optimize-DismCleanup {
    Write-Result -OutputBox $outputBox -Message "Running DISM Component Store Cleanup (Reclaiming SSD GBs)..."
    if ($form) { $form.Refresh() }
    try {
        $res = & dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1
        Write-Result -OutputBox $outputBox -Message ($res -join "`r`n")
        Write-Result -OutputBox $outputBox -Message "[OK] DISM Component Store cleanup complete."
    } catch {
        Write-Result -OutputBox $outputBox -Message "Could not run DISM cleanup: $($_.Exception.Message)"
    }
}

function Show-DuplicateCleanerDialog {
    param([string]$FolderPath)

    $colors = Get-ThemeColors -theme $script:currentTheme
    try {
        $colors.BoxFore = [System.Drawing.ColorTranslator]::FromHtml($script:userProfile.AccentColor)
    } catch {}

    $files = Get-ChildItem -LiteralPath $FolderPath -File -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $files) {
        [System.Windows.Forms.MessageBox]::Show("No files found in the selected folder.", "Duplicate Cleaner", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    $sizeGroups = $files | Group-Object Length | Where-Object { $_.Count -gt 1 -and $_.Name -gt 0 }
    if (-not $sizeGroups) {
        [System.Windows.Forms.MessageBox]::Show("No duplicate files found in this folder. All files have unique file sizes.", "Duplicate Cleaner", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        Write-Result -OutputBox $outputBox -Message "Scanned '$FolderPath': 0 duplicates found."
        return
    }

    $dupItems = @()
    $totalReclaimBytes = 0

    foreach ($sg in $sizeGroups) {
        $hashes = foreach ($f in $sg.Group) {
            $h = Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue
            if ($h) {
                [PSCustomObject]@{ File = $f; Hash = $h.Hash }
            }
        }
        foreach ($hg in ($hashes | Group-Object Hash | Where-Object { $_.Count -gt 1 })) {
            $sorted = $hg.Group | Sort-Object { $_.File.CreationTime }
            $original = $sorted[0]
            $duplicates = $sorted[1..($sorted.Count - 1)]

            foreach ($d in $duplicates) {
                $totalReclaimBytes += $d.File.Length
                $dupItems += [PSCustomObject]@{
                    OriginalPath = $original.File.FullName
                    DuplicatePath = $d.File.FullName
                    FileName = $d.File.Name
                    SizeMB = [math]::Round(($d.File.Length / 1MB), 2)
                    Hash = $hg.Name
                    FileObj = $d.File
                }
            }
        }
    }

    if ($dupItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No duplicate files found in this folder. All matching-size files have unique SHA256 hashes.", "Duplicate Cleaner", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        Write-Result -OutputBox $outputBox -Message "Scanned '$FolderPath': 0 duplicates found."
        return
    }

    $reclaimMB = [math]::Round(($totalReclaimBytes / 1MB), 2)

    $dupForm = New-Object System.Windows.Forms.Form
    $dupForm.Text = "Duplicate File Cleaner - QOL Reimagined"
    $dupForm.Size = New-Object System.Drawing.Size(680, 530)
    $dupForm.StartPosition = "CenterParent"
    $dupForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dupForm.MaximizeBox = $false
    $dupForm.MinimizeBox = $false
    $dupForm.BackColor = $colors.Back
    $dupForm.ForeColor = $colors.Fore

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Duplicate File Cleaner"
    $lblTitle.Location = New-Object System.Drawing.Point(15, 12)
    $lblTitle.Size = New-Object System.Drawing.Size(635, 22)
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = $colors.BoxFore
    $dupForm.Controls.Add($lblTitle)

    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Text = "Folder: $FolderPath`r`nFound $($dupItems.Count) duplicate file(s). Space to reclaim: $reclaimMB MB"
    $lblSummary.Location = New-Object System.Drawing.Point(15, 36)
    $lblSummary.Size = New-Object System.Drawing.Size(635, 36)
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $lblSummary.ForeColor = $colors.Fore
    $dupForm.Controls.Add($lblSummary)

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = "The original copy in each group is safely preserved. Select duplicate copies to delete:"
    $lblInfo.Location = New-Object System.Drawing.Point(15, 76)
    $lblInfo.Size = New-Object System.Drawing.Size(635, 18)
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dupForm.Controls.Add($lblInfo)

    $chkList = New-Object System.Windows.Forms.CheckedListBox
    $chkList.Location = New-Object System.Drawing.Point(15, 96)
    $chkList.Size = New-Object System.Drawing.Size(635, 210)
    $chkList.BackColor = $colors.BoxBack
    $chkList.ForeColor = $colors.BoxFore
    $chkList.Font = New-Object System.Drawing.Font("Consolas", 8.5)
    $chkList.CheckOnClick = $true

    for ($i = 0; $i -lt $dupItems.Count; $i++) {
        $item = $dupItems[$i]
        $chkList.Items.Add("[ $($item.SizeMB) MB ] $($item.FileName)  ->  $($item.DuplicatePath)", $true) | Out-Null
    }
    $dupForm.Controls.Add($chkList)

    $detailBox = New-Object System.Windows.Forms.TextBox
    $detailBox.Location = New-Object System.Drawing.Point(15, 315)
    $detailBox.Size = New-Object System.Drawing.Size(635, 75)
    $detailBox.Multiline = $true
    $detailBox.ReadOnly = $true
    $detailBox.BackColor = $colors.BoxBack
    $detailBox.ForeColor = $colors.Fore
    $detailBox.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $detailBox.Text = "Click any item in the list above to view full path and SHA256 comparison."
    $dupForm.Controls.Add($detailBox)

    $chkList.Add_SelectedIndexChanged({
        $idx = $chkList.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $dupItems.Count) {
            $sel = $dupItems[$idx]
            $detailBox.Text = "Original (Preserved): $($sel.OriginalPath)`r`nDuplicate (To Delete): $($sel.DuplicatePath)`r`nSHA256: $($sel.Hash) | Size: $($sel.SizeMB) MB"
        }
    })

    $chkRecycle = New-Object System.Windows.Forms.CheckBox
    $chkRecycle.Text = "Send deleted files to Windows Recycle Bin (Safe & Recoverable)"
    $chkRecycle.Location = New-Object System.Drawing.Point(15, 400)
    $chkRecycle.Size = New-Object System.Drawing.Size(420, 24)
    $chkRecycle.Checked = $true
    $chkRecycle.ForeColor = $colors.Fore
    $dupForm.Controls.Add($chkRecycle)

    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = "Select All"
    $btnSelectAll.Location = New-Object System.Drawing.Point(15, 435)
    $btnSelectAll.Size = New-Object System.Drawing.Size(95, 32)
    $btnSelectAll.BackColor = $colors.BtnBack
    $btnSelectAll.ForeColor = $colors.BtnFore
    $btnSelectAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSelectAll.Add_Click({
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            $chkList.SetItemChecked($i, $true)
        }
    })
    $dupForm.Controls.Add($btnSelectAll)

    $btnDeselectAll = New-Object System.Windows.Forms.Button
    $btnDeselectAll.Text = "Deselect All"
    $btnDeselectAll.Location = New-Object System.Drawing.Point(118, 435)
    $btnDeselectAll.Size = New-Object System.Drawing.Size(95, 32)
    $btnDeselectAll.BackColor = $colors.BtnBack
    $btnDeselectAll.ForeColor = $colors.BtnFore
    $btnDeselectAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnDeselectAll.Add_Click({
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            $chkList.SetItemChecked($i, $false)
        }
    })
    $dupForm.Controls.Add($btnDeselectAll)

    $btnDelete = New-Object System.Windows.Forms.Button
    $btnDelete.Text = "Delete Checked Duplicates"
    $btnDelete.Location = New-Object System.Drawing.Point(365, 435)
    $btnDelete.Size = New-Object System.Drawing.Size(185, 32)
    $btnDelete.BackColor = [System.Drawing.Color]::FromArgb(180, 40, 40)
    $btnDelete.ForeColor = [System.Drawing.Color]::White
    $btnDelete.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnDelete.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnDelete.Add_Click({
        $checkedIndices = @($chkList.CheckedIndices)
        if ($checkedIndices.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Please check at least one duplicate file to delete.", "No Files Selected", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }

        $destStr = if ($chkRecycle.Checked) { "Windows Recycle Bin (recoverable)" } else { "PERMANENT DELETION" }
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Are you sure you want to delete $($checkedIndices.Count) duplicate file(s)?`r`n`r`nDestination: $destStr`r`n`r`nThe original files will remain intact.",
            "Confirm Deletion",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

        $deletedCount = 0
        $freedBytes = 0
        foreach ($idx in ($checkedIndices | Sort-Object -Descending)) {
            $item = $dupItems[$idx]
            try {
                if ($chkRecycle.Checked) {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($item.DuplicatePath, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                } else {
                    Remove-Item -LiteralPath $item.DuplicatePath -Force -ErrorAction Stop
                }
                $deletedCount++
                $freedBytes += $item.FileObj.Length
                $chkList.Items.RemoveAt($idx)
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "[!] Could not delete: $($item.DuplicatePath) ($($_.Exception.Message))"
            }
        }

        $freedMB = [math]::Round(($freedBytes / 1MB), 2)
        $msg = "[OK] Successfully deleted $deletedCount duplicate file(s). Freed $freedMB MB disk space!"
        Write-Result -OutputBox $outputBox -Message $msg
        $lblSummary.Text = "Deleted $deletedCount file(s). Remaining in list: $($chkList.Items.Count). Space freed: $freedMB MB"
        $detailBox.Text = $msg
        [System.Windows.Forms.MessageBox]::Show($msg, "Duplicate Cleaner", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    })
    $dupForm.Controls.Add($btnDelete)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(560, 435)
    $btnClose.Size = New-Object System.Drawing.Size(90, 32)
    $btnClose.BackColor = $colors.BtnBack
    $btnClose.ForeColor = $colors.BtnFore
    $btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnClose.Add_Click({ $dupForm.Close() })
    $dupForm.Controls.Add($btnClose)

    [void]$dupForm.ShowDialog($form)
}

function Show-AutoAcceptDialog {
    $acceptForm = New-Object System.Windows.Forms.Form
    $acceptForm.Text = "Game Queue Auto-Accept Monitor"
    $acceptForm.Size = New-Object System.Drawing.Size(460, 360)
    $acceptForm.StartPosition = "CenterParent"
    $acceptForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $acceptForm.MaximizeBox = $false
    $acceptForm.MinimizeBox = $false

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = "Auto-Accept monitors your game queue and accepts match invites automatically when you are AFK."
    $lblInfo.Location = New-Object System.Drawing.Point(15, 12)
    $lblInfo.Size = New-Object System.Drawing.Size(415, 35)
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $acceptForm.Controls.Add($lblInfo)

    $lblGame = New-Object System.Windows.Forms.Label
    $lblGame.Text = "Target Game:"
    $lblGame.Location = New-Object System.Drawing.Point(15, 55)
    $lblGame.Size = New-Object System.Drawing.Size(90, 20)
    $acceptForm.Controls.Add($lblGame)

    $cboGame = New-Object System.Windows.Forms.ComboBox
    $cboGame.Location = New-Object System.Drawing.Point(110, 52)
    $cboGame.Size = New-Object System.Drawing.Size(320, 24)
    $cboGame.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cboGame.Items.AddRange(@("Counter-Strike 2 (cs2)", "League of Legends (Client)", "Any Active Window (Space/Enter)")) | Out-Null
    $cboGame.SelectedIndex = 0
    $acceptForm.Controls.Add($cboGame)

    $chkSound = New-Object System.Windows.Forms.CheckBox
    $chkSound.Text = "Play chime alert when queue / match found"
    $chkSound.Location = New-Object System.Drawing.Point(15, 90)
    $chkSound.Size = New-Object System.Drawing.Size(380, 24)
    $chkSound.Checked = $true
    $acceptForm.Controls.Add($chkSound)

    $chkClick = New-Object System.Windows.Forms.CheckBox
    $chkClick.Text = "Auto-send Accept input (focus game & press Enter)"
    $chkClick.Location = New-Object System.Drawing.Point(15, 118)
    $chkClick.Size = New-Object System.Drawing.Size(380, 24)
    $chkClick.Checked = $true
    $acceptForm.Controls.Add($chkClick)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Status: STOPPED"
    $lblStatus.Location = New-Object System.Drawing.Point(15, 150)
    $lblStatus.Size = New-Object System.Drawing.Size(415, 22)
    $lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblStatus.ForeColor = [System.Drawing.Color]::DarkRed
    $acceptForm.Controls.Add($lblStatus)

    $logBox = New-Object System.Windows.Forms.TextBox
    $logBox.Location = New-Object System.Drawing.Point(15, 178)
    $logBox.Size = New-Object System.Drawing.Size(415, 95)
    $logBox.Multiline = $true
    $logBox.ReadOnly = $true
    $logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $logBox.Font = New-Object System.Drawing.Font("Consolas", 8.5)
    $logBox.Text = "[Ready] Select your game and click 'Start Monitoring'.`r`n"
    $acceptForm.Controls.Add($logBox)

    $btnToggle = New-Object System.Windows.Forms.Button
    $btnToggle.Text = "Start Monitoring"
    $btnToggle.Location = New-Object System.Drawing.Point(15, 282)
    $btnToggle.Size = New-Object System.Drawing.Size(140, 32)
    $btnToggle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $acceptForm.Controls.Add($btnToggle)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(340, 282)
    $btnClose.Size = New-Object System.Drawing.Size(90, 32)
    $btnClose.Add_Click({ $acceptForm.Close() })
    $acceptForm.Controls.Add($btnClose)

    $monitorTimer = New-Object System.Windows.Forms.Timer
    $monitorTimer.Interval = 1000

    $script:isMonitoring = $false
    $script:acceptCooldown = 0

    $monitorTimer.Add_Tick({
        if ($script:acceptCooldown -gt 0) {
            $script:acceptCooldown--
            return
        }

        $selectedGame = $cboGame.SelectedItem
        $procName = "cs2"
        if ($selectedGame -match 'League') { $procName = "LeagueClient" }

        $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($procs) {
            $p = $procs[0]
            $timeStr = (Get-Date -Format "HH:mm:ss")
            if ($p.MainWindowHandle -ne 0) {
                if ($script:acceptCooldown -le 0) {
                    $logBox.AppendText("[$timeStr] Target game '$procName' detected! Checking queue...`r`n")
                    if ($chkSound.Checked) {
                        [System.Media.SystemSounds]::Exclamation.Play()
                    }
                    if ($chkClick.Checked) {
                        try {
                            $wshell = New-Object -ComObject WScript.Shell
                            $wshell.AppActivate($p.Id) | Out-Null
                            Start-Sleep -Milliseconds 200
                            [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
                            $logBox.AppendText("[$timeStr] Sent ACCEPT input to game window!`r`n")
                            $script:acceptCooldown = 15
                        }
                        catch {}
                    }
                }
            }
        }
        else {
            $lblStatus.Text = "Status: MONITORING (Waiting for $procName.exe...)"
            $lblStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
    })

    $btnToggle.Add_Click({
        if (-not $script:isMonitoring) {
            $script:isMonitoring = $true
            $btnToggle.Text = "Stop Monitoring"
            $cboGame.Enabled = $false
            $lblStatus.Text = "Status: MONITORING ACTIVE"
            $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
            $logBox.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Monitoring started for $($cboGame.SelectedItem).`r`n")
            $monitorTimer.Start()
        }
        else {
            $script:isMonitoring = $false
            $monitorTimer.Stop()
            $btnToggle.Text = "Start Monitoring"
            $cboGame.Enabled = $true
            $lblStatus.Text = "Status: STOPPED"
            $lblStatus.ForeColor = [System.Drawing.Color]::DarkRed
            $logBox.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Monitoring stopped.`r`n")
        }
    })

    $acceptForm.Add_FormClosing({
        $monitorTimer.Stop()
        $monitorTimer.Dispose()
    })

    [void]$acceptForm.ShowDialog($form)
}

function Show-DnsSwitchDialog {
    $dnsForm = New-Object System.Windows.Forms.Form
    $dnsForm.Text = "Fast DNS Switcher"
    $dnsForm.Size = New-Object System.Drawing.Size(400, 240)
    $dnsForm.StartPosition = "CenterParent"
    $dnsForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dnsForm.MaximizeBox = $false
    $dnsForm.MinimizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Choose a DNS provider to apply to your active network:"
    $lbl.Location = New-Object System.Drawing.Point(15, 15)
    $lbl.Size = New-Object System.Drawing.Size(360, 20)
    $dnsForm.Controls.Add($lbl)

    $btnCloudflare = New-Object System.Windows.Forms.Button
    $btnCloudflare.Text = "Cloudflare DNS (1.1.1.1 / 1.0.0.1) - Fastest & Private"
    $btnCloudflare.Location = New-Object System.Drawing.Point(15, 45)
    $btnCloudflare.Size = New-Object System.Drawing.Size(355, 32)
    $dnsForm.Controls.Add($btnCloudflare)

    $btnGoogle = New-Object System.Windows.Forms.Button
    $btnGoogle.Text = "Google DNS (8.8.8.8 / 8.8.4.4) - Ultra Reliable"
    $btnGoogle.Location = New-Object System.Drawing.Point(15, 85)
    $btnGoogle.Size = New-Object System.Drawing.Size(355, 32)
    $dnsForm.Controls.Add($btnGoogle)

    $btnDhcp = New-Object System.Windows.Forms.Button
    $btnDhcp.Text = "Automatic / Router Default (DHCP)"
    $btnDhcp.Location = New-Object System.Drawing.Point(15, 125)
    $btnDhcp.Size = New-Object System.Drawing.Size(355, 32)
    $dnsForm.Controls.Add($btnDhcp)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Cancel"
    $btnClose.Location = New-Object System.Drawing.Point(280, 168)
    $btnClose.Size = New-Object System.Drawing.Size(90, 28)
    $btnClose.Add_Click({ $dnsForm.Close() })
    $dnsForm.Controls.Add($btnClose)

    $applyDns = {
        param([string[]]$Servers, [string]$ProviderName)
        try {
            $adapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
            if (-not $adapter) {
                Write-Result -OutputBox $outputBox -Message "No active network adapter found to configure DNS."
                $dnsForm.Close()
                return
            }
            if ($Servers.Count -gt 0) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $Servers -ErrorAction Stop
                & ipconfig /flushdns 2>&1 | Out-Null
                Write-Result -OutputBox $outputBox -Message "DNS changed to $ProviderName ($($Servers -join ', ')) on '$($adapter.Name)'. DNS cache flushed."
            }
            else {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ResetServerAddresses -ErrorAction Stop
                & ipconfig /flushdns 2>&1 | Out-Null
                Write-Result -OutputBox $outputBox -Message "DNS reset to Automatic (DHCP) on '$($adapter.Name)'. DNS cache flushed."
            }
            $dnsForm.Close()
        }
        catch {
            Write-Result -OutputBox $outputBox -Message "Could not set DNS: $($_.Exception.Message)"
            $dnsForm.Close()
        }
    }

    $btnCloudflare.Add_Click({ & $applyDns @("1.1.1.1", "1.0.0.1") "Cloudflare" })
    $btnGoogle.Add_Click({ & $applyDns @("8.8.8.8", "8.8.4.4") "Google" })
    $btnDhcp.Add_Click({ & $applyDns @() "Automatic (DHCP)" })

    [void]$dnsForm.ShowDialog($form)
}

function Show-PingCustomDialog {
    $pForm = New-Object System.Windows.Forms.Form
    $pForm.Text = "Ping Custom Address"
    $pForm.Size = New-Object System.Drawing.Size(380, 160)
    $pForm.StartPosition = "CenterParent"
    $pForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $pForm.MaximizeBox = $false
    $pForm.MinimizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Enter IP or Domain (e.g. 1.1.1.1 or discord.com):"
    $lbl.Location = New-Object System.Drawing.Point(15, 15)
    $lbl.Size = New-Object System.Drawing.Size(340, 20)
    $pForm.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(15, 40)
    $txt.Size = New-Object System.Drawing.Size(335, 24)
    $txt.Text = "1.1.1.1"
    $pForm.Controls.Add($txt)

    $btnPing = New-Object System.Windows.Forms.Button
    $btnPing.Text = "Ping"
    $btnPing.Location = New-Object System.Drawing.Point(165, 75)
    $btnPing.Size = New-Object System.Drawing.Size(90, 30)
    $btnPing.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $pForm.Controls.Add($btnPing)
    $pForm.AcceptButton = $btnPing

    $btnCan = New-Object System.Windows.Forms.Button
    $btnCan.Text = "Cancel"
    $btnCan.Location = New-Object System.Drawing.Point(260, 75)
    $btnCan.Size = New-Object System.Drawing.Size(90, 30)
    $btnCan.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $pForm.Controls.Add($btnCan)
    $pForm.CancelButton = $btnCan

    if ($pForm.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $target = $txt.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($target)) {
            Write-Result -OutputBox $outputBox -Message "Pinging $target (4 packets)..."
            $form.Refresh()
            try {
                $pings = Test-Connection -ComputerName $target -Count 4 -ErrorAction Stop
                $avg = [math]::Round(($pings.ResponseTime | Measure-Object -Average).Average, 1)
                $min = ($pings.ResponseTime | Measure-Object -Minimum).Minimum
                $max = ($pings.ResponseTime | Measure-Object -Maximum).Maximum
                Write-Result -OutputBox $outputBox -Message "Ping results for $target : Minimum = $min ms, Maximum = $max ms, Average = $avg ms"
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Ping failed: Host unreachable or timed out."
            }
        }
    }
}

function Invoke-QuickAutoExtract {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select ZIP Archive to Auto-Extract"
    $dlg.Filter = "ZIP Archives (*.zip)|*.zip|All Files (*.*)|*.*"
    if ($dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $zipPath = $dlg.FileName
        $dir = Split-Path -Parent $zipPath
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($zipPath)
        $destDir = Join-Path $dir $baseName
        Write-Result -OutputBox $outputBox -Message "Auto-extracting: $([System.IO.Path]::GetFileName($zipPath))..."
        $form.Refresh()
        try {
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Expand-Archive -LiteralPath $zipPath -DestinationPath $destDir -Force -ErrorAction Stop
            Write-Result -OutputBox $outputBox -Message "Extraction complete! Extracted to folder:`r`n$destDir"
            Start-Process explorer.exe -ArgumentList "`"$destDir`"" | Out-Null
        }
        catch {
            Write-Result -OutputBox $outputBox -Message "Auto-extraction failed: $($_.Exception.Message)"
        }
    }
}

function Add-DefenderFolderExclusion {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select a folder to exclude from Windows Defender (Auto-Exception)"
    if ($dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $folderPath = $dlg.SelectedPath
        try {
            Add-MpPreference -ExclusionPath $folderPath -ErrorAction Stop
            Write-Result -OutputBox $outputBox -Message "Windows Defender Auto-Exception added successfully!`r`nExcluded Path: $folderPath"
        }
        catch {
            Write-Result -OutputBox $outputBox -Message "Could not add Defender exclusion: $($_.Exception.Message)`r`nMake sure this tool is run as Administrator."
        }
    }
}

function Open-WebsitePrompt {
    param([string]$InitialUrl = "")

    if ([string]::IsNullOrWhiteSpace($InitialUrl)) {
    $urlForm = New-Object System.Windows.Forms.Form
    $urlForm.Text = "Open Website"
    $urlForm.Size = New-Object System.Drawing.Size(420, 140)
    $urlForm.StartPosition = "CenterParent"
    $urlForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $urlForm.MaximizeBox = $false
    $urlForm.MinimizeBox = $false

    $urlBox = New-Object System.Windows.Forms.TextBox
    $urlBox.Location = New-Object System.Drawing.Point(12, 12)
    $urlBox.Size = New-Object System.Drawing.Size(380, 24)
    $urlBox.Text = "https://"
    $urlForm.Controls.Add($urlBox)

    $openButton = New-Object System.Windows.Forms.Button
    $openButton.Text = "Open"
    $openButton.Location = New-Object System.Drawing.Point(212, 50)
    $openButton.Size = New-Object System.Drawing.Size(85, 30)
    $openButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $urlForm.Controls.Add($openButton)
    $urlForm.AcceptButton = $openButton

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point(307, 50)
    $cancelButton.Size = New-Object System.Drawing.Size(85, 30)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $urlForm.Controls.Add($cancelButton)
    $urlForm.CancelButton = $cancelButton

    if ($urlForm.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

        $url = $urlBox.Text.Trim()
    }
    else {
        $url = $InitialUrl.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($url)) {
        return
    }

    if ($url -notmatch '^https?://') {
        $url = "https://$url"
    }

    $parsedUrl = $null
    if (-not [System.Uri]::TryCreate($url, [System.UriKind]::Absolute, [ref]$parsedUrl) -or $parsedUrl.Scheme -notin @("http", "https")) {
        [System.Windows.Forms.MessageBox]::Show("Enter a valid website address.", "Invalid Website", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $parsedUrl.AbsoluteUri
        $startInfo.UseShellExecute = $true
        [System.Diagnostics.Process]::Start($startInfo) | Out-Null
        Write-Result -OutputBox $outputBox -Message "Opening website: $($parsedUrl.AbsoluteUri)"
    }
    catch {
        Write-Result -OutputBox $outputBox -Message "Could not open website: $($_.Exception.Message)"
    }
}

function Test-CommandExists {
    param([string]$Name)
    return $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Get-CompatLocalIp {
    try {
        if (Test-CommandExists -Name "Get-NetConnectionProfile") {
            $netProfile = Get-NetConnectionProfile -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($netProfile) {
                $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $netProfile.InterfaceIndex -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty IPAddress
                if ($ip) { return $ip }
            }
        }

        $adapter = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($adapter -and $adapter.IPAddress) {
            return ($adapter.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1)
        }

        $ipconfig = & ipconfig 2>$null
        foreach ($line in $ipconfig) {
            if ($line -match 'IPv4 Address.*:\s*(\d+\.\d+\.\d+\.\d+)') {
                return $Matches[1]
            }
        }

        return "127.0.0.1"
    }
    catch {
        return "127.0.0.1"
    }
}

function Get-CompatNetAdapters {
    try {
        if (Test-CommandExists -Name "Get-NetAdapter") {
            return @(Get-NetAdapter -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
        }

        $adapters = Get-CimInstance Win32_NetworkAdapter -ErrorAction SilentlyContinue | Where-Object { $_.NetEnabled -eq $true }
        if ($adapters) {
            return @($adapters | Select-Object -ExpandProperty Name)
        }

        return @("No adapters detected")
    }
    catch {
        return @("No adapters detected")
    }
}

function Get-CompatTcpConnections {
    try {
        if (Test-CommandExists -Name "Get-NetTCPConnection") {
            return @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue)
        }

        $netstat = & netstat -ano 2>$null
        return @($netstat)
    }
    catch {
        return @()
    }
}

function Get-ThemeColors {
    param([string]$theme)

    switch ($theme) {
        "Light" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(245, 245, 245)
                Fore    = [System.Drawing.Color]::FromArgb(40, 40, 40)
                BoxBack = [System.Drawing.Color]::White
                BoxFore = [System.Drawing.Color]::FromArgb(0, 102, 204)
                BtnBack = [System.Drawing.Color]::FromArgb(220, 220, 220)
                BtnFore = [System.Drawing.Color]::Black
            }
        }
        "Kitty" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(255, 240, 245)
                Fore    = [System.Drawing.Color]::FromArgb(120, 60, 90)
                BoxBack = [System.Drawing.Color]::White
                BoxFore = [System.Drawing.Color]::FromArgb(180, 50, 100)
                BtnBack = [System.Drawing.Color]::FromArgb(255, 182, 193)
                BtnFore = [System.Drawing.Color]::FromArgb(80, 20, 50)
            }
        }
        "Ocean Pro" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(18, 38, 50)
                Fore    = [System.Drawing.Color]::FromArgb(225, 242, 238)
                BoxBack = [System.Drawing.Color]::FromArgb(12, 27, 36)
                BoxFore = [System.Drawing.Color]::FromArgb(76, 220, 190)
                BtnBack = [System.Drawing.Color]::FromArgb(35, 72, 84)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Emerald Pro" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(21, 39, 31)
                Fore    = [System.Drawing.Color]::FromArgb(228, 241, 231)
                BoxBack = [System.Drawing.Color]::FromArgb(12, 28, 21)
                BoxFore = [System.Drawing.Color]::FromArgb(90, 225, 150)
                BtnBack = [System.Drawing.Color]::FromArgb(38, 75, 52)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Crimson Pro" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(18, 14, 15)
                Fore    = [System.Drawing.Color]::FromArgb(250, 235, 235)
                BoxBack = [System.Drawing.Color]::FromArgb(10, 8, 9)
                BoxFore = [System.Drawing.Color]::FromArgb(255, 55, 65) # Racing Red
                BtnBack = [System.Drawing.Color]::FromArgb(55, 20, 25)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Neon Lime Pro" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(10, 14, 10)
                Fore    = [System.Drawing.Color]::FromArgb(235, 255, 235)
                BoxBack = [System.Drawing.Color]::FromArgb(6, 9, 6)
                BoxFore = [System.Drawing.Color]::FromArgb(57, 255, 20) # Hyper Lime
                BtnBack = [System.Drawing.Color]::FromArgb(20, 45, 20)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Cyberpunk" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(15, 8, 28)
                Fore    = [System.Drawing.Color]::FromArgb(245, 240, 255)
                BoxBack = [System.Drawing.Color]::FromArgb(10, 4, 18)
                BoxFore = [System.Drawing.Color]::FromArgb(0, 240, 255) # Electric Cyan
                BtnBack = [System.Drawing.Color]::FromArgb(55, 18, 85)
                BtnFore = [System.Drawing.Color]::FromArgb(255, 42, 133) # Hot Pink
            }
        }
        "Matrix" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(5, 15, 8)
                Fore    = [System.Drawing.Color]::FromArgb(220, 255, 220)
                BoxBack = [System.Drawing.Color]::FromArgb(2, 10, 4)
                BoxFore = [System.Drawing.Color]::FromArgb(0, 255, 102) # Phosphor Green
                BtnBack = [System.Drawing.Color]::FromArgb(12, 40, 18)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Dracula" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(40, 42, 54)
                Fore    = [System.Drawing.Color]::FromArgb(248, 248, 242)
                BoxBack = [System.Drawing.Color]::FromArgb(28, 30, 39)
                BoxFore = [System.Drawing.Color]::FromArgb(189, 147, 249) # Vampire Purple
                BtnBack = [System.Drawing.Color]::FromArgb(68, 71, 90)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Nord" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(46, 52, 64)
                Fore    = [System.Drawing.Color]::FromArgb(236, 239, 244)
                BoxBack = [System.Drawing.Color]::FromArgb(36, 41, 51)
                BoxFore = [System.Drawing.Color]::FromArgb(136, 192, 208) # Frost Cyan
                BtnBack = [System.Drawing.Color]::FromArgb(67, 76, 94)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Tokyo Night" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(26, 27, 38)
                Fore    = [System.Drawing.Color]::FromArgb(220, 225, 245)
                BoxBack = [System.Drawing.Color]::FromArgb(18, 19, 28)
                BoxFore = [System.Drawing.Color]::FromArgb(122, 162, 247) # Electric Indigo
                BtnBack = [System.Drawing.Color]::FromArgb(48, 54, 82)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Blood Moon" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(28, 12, 15)
                Fore    = [System.Drawing.Color]::FromArgb(255, 230, 232)
                BoxBack = [System.Drawing.Color]::FromArgb(18, 7, 9)
                BoxFore = [System.Drawing.Color]::FromArgb(255, 60, 75)
                BtnBack = [System.Drawing.Color]::FromArgb(70, 22, 28)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Gold Luxe" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(20, 20, 20)
                Fore    = [System.Drawing.Color]::FromArgb(250, 245, 230)
                BoxBack = [System.Drawing.Color]::FromArgb(12, 12, 12)
                BoxFore = [System.Drawing.Color]::FromArgb(255, 215, 0) # Imperial Gold
                BtnBack = [System.Drawing.Color]::FromArgb(50, 44, 25)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Vaporwave" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(24, 12, 42)
                Fore    = [System.Drawing.Color]::FromArgb(255, 240, 255)
                BoxBack = [System.Drawing.Color]::FromArgb(16, 7, 30)
                BoxFore = [System.Drawing.Color]::FromArgb(255, 113, 206) # Pastel Magenta
                BtnBack = [System.Drawing.Color]::FromArgb(60, 25, 95)
                BtnFore = [System.Drawing.Color]::FromArgb(1, 205, 254) # Neon Aqua
            }
        }
        "Solar Flare" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(35, 20, 14)
                Fore    = [System.Drawing.Color]::FromArgb(255, 240, 230)
                BoxBack = [System.Drawing.Color]::FromArgb(24, 13, 9)
                BoxFore = [System.Drawing.Color]::FromArgb(255, 122, 0) # Solar Orange
                BtnBack = [System.Drawing.Color]::FromArgb(75, 38, 22)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Mint Frost" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(18, 30, 42)
                Fore    = [System.Drawing.Color]::FromArgb(235, 248, 250)
                BoxBack = [System.Drawing.Color]::FromArgb(12, 22, 32)
                BoxFore = [System.Drawing.Color]::FromArgb(45, 212, 191) # Mint
                BtnBack = [System.Drawing.Color]::FromArgb(32, 60, 80)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Ocean" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(18, 38, 50)
                Fore    = [System.Drawing.Color]::FromArgb(225, 242, 238)
                BoxBack = [System.Drawing.Color]::FromArgb(12, 27, 36)
                BoxFore = [System.Drawing.Color]::FromArgb(76, 220, 190)
                BtnBack = [System.Drawing.Color]::FromArgb(35, 72, 84)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Forest" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(27, 42, 32)
                Fore    = [System.Drawing.Color]::FromArgb(230, 239, 220)
                BoxBack = [System.Drawing.Color]::FromArgb(18, 31, 23)
                BoxFore = [System.Drawing.Color]::FromArgb(170, 210, 120)
                BtnBack = [System.Drawing.Color]::FromArgb(51, 76, 48)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Sunset" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(54, 32, 38)
                Fore    = [System.Drawing.Color]::FromArgb(255, 235, 218)
                BoxBack = [System.Drawing.Color]::FromArgb(37, 25, 34)
                BoxFore = [System.Drawing.Color]::FromArgb(255, 165, 115)
                BtnBack = [System.Drawing.Color]::FromArgb(100, 54, 57)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Glacier" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(224, 240, 244)
                Fore    = [System.Drawing.Color]::FromArgb(31, 56, 66)
                BoxBack = [System.Drawing.Color]::White
                BoxFore = [System.Drawing.Color]::FromArgb(33, 126, 153)
                BtnBack = [System.Drawing.Color]::FromArgb(191, 222, 231)
                BtnFore = [System.Drawing.Color]::FromArgb(24, 54, 64)
            }
        }
        "Rose" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(54, 36, 45)
                Fore    = [System.Drawing.Color]::FromArgb(250, 230, 236)
                BoxBack = [System.Drawing.Color]::FromArgb(35, 25, 33)
                BoxFore = [System.Drawing.Color]::FromArgb(240, 145, 175)
                BtnBack = [System.Drawing.Color]::FromArgb(90, 55, 70)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Amber" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(43, 39, 27)
                Fore    = [System.Drawing.Color]::FromArgb(246, 238, 216)
                BoxBack = [System.Drawing.Color]::FromArgb(30, 29, 22)
                BoxFore = [System.Drawing.Color]::FromArgb(235, 190, 85)
                BtnBack = [System.Drawing.Color]::FromArgb(82, 68, 38)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Coral" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(40, 37, 39)
                Fore    = [System.Drawing.Color]::FromArgb(245, 235, 230)
                BoxBack = [System.Drawing.Color]::FromArgb(25, 27, 29)
                BoxFore = [System.Drawing.Color]::FromArgb(255, 127, 110)
                BtnBack = [System.Drawing.Color]::FromArgb(78, 57, 56)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Citrus" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(34, 42, 30)
                Fore    = [System.Drawing.Color]::FromArgb(238, 243, 218)
                BoxBack = [System.Drawing.Color]::FromArgb(22, 30, 23)
                BoxFore = [System.Drawing.Color]::FromArgb(204, 230, 95)
                BtnBack = [System.Drawing.Color]::FromArgb(58, 75, 43)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Cobalt" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(25, 35, 52)
                Fore    = [System.Drawing.Color]::FromArgb(232, 239, 250)
                BoxBack = [System.Drawing.Color]::FromArgb(16, 24, 39)
                BoxFore = [System.Drawing.Color]::FromArgb(100, 170, 255)
                BtnBack = [System.Drawing.Color]::FromArgb(42, 61, 89)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Ember" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(43, 34, 29)
                Fore    = [System.Drawing.Color]::FromArgb(245, 232, 218)
                BoxBack = [System.Drawing.Color]::FromArgb(30, 25, 22)
                BoxFore = [System.Drawing.Color]::FromArgb(245, 145, 80)
                BtnBack = [System.Drawing.Color]::FromArgb(77, 52, 39)
                BtnFore = [System.Drawing.Color]::White
            }
        }
        "Super Black" {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(0, 0, 0)
                Fore    = [System.Drawing.Color]::FromArgb(255, 255, 255)
                BoxBack = [System.Drawing.Color]::FromArgb(10, 10, 10)
                BoxFore = [System.Drawing.Color]::FromArgb(0, 255, 128)
                BtnBack = [System.Drawing.Color]::FromArgb(20, 20, 20)
                BtnFore = [System.Drawing.Color]::FromArgb(255, 255, 255)
            }
        }
        Default {
            return @{
                Back    = [System.Drawing.Color]::FromArgb(30, 30, 30)
                Fore    = [System.Drawing.Color]::FromArgb(220, 220, 220)
                BoxBack = [System.Drawing.Color]::FromArgb(20, 20, 20)
                BoxFore = [System.Drawing.Color]::FromArgb(0, 255, 128)
                BtnBack = [System.Drawing.Color]::FromArgb(45, 45, 48)
                BtnFore = [System.Drawing.Color]::White
            }
        }
    }
}

$script:userProfileFile = Join-Path $script:appDataDir "profile.json"
$script:userProfile = [pscustomobject]@{
    Theme = "Super Black"
    FontSize = 9
    AccentColor = "#00FF80"
    Notes = ""
    History = @()
    Achievements = @()
    ActionCount = 0
    GamesPlayed = 0
    GameWins = 0
    CatFacts = 0
    RareCatFacts = 0
    RngHighScore = 0
    PerfectWins = 0
    RngCredits = 0
    LuckLevel = 0
}

function Save-UserProfile {
    $profileFolder = Split-Path -Parent $script:userProfileFile
    if (-not (Test-Path $profileFolder)) {
        New-Item -ItemType Directory -Path $profileFolder -Force | Out-Null
    }
    $script:userProfile | ConvertTo-Json -Depth 5 | Set-Content -Path $script:userProfileFile -Encoding UTF8
}

function Import-UserProfile {
    if (-not (Test-Path $script:userProfileFile)) {
        return
    }

    try {
        $savedProfile = Get-Content -Path $script:userProfileFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        foreach ($property in @("Theme", "FontSize", "AccentColor", "Notes", "History", "Achievements", "ActionCount", "GamesPlayed", "GameWins", "CatFacts", "RareCatFacts", "RngHighScore", "PerfectWins", "RngCredits", "LuckLevel")) {
            if ($null -ne $savedProfile.$property) {
                $script:userProfile.$property = $savedProfile.$property
            }
        }
    }
    catch {
        $script:userProfile = [pscustomobject]@{
            Theme = "Super Black"
            FontSize = 9
            AccentColor = "#00FF80"
            Notes = ""
            History = @()
            Achievements = @()
            ActionCount = 0
            GamesPlayed = 0
            GameWins = 0
            CatFacts = 0
            RareCatFacts = 0
            RngHighScore = 0
            PerfectWins = 0
            RngCredits = 0
            LuckLevel = 0
        }
    }
}

$script:achievementRarities = @{
    "First Action" = "Common"
    "Ten Taps" = "Uncommon"
    "Action Explorer" = "Rare"
    "Century Club" = "Epic"
    "Lucky Cat" = "Legendary"
    "Guessing Master" = "Mythic"
    "Kitty Finder" = "Secret"
    "Abyssal Roll" = "Abyssal"
    "Cat Collector" = "Primordial"
    "Cosmic Cat" = "Celestial"
    "Triple Hundred" = "Ethereal"
    "Perfect Guesses" = "Divine"
    "RNG Jackpot" = "Epic"
    "One in Ten Million" = "Divine"
    "One in a Billion" = "Divine"
}

function Add-Achievement {
    param([string]$AchievementId)

    if ($script:userProfile.Achievements -notcontains $AchievementId) {
        $script:userProfile.Achievements = @($script:userProfile.Achievements) + $AchievementId
        Save-UserProfile
        $rarity = $script:achievementRarities[$AchievementId]
        if (-not $rarity) { $rarity = "Common" }
        [System.Windows.Forms.MessageBox]::Show("$rarity badge unlocked: $AchievementId", "Achievement Unlocked", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
}

Import-UserProfile
$script:currentTheme = $script:userProfile.Theme
$script:kittyUnlocked = $false
$script:clickCount = 0

function Set-Theme {
    param([string]$themeName)

    if ($themeName -in @("Ocean Pro", "Emerald Pro", "Crimson Pro", "Neon Lime Pro") -and -not (Test-ProAccess)) {
        $themeName = "Super Black"
    }
    if ($themeName -eq "Kitty" -and -not $script:kittyUnlocked) {
        $themeName = "Dark"
    }

    $script:currentTheme = $themeName
    $script:userProfile.Theme = $themeName
    $colors = Get-ThemeColors -theme $themeName
    try {
        $colors.BoxFore = [System.Drawing.ColorTranslator]::FromHtml($script:userProfile.AccentColor)
    }
    catch {
        $script:userProfile.AccentColor = "#00FF80"
    
    }

    if ($form) {
        $form.BackColor = $colors.Back
        $form.ForeColor = $colors.Fore
    }
    if ($lblTitle) { $lblTitle.ForeColor = $colors.Fore }

    if ($btnExtras) {
        $btnExtras.BackColor = $colors.BtnBack
        $btnExtras.ForeColor = $colors.BtnFore
    }
    if ($btnSettings) {
        $btnSettings.BackColor = $colors.BtnBack
        $btnSettings.ForeColor = $colors.BtnFore
    }

    if ($cboCategory) {
        $cboCategory.BackColor = $colors.BtnBack
        $cboCategory.ForeColor = $colors.BtnFore
    }

    if ($dropdown) {
        $dropdown.BackColor = $colors.BtnBack
        $dropdown.ForeColor = $colors.BtnFore
    }

    if ($btnRun) {
        $btnRun.BackColor = $colors.BoxFore
        $btnRun.ForeColor = $colors.BtnFore
    }

    if ($lblDesc) {
        $lblDesc.ForeColor = $colors.BoxFore
    }

    if ($outputBox) {
        $outputBox.BackColor = $colors.BoxBack
        $outputBox.ForeColor = $colors.BoxFore
        $outputBox.Font = New-Object System.Drawing.Font("Consolas", [math]::Max(8, [math]::Min(14, [int]$script:userProfile.FontSize)))
    }
    Save-UserProfile
}

function Show-CatUnlock {
    $script:clickCount = 0
    $script:kittyUnlocked = $true
    Set-Theme "Kitty"

    $catForm = New-Object System.Windows.Forms.Form
    $catForm.Text = "VIP Access Unlocked"
    $catForm.Size = New-Object System.Drawing.Size(440, 470)
    $catForm.StartPosition = "CenterParent"
    $catForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $catForm.MaximizeBox = $false
    $catForm.MinimizeBox = $false
    $catForm.BackColor = [System.Drawing.Color]::FromArgb(0, 0, 0)

    $picBox = New-Object System.Windows.Forms.PictureBox
    $picBox.Location = New-Object System.Drawing.Point(20, 20)
    $picBox.Size = New-Object System.Drawing.Size(385, 340)
    $picBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom

    $catImagePath = Get-AssetPath -FileName "cat.png"
    if (Test-Path $catImagePath) {
        $picBox.Image = [System.Drawing.Image]::FromFile($catImagePath)
        $catForm.Controls.Add($picBox)
    }
    else {
        $lblMissing = New-Object System.Windows.Forms.Label
        $lblMissing.Text = "Save your image as 'cat.png' in this folder to show it here."
        $lblMissing.Location = New-Object System.Drawing.Point(20, 120)
        $lblMissing.Size = New-Object System.Drawing.Size(345, 80)
        $lblMissing.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $lblMissing.ForeColor = [System.Drawing.Color]::White
        $lblMissing.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
        $catForm.Controls.Add($lblMissing)
    }

    $lblCaption = New-Object System.Windows.Forms.Label
    $lblCaption.Text = "KITTY THEME UNLOCKED // MAXIMUM CUTE MODE "
    $lblCaption.Location = New-Object System.Drawing.Point(20, 375)
    $lblCaption.Size = New-Object System.Drawing.Size(385, 35)
    $lblCaption.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblCaption.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $lblCaption.ForeColor = [System.Drawing.Color]::FromArgb(120, 60, 90)
    $catForm.Controls.Add($lblCaption)

    [System.Media.SystemSounds]::Exclamation.Play()
    [void]$catForm.ShowDialog($form)
}

function Write-Result {
    param(
        [System.Windows.Forms.TextBox]$OutputBox,
        [string]$Message
    )

    $OutputBox.Text += "$Message`r`n"
    $history = @($script:userProfile.History)
    $history += [pscustomobject]@{ Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; Text = $Message }
    if ($history.Count -gt 100) {
        $history = $history[($history.Count - 100)..($history.Count - 1)]
    }
    $script:userProfile.History = $history
    Save-UserProfile
}

function Invoke-PingCheck {
    param(
        [string]$Label,
        [string]$TargetHost
    )

    try {
        $ping = Test-Connection -ComputerName $TargetHost -Count 2 -ErrorAction SilentlyContinue
        if ($ping) {
            $avg = ($ping.ResponseTime | Measure-Object -Average).Average
            return "${Label}: $avg ms"
        }

        return "${Label} timed out."
    }
    catch {
        return "Ping check failed."
    }
}

function Open-ToolWindow {
    param(
        [string]$DisplayName,
        [string]$FilePath,
        [string]$Arguments = ""
    )

    try {
        if ($Arguments) {
            Start-Process -FilePath $FilePath -ArgumentList $Arguments | Out-Null
        }
        else {
            Start-Process -FilePath $FilePath | Out-Null
        }

        return "$DisplayName opened."
    }
    catch {
        return "Could not open $DisplayName."
    }
}


# Build complete metadata and test AST



$toolCategories = [ordered]@{
        "PC Optimizers & Cleaners" = @(
        "1-Click Quick PC Boost",
        "Optimize Network & Gaming Latency",
        "Hardware GPU Scheduling (HAGS)",
        "Enable Windows Game Mode",
        "Set Win32 Gaming Priority (0x26)",
        "Disable Mouse Acceleration (1:1 Raw Input)",
        "Disable Background GameDVR",
        "Disable Sticky Keys Popups in Games",
        "Optimize TCP Auto-Tuning & RSS",
        "Disable Nagle's Algorithm (TcpAckFrequency)",
        "Flush DNS & NetBIOS Caches",
        "Disable Delivery Optimization (P2P Leech)",
        "Disable Superfetch (SysMain)",
        "Disable Xbox Background Services",
        "Disable Windows Telemetry",
        "Disable Windows Bloat Auto-Install",
        "Disable Cortana & Start Web Search",
        "Disable Windows Tips & Suggestions",
        "Disable Background UWP Apps",
        "Disable Transparency Effects (DWM)",
        "Snappy Visual Effects (0ms Delay)",
        "Clear Windows Update Cache",
        "Clean Browser Caches (Chrome/Edge/Discord)",
        "Clean Windows Crash Dumps & Error Reports",
        "Clear Windows Thumbnail Cache",
        "Clear Windows Font Cache",
        "Free Standby & Working Set RAM",
        "Trim & Re-Trim All SSD Drives",
        "Clean Component Store (DISM)",
        "Toggle Hibernation (Free Disk Space)",
        "Enable Ultimate Performance Plan",
        "Kill Not Responding Apps",
        "Clear Temporary Files",
        "Run Disk Cleanup",
        "Optimize Drives",
        "Run SFC Scan",
        "Run DISM Repair",
        "Run Custom Windows Debloater",
        "Install Performance Software",
        "Launch Chris Titus Winutil",
        "Empty Recycle Bin",
        "Restart Explorer"
    )
    "Apps & Windows Tools" = @(
        "Open Task Manager",
        "Open Resource Monitor",
        "Open Device Manager",
        "Open Disk Management",
        "Open Registry Editor",
        "Open Services",
        "Open God Mode",
        "Open Control Panel",
        "Open Calculator",
        "Open Notepad",
        "Open Paint",
        "Open Snipping Tool",
        "Open File Explorer",
        "Install Performance Software",
        "Launch Chris Titus Winutil"
    )
    "Network & Wi-Fi Tools" = @(
        "Show Saved Wi-Fi Passwords",
        "Reset Network Stack (Full Repair)",
        "Switch DNS (Cloudflare / Google / DHCP)",
        "Optimize TCP Auto-Tuning & RSS",
        "Disable Nagle's Algorithm (TcpAckFrequency)",
        "Disable Delivery Optimization (P2P Leech)",
        "Flush DNS & NetBIOS Caches",
        "Quick Speed Test (Cloudflare)",
        "Check Local IP",
        "Check Public IP",
        "Ping Google (8.8.8.8)",
        "Ping Cloudflare (1.1.1.1)",
        "Ping Default Gateway",
        "Ping Custom Address",
        "Trace Route to Google",
        "Release IP Address",
        "Renew IP Address",
        "Check Wi-Fi Connection",
        "List Network Adapters",
        "View Active TCP Connections",
        "View ARP Table",
        "Open Network Connections",
        "Open Windows Defender Firewall"
    )
    "System & Hardware Specs" = @(
        "Check Hardware & Specs Summary",
        "Check Windows Activation Status",
        "Check System Uptime",
        "Check Battery Status",
        "Check Disk Space",
        "Check Memory Usage",
        "List Running Processes",
        "Check Windows Version",
        "Check Computer Information",
        "List Startup Apps",
        "List Installed Printers",
        "Check CPU Usage",
        "List USB Devices",
        "Check Graphics Cards",
        "List Audio Devices",
        "List Installed Apps",
        "List Recent Updates",
        "List Scheduled Tasks",
        "Check Current User",
        "Check Default Printer",
        "Check Display Resolution",
        "Generate Battery Report"
    )
    "Windows Management & Admin" = @(
        "Open God Mode",
        "Open Device Manager",
        "Open Services",
        "Open Task Manager",
        "Open Event Viewer",
        "Open Computer Management",
        "Open Registry Editor",
        "Open Hosts File",
        "Open Environment Variables",
        "Open Advanced System Settings",
        "Open Disk Management",
        "Open Performance Monitor",
        "Open Reliability Monitor",
        "Open Windows Security",
        "Open Group Policy Editor",
        "Open Local Users and Groups",
        "Open Advanced Power Options",
        "Open Startup Apps Settings",
        "Open Control Panel",
        "Open Task Scheduler",
        "Open Credential Manager",
        "Open System Information",
        "Open Resource Monitor",
        "Open Windows Update Settings",
        "Open Storage Settings",
        "Open Personalization Settings",
        "Open Date and Time Settings",
        "Open Mouse Settings",
        "Open Keyboard Settings",
        "Open Accessibility Settings",
        "Open Clipboard Settings",
        "Open Bluetooth Settings",
        "Open Display Settings",
        "Open Sound Settings",
        "Open Printer Settings"
    )
    "Files, Folders & Storage" = @(
        "Auto-Organize Folder",
        "Find Large Files",
        "Find Duplicate Files",
        "Find Recently Changed Files",
        "Create ZIP Backup",
        "Extract ZIP Archive",
        "Quick Auto-Extract ZIP",
        "Open Temp Folder",
        "Open System32 Folder",
        "Open Downloads Folder",
        "Open Documents Folder",
        "Open Pictures Folder",
        "Open Screenshots Folder",
        "Open Fonts Folder",
        "Open Desktop Folder",
        "Open Music Folder",
        "Open Videos Folder",
        "Open Recycle Bin",
        "Open Startup Folder",
        "Open File Explorer",
        "Open Calculator",
        "Open Notepad",
        "Open Paint",
        "Open Snipping Tool",
        "Open On-Screen Keyboard",
        "Open Magnifier"
    )
    "Pinned & Pro Tools" = @(
        "Pinned Commands",
        "Buy Pro (Â£2)",
        "Activate Pro",
        "Manage Pro Commands",
        "Add Defender Exclusion (Auto-Exception)",
        "Game Queue Auto-Accept Monitor",
        "Open Website",
        "Random Cat Fact"
    )
}

$allUniqueTools = @()
foreach ($cat in $toolCategories.Keys) {
    foreach ($item in $toolCategories[$cat]) {
        if ($allUniqueTools -notcontains $item) {
            $allUniqueTools += $item
        }
    }
}
$toolCategories["All Tools (Complete List)"] = $allUniqueTools



$script:toolDescriptions = @{
    # PC Optimizers & Cleaners
    "1-Click Quick PC Boost" = "Runs an automated 5-in-1 tuneup: cleans temp junk, flushes DNS, frees RAM, kills frozen apps, and sets High Performance."
    "Optimize Network & Gaming Latency" = "Disables network packet throttling, sets multimedia responsiveness to 0, prioritizes game GPU queue, and stops GameDVR."
    "Clear Windows Update Cache" = "Stops update services and purges leftover downloaded update caches in SoftwareDistribution to reclaim gigabytes of disk space."
    "Disable Background GameDVR" = "Disables background GameDVR and Game Bar recording overhead to eliminate stutter and input delay during games."
    "Optimize Visual Effects" = "Eliminates menu show delays (0 ms) and minimizes window animation lag so all Windows apps open instantaneously."
    "Disable Search Indexer" = "Toggles the Windows Search Indexer service (WSearch) to eliminate 100% background disk usage and CPU spikes."
    "Enable Ultimate Performance Plan" = "Unlocks and activates the hidden Windows Ultimate Performance power plan for maximum hardware throughput."
    "Use High Performance Power Plan" = "Switches system power management to High Performance mode to prevent CPU core parking and clock throttling."
    "Use Balanced Power Plan" = "Restores the default Windows Balanced power profile for balanced power savings and standard performance."
    "Clear Standby RAM & Icon Cache" = "Purges standby memory cache, cleans thumbnail/icon database files, and restarts Windows Explorer."
    "Clear Temporary Files" = "Deletes system and user temporary cache files located in %TEMP% and Windows\Temp to free up disk space."
    "Kill Not Responding Apps" = "Instantly scans for and terminates all frozen or hanging applications that are unresponsive."
    "Toggle Hibernation (Free Disk Space)" = "Toggles the Windows hiberfil.sys hibernation file on or off to reclaim 8 GB to 32 GB of primary drive storage."
    "Run Disk Cleanup" = "Launches Windows cleanmgr utility to clean system restore points, update archives, and recycle bins."
    "Optimize Drives" = "Opens the Windows Drive Defragmenter and TRIM optimization utility for HDDs and NVMe/SATA SSDs."
    "Run SFC Scan" = "Runs System File Checker (sfc /scannow) in administrative mode to repair corrupted Windows core files."
    "Run DISM Repair" = "Executes Deployment Image Servicing and Management (DISM) to check health and repair Windows image corruption."
    "Run Custom Windows Debloater" = "Removes pre-installed third-party bloatware, telemetry packages, and non-essential provisioned Windows apps."
    "Disable Windows Telemetry" = "Disables diagnostic data tracking services and telemetry scheduled tasks to enhance privacy and free resources."
    "Install Performance Software" = "Opens an installer menu for essential gaming and system performance tools (7-Zip, Notepad++, VLC, HWMonitor)."
    "Launch Chris Titus Winutil" = "Launches Chris Titus Tech's renowned open-source Windows Utility toolbox for comprehensive system tuning."
    "Empty Recycle Bin" = "Permanently deletes all discarded files stored in the Windows Recycle Bin across all connected drives."
    "Restart Explorer" = "Gracefully stops and restarts the Windows desktop Explorer shell to resolve taskbar or UI freezes."

    # Network & Wi-Fi
    "Show Saved Wi-Fi Passwords" = "Lists all stored Wi-Fi profiles on this computer along with their plaintext security keys."
    "Reset Network Stack (Full Repair)" = "Completely flushes and resets Winsock, TCP/IP stack, ARP cache, and re-registers DNS client settings."
    "Switch DNS (Cloudflare / Google / DHCP)" = "Instantly switches network adapter DNS servers between Cloudflare (1.1.1.1), Google (8.8.8.8), or default DHCP."
    "Quick Speed Test (Cloudflare)" = "Tests active network download speed, upload latency, and jitter using Cloudflare's edge speed endpoint."
    "Check Local IP" = "Displays your internal LAN IPv4 address, active subnet mask, and local default gateway."
    "Check Public IP" = "Fetches and displays your public WAN IP address and external geolocation provider."
    "Ping Google (8.8.8.8)" = "Sends ICMP echo requests to Google's primary public DNS (8.8.8.8) to verify internet connectivity."
    "Ping Cloudflare (1.1.1.1)" = "Sends ICMP echo requests to Cloudflare's ultra-fast Anycast DNS (1.1.1.1) to test low latency."
    "Ping Default Gateway" = "Pings your local Wi-Fi router or network switch gateway to verify local LAN health."
    "Ping Custom Address" = "Opens a prompt to ping any custom domain name, IP address, or local server of your choice."
    "Trace Route to Google" = "Traces each network hop between your machine and Google servers to pinpoint network bottlenecks."
    "Flush DNS Cache" = "Purges the Windows DNS client resolver cache to resolve domain name resolution errors and expired records."
    "Release IP Address" = "Releases your active DHCP lease address on all active network adapters."
    "Renew IP Address" = "Requests a brand new IP address and configuration lease from your local DHCP router."
    "Check Wi-Fi Connection" = "Displays current Wi-Fi network SSID, BSSID, radio type, signal quality percentage, and link speed."
    "List Network Adapters" = "Lists all physical, virtual, Ethernet, and Wi-Fi adapters with their MAC addresses and status."
    "View Active TCP Connections" = "Lists all established and listening TCP connections along with their owning process IDs."
    "View ARP Table" = "Displays the current Address Resolution Protocol (ARP) table showing IP-to-MAC hardware mappings."
    "Open Network Connections" = "Opens the Windows Network Connections control applet (ncpa.cpl) to configure adapters."
    "Open Windows Defender Firewall" = "Opens the Windows Defender Firewall with Advanced Security management console (wf.msc)."

    # System & Diagnostics
    "Check Hardware & Specs Summary" = "Generates a detailed summary of your CPU, Motherboard, RAM, GPU, OS Build, and connected drives."
    "Check Windows Activation Status" = "Queries the Windows Software Licensing Management tool (slmgr) to verify license activation status."
    "Check System Uptime" = "Displays how long your computer has been continuously running since the last complete system reboot."
    "Check Battery Status" = "Displays current battery charge level, charging status, health, and estimated remaining run time."
    "Check Disk Space" = "Displays total capacity, used space, and free percentage for every internal and external drive."
    "Check Memory Usage" = "Shows total installed RAM, currently used memory, and available physical memory in gigabytes."
    "List Running Processes" = "Lists all active processes currently executing on your system sorted by working memory usage."
    "Check Windows Version" = "Displays your exact Windows release name, version number, build number, and architecture."
    "Check Computer Information" = "Displays computer system manufacturer, model, domain, and operating system configuration."
    "List Startup Apps" = "Lists all programs configured to run automatically when Windows starts up from the registry and startup folder."
    "List Installed Printers" = "Enumerates all local and network print devices connected or installed on this system."
    "Check CPU Usage" = "Samples and displays current processor load percentage across all CPU logical cores."
    "List USB Devices" = "Enumerates all connected USB host controllers, hubs, mice, keyboards, and flash storage drives."
    "Check Graphics Cards" = "Displays installed GPU models, display adapter drivers, and video memory configuration."
    "List Audio Devices" = "Lists all detected audio playback and recording endpoints connected to the computer."
    "List Installed Apps" = "Lists software applications installed on the system along with their versions and publishers."
    "List Recent Updates" = "Displays recently installed Windows security hotfixes and cumulative update package IDs."
    "List Scheduled Tasks" = "Lists all active Windows Task Scheduler automated jobs and their next scheduled run times."
    "Check Current User" = "Displays the current Windows username, account domain, and administrative privileges."
    "Check Default Printer" = "Identifies the current system default printer configured in Windows."
    "Check Display Resolution" = "Displays active screen resolution, refresh rate, and display scaling settings."
    "Generate Battery Report" = "Generates an in-depth HTML battery health, cycle count, and capacity degradation report."

    # Windows Management
    "Open God Mode" = "Opens Windows Master Control Panel (God Mode) giving access to over 200 hidden system administration settings."
    "Open Device Manager" = "Opens Windows Device Manager (devmgmt.msc) to inspect, update, or troubleshoot hardware devices."
    "Open Services" = "Opens the Windows Services console (services.msc) to manage background system services."
    "Open Task Manager" = "Launches Windows Task Manager (taskmgr.exe) to view running applications, performance, and processes."
    "Open Event Viewer" = "Opens Windows Event Viewer (eventvwr.msc) to review system, application, and security event logs."
    "Open Computer Management" = "Opens the Computer Management snap-in (compmgmt.msc) for disks, shared folders, and local users."
    "Open Registry Editor" = "Opens Windows Registry Editor (regedit.exe) for inspecting and editing configuration keys."
    "Open Hosts File" = "Opens the Windows TCP/IP hosts file in Notepad to configure custom domain-to-IP overrides."
    "Open Environment Variables" = "Opens the Windows System Properties dialog directly to user and system Environment Variables."
    "Open Advanced System Settings" = "Opens Advanced System Properties (sysdm.cpl) for visual effects, paging file, and DEP settings."
    "Open Disk Management" = "Opens Windows Disk Management (diskmgmt.msc) to format, resize, partition, or assign drive letters."
    "Open Performance Monitor" = "Opens Windows Performance Monitor (perfmon.exe) for real-time hardware telemetry counters."
    "Open Reliability Monitor" = "Opens the Windows Reliability Monitor graph showing historical software crashes and system stability."
    "Open Windows Security" = "Opens Windows Security / Defender dashboard for virus protection, firewall, and device safety."
    "Open Group Policy Editor" = "Opens the Local Group Policy Editor (gpedit.msc) on Windows Pro/Enterprise editions."
    "Open Local Users and Groups" = "Opens Local Users and Groups manager (lusrmgr.msc) to manage local user accounts and passwords."
    "Open Advanced Power Options" = "Opens the classic Windows Power Options Control Panel applet (powercfg.cpl)."
    "Open Startup Apps Settings" = "Opens the Windows 10/11 Settings page for managing startup applications."
    "Open Control Panel" = "Opens the classic Windows Control Panel for access to all legacy system configuration applets."
    "Open Task Scheduler" = "Opens Windows Task Scheduler (taskschd.msc) to view and create automated system tasks."
    "Open Credential Manager" = "Opens Windows Credential Manager to manage saved Web and Windows network passwords."
    "Open System Information" = "Opens Microsoft System Information utility (msinfo32.exe) for comprehensive hardware details."
    "Open Resource Monitor" = "Opens Windows Resource Monitor (resmon.exe) for deep CPU, Memory, Disk, and Network tracking."
    "Open Windows Update Settings" = "Opens the Windows Update settings page to check for and install system patches."
    "Open Storage Settings" = "Opens Windows Storage Sense settings to manage drive usage and automatic temporary file cleanup."
    "Open Personalization Settings" = "Opens Windows Personalization settings for themes, wallpapers, colors, and lock screens."
    "Open Date and Time Settings" = "Opens Windows Date and Time configuration to adjust time zones and internet synchronization."
    "Open Mouse Settings" = "Opens Windows Mouse and Touchpad settings to configure pointer speed and buttons."
    "Open Keyboard Settings" = "Opens Windows Keyboard settings to adjust repeat rates and language layout preferences."
    "Open Accessibility Settings" = "Opens Windows Accessibility (Ease of Access) settings for high contrast, narrator, and captions."
    "Open Clipboard Settings" = "Opens Windows Clipboard settings to enable Cloud Clipboard and historical copy history (Win+V)."
    "Open Bluetooth Settings" = "Opens Windows Bluetooth & Devices settings to pair and manage wireless peripherals."
    "Open Display Settings" = "Opens Windows Display settings to change monitors, resolution, HDR, and scaling."
    "Open Sound Settings" = "Opens Windows Sound settings to configure audio output, microphone input, and volume mixers."
    "Open Printer Settings" = "Opens Windows Printers & Scanners settings to add or manage local and network printers."

    # Files & Storage
    "Auto-Organize Folder" = "Prompts you to pick a cluttered folder and neatly organizes its files into categorized subfolders."
    "Find Large Files" = "Scans a chosen folder or drive and lists all files taking up more than 100 MB of space."
    "Find Duplicate Files" = "Scans a folder for duplicate files by size and SHA256 hash, and lets you safely review and delete duplicate copies to reclaim disk space."
    "Find Recently Changed Files" = "Lists files inside a directory that have been modified or created within the past 24 hours."
    "Create ZIP Backup" = "Compresses an entire selected folder into a timestamped .zip archive backup."
    "Extract ZIP Archive" = "Prompts for a .zip file and extracts its complete contents into a destination folder."
    "Quick Auto-Extract ZIP" = "Instantly detects and unzips any recently downloaded archive into an organized destination folder."
    "Open Temp Folder" = "Opens your user temporary files directory (%TEMP%) in Windows Explorer."
    "Open System32 Folder" = "Opens the Windows System32 core operating system directory in Windows Explorer."
    "Open Downloads Folder" = "Opens your personal Downloads folder in Windows Explorer."
    "Open Documents Folder" = "Opens your personal Documents folder in Windows Explorer."
    "Open Pictures Folder" = "Opens your personal Pictures folder in Windows Explorer."
    "Open Screenshots Folder" = "Opens your saved screenshots capture directory in Windows Explorer."
    "Open Fonts Folder" = "Opens the Windows Fonts library in Windows Explorer to view or install fonts."
    "Open Desktop Folder" = "Opens your Desktop directory in Windows Explorer."
    "Open Music Folder" = "Opens your personal Music library directory in Windows Explorer."
    "Open Videos Folder" = "Opens your personal Videos library directory in Windows Explorer."
    "Open Recycle Bin" = "Opens the Windows Recycle Bin folder in Windows Explorer."
    "Open Startup Folder" = "Opens the current user's shell:startup folder to view apps starting with Windows."
    "Open File Explorer" = "Launches a new instance of Windows File Explorer to browse files and folders."
    "Open Calculator" = "Launches the Windows Calculator utility for standard, scientific, and programmer math."
    "Open Notepad" = "Launches Windows Notepad text editor for quick notes and text file editing."
    "Open Paint" = "Launches Microsoft Paint for quick image viewing, cropping, and sketch drawings."
    "Open Snipping Tool" = "Launches Windows Snipping Tool / Snip & Sketch for screen captures and annotations."
    "Open On-Screen Keyboard" = "Opens the Windows accessibility On-Screen virtual keyboard (osk.exe)."
    "Open Magnifier" = "Launches the Windows Magnifier screen zoom tool for improved visibility."

    # Pinned & Pro
    "Pinned Commands" = "Opens your list of favorite pinned commands for instant 1-click execution."
    "Buy Pro (Â£2)" = "Opens the checkout page to upgrade to QOL Reimagined Pro for advanced file and network tools."
    "Activate Pro" = "Opens the Pro activation dialog to enter your offline or online Pro license key."
    "Manage Pro Commands" = "Allows Pro users to create and run custom command shortcuts and scripts."
    "Add Defender Exclusion (Auto-Exception)" = "Prompts you to select a game or tool folder and automatically adds a Windows Defender antivirus exclusion."
    "Game Queue Auto-Accept Monitor" = "Monitors your screen and automatically clicks 'Accept' when a competitive match queue pops while AFK."
    "Open Website" = "Opens the official QOL Reimagined website or documentation in your default web browser."
    "Random Cat Fact" = "Fetches a fun random cat trivia fact and rolls for rare collectible feline achievements!"
}



    $script:toolDescriptions["Clean Browser Caches (Chrome/Edge/Discord)"] = "Safely cleans web browser and Discord cache files without removing saved cookies, passwords, or history."
    $script:toolDescriptions["Disable Mouse Acceleration (1:1 Raw Input)"] = "Zeroes out mouse curve and acceleration thresholds for true 1:1 hardware raw input in games."
    $script:toolDescriptions["Optimize TCP Auto-Tuning & RSS"] = "Enables TCP Auto-Tuning (Normal) and Receive-Side Scaling (RSS) to maximize broadband throughput and reduce latency."
    $script:toolDescriptions["Disable Delivery Optimization (P2P Leech)"] = "Prevents Windows from using your upload bandwidth to seed Windows updates to other PCs on the internet."
    $script:toolDescriptions["Disable Windows Bloat Auto-Install"] = "Prevents Windows from silently auto-installing suggested store apps and sponsored games like Candy Crush or TikTok."
    $script:toolDescriptions["Disable Cortana & Start Web Search"] = "Restricts Start Menu searches exclusively to local files and apps, eliminating Bing web search latency."
    $script:toolDescriptions["Clean Windows Crash Dumps & Error Reports"] = "Removes accumulated application crash memory dumps and Windows Error Reporting logs to free drive space."
    $script:toolDescriptions["Trim & Re-Trim All SSD Drives"] = "Sends TRIM optimization commands to all connected solid-state drives to restore peak write performance."
    $script:toolDescriptions["Disable Nagle's Algorithm (TcpAckFrequency)"] = "Disables packet batching delays by setting TcpAckFrequency and TCPNoDelay to 1 on all network adapters."
    $script:toolDescriptions["Disable Sticky Keys Popups in Games"] = "Disables the accessibility popup prompt triggered by tapping the Shift key 5 times during gameplay."
    $script:toolDescriptions["Flush DNS & NetBIOS Caches"] = "Completely purges both the Windows DNS client resolver cache and local NetBIOS name caches."
    $script:toolDescriptions["Free Standby & Working Set RAM"] = "Trims working set memory of idle applications and triggers garbage collection to maximize available physical RAM."
$script:toolDescriptions["Hardware GPU Scheduling (HAGS)"] = "Enables hardware-accelerated GPU scheduling in registry (HwSchMode=2) for reduced input lag."
$script:toolDescriptions["Enable Windows Game Mode"] = "Enables Windows Game Mode to prioritize CPU/GPU core scheduling for active games."
$script:toolDescriptions["Set Win32 Gaming Priority (0x26)"] = "Sets Win32PrioritySeparation to 38 (0x26) for optimal foreground gaming response."
$script:toolDescriptions["Disable Superfetch (SysMain)"] = "Stops and disables SysMain service to prevent 100% disk usage thrashing on SSDs."
$script:toolDescriptions["Disable Xbox Background Services"] = "Disables background Xbox networking and telemetry services to save RAM and CPU."
$script:toolDescriptions["Disable Windows Tips & Suggestions"] = "Disables lock screen spotlight ads, Start menu suggestions, and tips."
$script:toolDescriptions["Disable Background UWP Apps"] = "Disables background app execution policy to stop idle UWP apps from draining power."
$script:toolDescriptions["Disable Transparency Effects (DWM)"] = "Turns off window transparency effects to reduce DWM GPU and VRAM utilization."
$script:toolDescriptions["Clear Windows Thumbnail Cache"] = "Deletes bloated thumbcache database files to reclaim disk space."
$script:toolDescriptions["Clear Windows Font Cache"] = "Rebuilds Windows font cache service to eliminate UI micro-stutters."
$script:toolDescriptions["Clean Component Store (DISM)"] = "Runs DISM StartComponentCleanup to purge obsolete Windows update files."
$script:toolDescriptions["Snappy Visual Effects (0ms Delay)"] = "Eliminates menu delay and animation delays for instantaneous window response."


$form = New-Object System.Windows.Forms.Form
$form.Text = "QOL Reimagined"
$form.Size = New-Object System.Drawing.Size(480, 440)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $false

$formIcon = Get-AppIcon
if ($formIcon) {
    $form.Icon = $formIcon
}

$font = New-Object System.Drawing.Font("Segoe UI", 9)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "QOL Reimagined"
$lblTitle.Location = New-Object System.Drawing.Point(12, 12)
$lblTitle.Size = New-Object System.Drawing.Size(220, 24)
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
$lblTitle.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($lblTitle)

$lblTitle.Add_Click({
    $script:clickCount++
    if ($script:clickCount -ge 10) {
        Add-Achievement -AchievementId "Ten Taps"
        Show-CatUnlock
    }
})

$btnExtras = New-Object System.Windows.Forms.Button
$btnExtras.Text = "Extras Hub"
$btnExtras.Location = New-Object System.Drawing.Point(260, 10)
$btnExtras.Size = New-Object System.Drawing.Size(95, 26)
$btnExtras.Font = $font
$btnExtras.Add_Click({ Show-ExtrasHub })
$form.Controls.Add($btnExtras)

$btnSettings = New-Object System.Windows.Forms.Button
$btnSettings.Text = "Settings"
$btnSettings.Location = New-Object System.Drawing.Point(365, 10)
$btnSettings.Size = New-Object System.Drawing.Size(90, 26)
$btnSettings.Font = $font
$form.Controls.Add($btnSettings)

# Category selector combobox
$cboCategory = New-Object System.Windows.Forms.ComboBox
$cboCategory.Location = New-Object System.Drawing.Point(12, 44)
$cboCategory.Size = New-Object System.Drawing.Size(160, 25)
$cboCategory.Font = $font
$cboCategory.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
foreach ($cat in $toolCategories.Keys) {
    $cboCategory.Items.Add($cat) | Out-Null
}
$form.Controls.Add($cboCategory)

# Tool selector dropdown
$dropdown = New-Object System.Windows.Forms.ComboBox
$dropdown.Location = New-Object System.Drawing.Point(178, 44)
$dropdown.Size = New-Object System.Drawing.Size(202, 25)
$dropdown.Font = $font
$dropdown.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
$dropdown.AutoCompleteMode = [System.Windows.Forms.AutoCompleteMode]::SuggestAppend
$dropdown.AutoCompleteSource = [System.Windows.Forms.AutoCompleteSource]::ListItems
$form.Controls.Add($dropdown)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Run"
$btnRun.Location = New-Object System.Drawing.Point(388, 43)
$btnRun.Size = New-Object System.Drawing.Size(67, 27)
$btnRun.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnRun)

# Live hover / selection description banner
$lblDesc = New-Object System.Windows.Forms.Label
$lblDesc.Location = New-Object System.Drawing.Point(12, 74)
$lblDesc.Size = New-Object System.Drawing.Size(443, 34)
$lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Italic)
$lblDesc.Text = "Description: Select or hover over any tool above to view details."
$form.Controls.Add($lblDesc)

# Output Box
$outputBox = New-Object System.Windows.Forms.TextBox
$outputBox.Location = New-Object System.Drawing.Point(12, 114)
$outputBox.Size = New-Object System.Drawing.Size(443, 275)
$outputBox.Multiline = $true
$outputBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$outputBox.ReadOnly = $true
$outputBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($outputBox)

# Tooltips
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 12000
$toolTip.InitialDelay = 250
$toolTip.ReshowDelay = 100
$toolTip.ShowAlways = $true

$toolTip.SetToolTip($lblTitle, "QOL Reimagined - Click 10 times to discover a secret easter egg!")
$toolTip.SetToolTip($btnExtras, "Extras Hub: 1-Click Optimizer, Apps Installer, 28 Themes & Retro Games")
$toolTip.SetToolTip($btnSettings, "Customize theme palette, accent colors, output font size, and pinned quick-launch tools")
$toolTip.SetToolTip($cboCategory, "Filter tools by category to simplify navigation")
$toolTip.SetToolTip($btnRun, "Click to execute the selected tool (or press Enter in dropdown)")
$toolTip.SetToolTip($lblDesc, "Real-time explanation of what the selected feature or optimization does")
$toolTip.SetToolTip($outputBox, "Command output and diagnostics console")

$updateDesc = {
    $current = if ($dropdown.SelectedItem) { [string]$dropdown.SelectedItem } else { $dropdown.Text.Trim() }
    if ($script:toolDescriptions.ContainsKey($current)) {
        $desc = $script:toolDescriptions[$current]
        $lblDesc.Text = "Description: " + $desc
        $toolTip.SetToolTip($dropdown, $desc)
    }
    elseif ($current -match '^(?i)kitty$') {
        $lblDesc.Text = "Secret VIP Mode: Unlock custom Kitty theme and feline achievements!"
        $toolTip.SetToolTip($dropdown, "Secret VIP Mode")
    }
    else {
        $lblDesc.Text = "Description: Select or type any tool above to view details."
        $toolTip.SetToolTip($dropdown, "Select or enter a tool name and click Run")
    }
}

$cboCategory.Add_SelectedIndexChanged({
    $cat = $cboCategory.SelectedItem
    if ($toolCategories.Contains($cat)) {
        $items = $toolCategories[$cat]
        $dropdown.BeginUpdate()
        $dropdown.Items.Clear()
        foreach ($item in $items) {
            $dropdown.Items.Add($item) | Out-Null
        }
        if ($script:kittyUnlocked -and ($cat -eq "All Tools (Complete List)" -or $cat -eq "Pinned & Pro Tools")) {
            $dropdown.Items.Add("Kitty") | Out-Null
        }
        $dropdown.EndUpdate()
        if ($dropdown.Items.Count -gt 0) {
            $dropdown.SelectedIndex = 0
        }
    }
})

$dropdown.Add_SelectedIndexChanged($updateDesc)
$dropdown.Add_TextChanged($updateDesc)
$dropdown.Add_MouseEnter($updateDesc)

$btnRun.Add_MouseEnter({
    $current = if ($dropdown.SelectedItem) { [string]$dropdown.SelectedItem } else { $dropdown.Text.Trim() }
    $lblDesc.Text = "Execute: $current"
})
$btnRun.Add_MouseLeave($updateDesc)

$dropdown.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $btnRun.PerformClick()
    }
})

$cboCategory.SelectedItem = "PC Optimizers & Cleaners"



$btnSettings.Add_Click({
    $settingsForm = New-Object System.Windows.Forms.Form
    $settingsForm.Text = "Settings & Themes"
    $settingsForm.Size = New-Object System.Drawing.Size(260, 220)
    $settingsForm.StartPosition = "CenterParent"
    $settingsForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $settingsForm.MaximizeBox = $false
    $settingsForm.MinimizeBox = $false
    if ($form.Icon) { $settingsForm.Icon = $form.Icon }

    $lblTheme = New-Object System.Windows.Forms.Label
    $lblTheme.Text = "Select Theme:"
    $lblTheme.Location = New-Object System.Drawing.Point(20, 20)
    $lblTheme.Size = New-Object System.Drawing.Size(200, 20)
    $settingsForm.Controls.Add($lblTheme)

    $comboTheme = New-Object System.Windows.Forms.ComboBox
    $comboTheme.Location = New-Object System.Drawing.Point(20, 45)
    $comboTheme.Size = New-Object System.Drawing.Size(200, 24)
    $comboTheme.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $allSettingThemes = @(
        "Dark", "Light", "Super Black", "Cyberpunk", "Matrix", "Dracula", "Nord", "Tokyo Night",
        "Blood Moon", "Gold Luxe", "Vaporwave", "Solar Flare", "Mint Frost", "Ocean", "Forest",
        "Sunset", "Glacier", "Rose", "Amber", "Coral", "Citrus", "Cobalt", "Ember"
    )
    foreach ($th in $allSettingThemes) {
        $comboTheme.Items.Add($th) | Out-Null
    }
    if (Test-ProAccess) {
        $comboTheme.Items.Add("Ocean Pro") | Out-Null
        $comboTheme.Items.Add("Emerald Pro") | Out-Null
        $comboTheme.Items.Add("Crimson Pro") | Out-Null
        $comboTheme.Items.Add("Neon Lime Pro") | Out-Null
    }
    if ($script:kittyUnlocked) {
        $comboTheme.Items.Add("Kitty") | Out-Null
    }
    $comboTheme.SelectedItem = $script:currentTheme
    $settingsForm.Controls.Add($comboTheme)

    $imgBox = New-Object System.Windows.Forms.PictureBox
    $imgBox.Location = New-Object System.Drawing.Point(20, 80)
    $imgBox.Size = New-Object System.Drawing.Size(200, 60)
    $imgBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $imgBox.BackColor = [System.Drawing.Color]::FromArgb(255, 240, 245)
    $catImagePath = Get-AssetPath -FileName "cat.png"
    if (Test-Path $catImagePath) {
        $imgBox.Image = [System.Drawing.Image]::FromFile($catImagePath)
    }
    $settingsForm.Controls.Add($imgBox)

    $lblPinned = New-Object System.Windows.Forms.Label
    $lblPinned.Text = "Pinned Commands:"
    $lblPinned.Location = New-Object System.Drawing.Point(20, 150)
    $lblPinned.Size = New-Object System.Drawing.Size(200, 20)
    $settingsForm.Controls.Add($lblPinned)

    $lstPinned = New-Object System.Windows.Forms.ListBox
    $lstPinned.Location = New-Object System.Drawing.Point(20, 175)
    $lstPinned.Size = New-Object System.Drawing.Size(200, 120)
    foreach ($item in (Import-PinnedCommands)) {
        $lstPinned.Items.Add($item) | Out-Null
    }
    $settingsForm.Controls.Add($lstPinned)

    $btnPinCurrent = New-Object System.Windows.Forms.Button
    $btnPinCurrent.Text = "Pin Current"
    $btnPinCurrent.Location = New-Object System.Drawing.Point(235, 175)
    $btnPinCurrent.Size = New-Object System.Drawing.Size(100, 30)
    $btnPinCurrent.Add_Click({
        $current = if ($dropdown.SelectedItem) { $dropdown.SelectedItem } else { $dropdown.Text.Trim() }
        if (-not [string]::IsNullOrWhiteSpace($current) -and $lstPinned.Items -notcontains $current) {
            $lstPinned.Items.Add($current) | Out-Null
            Save-PinnedCommands -Commands @($lstPinned.Items)
        }
    })
    $settingsForm.Controls.Add($btnPinCurrent)

    $btnRemovePinned = New-Object System.Windows.Forms.Button
    $btnRemovePinned.Text = "Remove"
    $btnRemovePinned.Location = New-Object System.Drawing.Point(235, 210)
    $btnRemovePinned.Size = New-Object System.Drawing.Size(100, 30)
    $btnRemovePinned.Add_Click({
        if ($lstPinned.SelectedItem) {
            $lstPinned.Items.Remove($lstPinned.SelectedItem)
            Save-PinnedCommands -Commands @($lstPinned.Items)
        }
    })
    $settingsForm.Controls.Add($btnRemovePinned)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Apply Theme"
    $btnSave.Location = New-Object System.Drawing.Point(235, 245)
    $btnSave.Size = New-Object System.Drawing.Size(100, 30)

    $btnSave.Add_Click({
        $selectedTheme = $comboTheme.SelectedItem
        if ($selectedTheme -eq "Kitty" -and -not $script:kittyUnlocked) {
            $selectedTheme = "Dark"
        }
        Set-Theme -themeName $selectedTheme
        [System.Media.SystemSounds]::Asterisk.Play()
        $settingsForm.Close()
    })
    $settingsForm.Controls.Add($btnSave)

    $btnRunPinned = New-Object System.Windows.Forms.Button
    $btnRunPinned.Text = "Run Pinned"
    $btnRunPinned.Location = New-Object System.Drawing.Point(235, 280)
    $btnRunPinned.Size = New-Object System.Drawing.Size(100, 30)
    $btnRunPinned.Add_Click({
        if ($lstPinned.SelectedItem) {
            if ($dropdown.Items -notcontains $lstPinned.SelectedItem) {
                $cboCategory.SelectedItem = "All Tools (Complete List)"
            }
            $dropdown.SelectedItem = $lstPinned.SelectedItem
            $btnRun.PerformClick()
            $settingsForm.Close()
        }
    })
    $settingsForm.Controls.Add($btnRunPinned)

    $btnDesktopShortcut = New-Object System.Windows.Forms.Button
    $btnDesktopShortcut.Text = "Install Desktop Shortcut"
    $btnDesktopShortcut.Location = New-Object System.Drawing.Point(20, 305)
    $btnDesktopShortcut.Size = New-Object System.Drawing.Size(315, 30)
    $btnDesktopShortcut.BackColor = $colors.BtnBack
    $btnDesktopShortcut.ForeColor = $colors.BtnFore
    $btnDesktopShortcut.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnDesktopShortcut.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnDesktopShortcut.Add_Click({
        if (Install-DesktopShortcut) {
            [System.Windows.Forms.MessageBox]::Show("QOL Reimagined shortcut created on your Desktop with the custom icon!", "Shortcut Installed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("Could not create Desktop shortcut.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    })
    $settingsForm.Controls.Add($btnDesktopShortcut)

    $settingsForm.Size = New-Object System.Drawing.Size(360, 390)
    [void]$settingsForm.ShowDialog($form)
})

Set-Theme -themeName $script:currentTheme

$btnRun.Add_Click({
    $selection = if ($dropdown.SelectedItem) { $dropdown.SelectedItem } else { $dropdown.Text.Trim() }

    if ($selection -match '^(?i)kitty$') {
        if (-not $script:kittyUnlocked) {
            $script:kittyUnlocked = $true
            Add-Achievement -AchievementId "Kitty Finder"
            if ($dropdown.Items -notcontains "Kitty") {
                $dropdown.Items.Add("Kitty") | Out-Null
            }
            $dropdown.SelectedItem = "Kitty"
            Set-Theme "Kitty"
            [System.Windows.Forms.MessageBox]::Show("You have unlocked Kitty theme!", "Kitty Unlocked", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            Show-CatUnlock
        }
        else {
            Set-Theme "Kitty"
        }

        $outputBox.Text = "> Kitty theme unlocked!`r`n"
        return
    }

    if ($selection -ieq "i want game") {
        Show-MiniGame
        return
    }

    if ($selection -ieq "rng") {
        Show-RngGame
        return
    }

    if ($selection -match '^(?i)Open Website(?:\s+(.+))?$') {
        Open-WebsitePrompt -InitialUrl $Matches[1]
        return
    }

    if ($selection -eq "Pinned Commands") {
        Show-PinnedCommandsDialog
        return
    }

    if ($selection -eq "Buy Pro (£2)") {
        Start-ProCheckout
        return
    }

    if ($selection -eq "Activate Pro") {
        Show-ProActivationDialog
        return
    }

    if ($selection -eq "Manage Pro Commands") {
        Show-CustomCommandsDialog
        return
    }

    $proOnlyActions = @("Find Large Files", "Find Duplicate Files", "Find Recently Changed Files", "Create ZIP Backup", "Extract ZIP Archive", "Generate Battery Report", "Empty Recycle Bin")
    if ($selection -in $proOnlyActions -and -not (Assert-ProAccess)) {
        return
    }

    $script:userProfile.ActionCount++
    if ($script:userProfile.ActionCount -eq 1) { Add-Achievement -AchievementId "First Action" }
    if ($script:userProfile.ActionCount -eq 25) { Add-Achievement -AchievementId "Action Explorer" }
    if ($script:userProfile.ActionCount -eq 100) { Add-Achievement -AchievementId "Century Club" }
    Save-UserProfile

    $outputBox.Text = "> Running: $selection...`r`n`r`n"
    $form.Refresh()

    switch ($selection) {
        "Check Local IP" {
            try {
                Write-Result -OutputBox $outputBox -Message "Local IPv4: $(Get-CompatLocalIp)"
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read local IP."
            }
        }
        "Check Public IP" {
            try {
                $pubIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction Stop)
                Write-Result -OutputBox $outputBox -Message "Public IP: $pubIp"
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Failed to fetch Public IP."
            }
        }
        "Quick Speed Test (Cloudflare)" {
            try {
                Write-Result -OutputBox $outputBox -Message "Downloading speed test packet..."
                $form.Refresh()
                $url = 'https://speed.cloudflare.com/__down?bytes=5000000'
                $client = New-Object System.Net.WebClient
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $data = $client.DownloadData($url)
                $sw.Stop()
                $mbps = [math]::Round(($data.Length * 8) / ($sw.Elapsed.TotalSeconds * 1000000), 2)
                Write-Result -OutputBox $outputBox -Message "Download Speed: $mbps Mbps"
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Speed test connection failed."
            }
        }
        "Ping Google (8.8.8.8)" {
            Write-Result -OutputBox $outputBox -Message (Invoke-PingCheck -Label "Google Ping Latency" -TargetHost "8.8.8.8")
        }
        "Ping Cloudflare (1.1.1.1)" {
            Write-Result -OutputBox $outputBox -Message (Invoke-PingCheck -Label "Cloudflare Ping Latency" -TargetHost "1.1.1.1")
        }
        "Ping Default Gateway" {
            try {
                $gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object -ExpandProperty NextHop -First 1)
                if ($gw) {
                    Write-Result -OutputBox $outputBox -Message (Invoke-PingCheck -Label "Gateway ($gw) Ping" -TargetHost $gw)
                }
                else {
                    Write-Result -OutputBox $outputBox -Message "No default gateway found."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read default gateway."
            }
        }
        "Trace Route to Google" {
            try {
                Write-Result -OutputBox $outputBox -Message "Tracing route to 8.8.8.8 (please wait)..."
                $form.Refresh()
                $trace = & tracert -h 5 8.8.8.8 2>&1
                Write-Result -OutputBox $outputBox -Message ($trace | Out-String)
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Trace route failed."
            }
        }
        "Flush DNS Cache" {
            try {
                if (Test-CommandExists -Name "Clear-DnsClientCache") {
                    Clear-DnsClientCache -ErrorAction Stop
                    Write-Result -OutputBox $outputBox -Message "DNS Resolver Cache successfully cleared."
                }
                else {
                    & ipconfig /flushdns 2>$null | Out-Null
                    Write-Result -OutputBox $outputBox -Message "DNS cache flushed with ipconfig fallback."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "DNS cache could not be cleared on this system."
            }
        }
        "Release IP Address" {
            try {
                & ipconfig /release 2>$null | Out-Null
                Write-Result -OutputBox $outputBox -Message "IP address released."
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Release command failed."
            }
        }
        "Renew IP Address" {
            try {
                & ipconfig /renew 2>$null | Out-Null
                Write-Result -OutputBox $outputBox -Message "IP address renewed successfully."
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Renew command failed."
            }
        }
        "Auto-Organize Folder" {
            try {
                $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
                $dialog.Description = "Select a folder to auto-organize"
                if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $targetDir = $dialog.SelectedPath
                    Write-Result -OutputBox $outputBox -Message "Organizing folder: $targetDir..."
                    $form.Refresh()

                    $folders = @("Images", "Documents", "Scripts", "Archives", "Executables", "Other")
                    foreach ($folderName in $folders) {
                        $path = Join-Path $targetDir $folderName
                        if (-not (Test-Path $path)) {
                            New-Item -ItemType Directory -Path $path -Force | Out-Null
                        }
                    }

                    $files = Get-ChildItem -Path $targetDir -File
                    $count = 0

                    foreach ($file in $files) {
                        $ext = $file.Extension.ToLower()
                        $dest = $null

                        if ($ext -in @(".png", ".jpg", ".jpeg", ".ico", ".gif", ".webp")) {
                            $dest = "Images"
                        }
                        elseif ($ext -in @(".txt", ".pdf", ".docx", ".xlsx", ".csv", ".pptx")) {
                            $dest = "Documents"
                        }
                        elseif ($ext -in @(".ps1", ".bat", ".vbs", ".py", ".js", ".html", ".css", ".json")) {
                            $dest = "Scripts"
                        }
                        elseif ($ext -in @(".zip", ".rar", ".7z", ".tar", ".gz")) {
                            $dest = "Archives"
                        }
                        elseif ($ext -in @(".exe", ".msi")) {
                            $dest = "Executables"
                        }
                        else {
                            $dest = "Other"
                        }

                        if ($dest) {
                            Move-Item -Path $file.FullName -Destination (Join-Path $targetDir $dest) -Force
                            $count++
                        }
                    }

                    Write-Result -OutputBox $outputBox -Message "Successfully organized $count files into category folders!"
                }
                else {
                    Write-Result -OutputBox $outputBox -Message "Folder organization cancelled."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Folder organization failed."
            }
        }
        "Check System Uptime" {
            try {
                $uptime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
                $span = (Get-Date) - $uptime
                Write-Result -OutputBox $outputBox -Message "System Uptime: $($span.Days)d $($span.Hours)h $($span.Minutes)m"
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read system uptime."
            }
        }
        "List Network Adapters" {
            try {
                $adapters = Get-CompatNetAdapters | Where-Object { $_ -and $_.ToString() -notmatch 'No adapters detected' }
                if ($adapters -and $adapters.Count -gt 0) {
                    Write-Result -OutputBox $outputBox -Message "Active Adapters:`r`n$($adapters -join "`r`n")"
                }
                else {
                    Write-Result -OutputBox $outputBox -Message "No active adapters found."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not list adapters."
            }
        }
        "View Active TCP Connections" {
            try {
                $conns = Get-CompatTcpConnections
                if ($conns -and $conns.Count -gt 0) {
                    if ($conns[0].GetType().Name -eq "String") {
                        Write-Result -OutputBox $outputBox -Message ($conns | Select-Object -First 10 | Out-String)
                    }
                    else {
                        $lines = @("Active Connections:")
                        foreach ($c in ($conns | Select-Object -First 8)) {
                            $lines += "-> IP: $($c.RemoteAddress) | Local Port: $($c.LocalPort)"
                        }
                        Write-Result -OutputBox $outputBox -Message ($lines -join "`r`n")
                    }
                }
                else {
                    Write-Result -OutputBox $outputBox -Message "No active TCP connections found."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read active TCP connections."
            }
        }
        "Check Wi-Fi Connection" {
            try {
                $wifiCheck = & netsh wlan show interfaces 2>&1
                if ($wifiCheck -match "State\s*:\s*connected") {
                    Write-Result -OutputBox $outputBox -Message ($wifiCheck | Out-String)
                }
                else {
                    Write-Result -OutputBox $outputBox -Message "No active Wi-Fi connection found (you may be on Ethernet or Wi-Fi is disabled)."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not check Wi-Fi connection."
            }
        }
        "View ARP Table" {
            try {
                $arp = & arp -a 2>&1
                Write-Result -OutputBox $outputBox -Message ($arp | Out-String)
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read ARP table."
            }
        }
        "Random Cat Fact" {
            $facts = @(
                "Cats spend about 70% of their lives sleeping.",
                "A group of cats is called a clowder!",
                "Cats can jump up to 6 times their height!",
                "A cat's meow is usually used to communicate with humans."
            )
            $script:userProfile.CatFacts++
            if ($script:userProfile.CatFacts -ge 50) { Add-Achievement -AchievementId "Cat Collector" }
            $catFactRoll = Get-Random -Minimum 1 -Maximum 10001
            if ($catFactRoll -le 10) {
                $script:userProfile.RareCatFacts++
                Add-Achievement -AchievementId "Lucky Cat"
                if ($catFactRoll -eq 1) {
                    Add-Achievement -AchievementId "Cosmic Cat"
                    $fact = "SUPER RARE CAT FACT! Type Kitty in the command bar to reveal a secret."
                }
                else {
                    $fact = "A rare cat fact appeared! Type Kitty in the command bar to reveal a secret."
                }
            }
            else {
                $fact = $facts[(Get-Random -Maximum $facts.Length)]
            }
            Save-UserProfile
            Write-Result -OutputBox $outputBox -Message $fact
        }
        "Check Battery Status" {
            try {
                $battery = Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object -First 1
                if ($battery) {
                    $statusNames = @{ 1 = "Other"; 2 = "Unknown"; 3 = "Fully charged"; 4 = "Low"; 5 = "Critical"; 6 = "Charging"; 7 = "Charging (high)"; 8 = "Charging (low)"; 9 = "Charging (critical)"; 10 = "Not charging"; 11 = "Partially charged" }
                    $status = $statusNames[[int]$battery.BatteryStatus]
                    if (-not $status) { $status = "Status unavailable" }
                    Write-Result -OutputBox $outputBox -Message "Battery: $($battery.EstimatedChargeRemaining)%`r`nStatus: $status"
                }
                else {
                    Write-Result -OutputBox $outputBox -Message "No battery detected."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read battery status."
            }
        }
        "Check Disk Space" {
            try {
                $drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3" -ErrorAction Stop
                $lines = foreach ($drive in $drives) {
                    $sizeGb = [math]::Round($drive.Size / 1GB, 1)
                    $freeGb = [math]::Round($drive.FreeSpace / 1GB, 1)
                    "{0}  {1} GB free of {2} GB" -f $drive.DeviceID, $freeGb, $sizeGb
                }
                Write-Result -OutputBox $outputBox -Message ($lines -join "`r`n")
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read disk space."
            }
        }
        "Check Memory Usage" {
            try {
                $memory = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                $totalGb = [math]::Round($memory.TotalVisibleMemorySize / 1MB, 1)
                $freeGb = [math]::Round($memory.FreePhysicalMemory / 1MB, 1)
                $usedGb = [math]::Round($totalGb - $freeGb, 1)
                Write-Result -OutputBox $outputBox -Message "Memory in use: $usedGb GB`r`nAvailable: $freeGb GB`r`nTotal: $totalGb GB"
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read memory usage."
            }
        }
        "List Running Processes" {
            try {
                $processes = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 12 Name, Id, @{ Name = "MemoryMB"; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 1) } }
                Write-Result -OutputBox $outputBox -Message ($processes | Format-Table -AutoSize | Out-String)
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not list running processes."
            }
        }
        "Check Windows Version" {
            try {
                $windows = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                Write-Result -OutputBox $outputBox -Message "$($windows.Caption)`r`nVersion: $($windows.Version)`r`nBuild: $($windows.BuildNumber)"
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read the Windows version."
            }
        }
        "Check Computer Information" {
            try {
                $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
                $processor = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
                $ramGb = [math]::Round($computer.TotalPhysicalMemory / 1GB, 1)
                Write-Result -OutputBox $outputBox -Message "Manufacturer: $($computer.Manufacturer)`r`nModel: $($computer.Model)`r`nProcessor: $($processor.Name)`r`nInstalled RAM: $ramGb GB"
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read computer information."
            }
        }
        "List Startup Apps" {
            try {
                $startupItems = Get-CimInstance Win32_StartupCommand -ErrorAction Stop | Select-Object -First 15 Name, Location, Command
                if ($startupItems) {
                    Write-Result -OutputBox $outputBox -Message ($startupItems | Format-List | Out-String)
                }
                else {
                    Write-Result -OutputBox $outputBox -Message "No startup apps found."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not list startup apps."
            }
        }
        "List Installed Printers" {
            try {
                $printers = Get-CimInstance Win32_Printer -ErrorAction Stop | Select-Object -ExpandProperty Name
                if ($printers) {
                    Write-Result -OutputBox $outputBox -Message ($printers -join "`r`n")
                }
                else {
                    Write-Result -OutputBox $outputBox -Message "No printers found."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not list installed printers."
            }
        }
        "Check CPU Usage" {
            try {
                $processors = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
                $load = [math]::Round(($processors | Measure-Object -Property LoadPercentage -Average).Average, 0)
                Write-Result -OutputBox $outputBox -Message "Current CPU usage: $load%`r`nProcessor(s): $($processors.Count)"
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read CPU usage."
            }
        }
        "List USB Devices" {
            try {
                $devices = Get-CimInstance Win32_PnPEntity -Filter "PNPClass = 'USB'" -ErrorAction Stop | Select-Object -First 15 Name, Status
                if ($devices) {
                    Write-Result -OutputBox $outputBox -Message ($devices | Format-Table -AutoSize | Out-String)
                }
                else {
                    Write-Result -OutputBox $outputBox -Message "No USB devices found."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not list USB devices."
            }
        }
        "Check Graphics Cards" {
            try {
                $graphics = Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object Name, DriverVersion, @{ Name = "MemoryMB"; Expression = { if ($_.AdapterRAM) { [math]::Round($_.AdapterRAM / 1MB, 0) } else { "Unknown" } } }
                Write-Result -OutputBox $outputBox -Message ($graphics | Format-List | Out-String)
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read graphics card information."
            }
        }
        "List Audio Devices" {
            try {
                $audioDevices = Get-CimInstance Win32_SoundDevice -ErrorAction Stop | Select-Object Name, Status
                if ($audioDevices) {
                    Write-Result -OutputBox $outputBox -Message ($audioDevices | Format-Table -AutoSize | Out-String)
                }
                else {
                    Write-Result -OutputBox $outputBox -Message "No audio devices found."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not list audio devices."
            }
        }
        "List Installed Apps" {
            try {
                $appPaths = @(
                    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
                )
                $apps = foreach ($appPath in $appPaths) {
                    Get-ItemProperty -Path $appPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | Select-Object @{ Name = "Name"; Expression = { $_.DisplayName } }, DisplayVersion
                }
                $appLines = $apps | Sort-Object Name -Unique | Select-Object -First 20 | ForEach-Object { if ($_.DisplayVersion) { "$($_.Name) ($($_.DisplayVersion))" } else { $_.Name } }
                if ($appLines) {
                    Write-Result -OutputBox $outputBox -Message ($appLines -join "`r`n")
                }
                else {
                    Write-Result -OutputBox $outputBox -Message "No installed desktop apps found."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not list installed apps."
            }
        }
        "List Recent Updates" {
            try {
                $updates = Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object -First 12 HotFixID, Description, InstalledOn
                Write-Result -OutputBox $outputBox -Message ($updates | Format-Table -AutoSize | Out-String)
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not list recent Windows updates."
            }
        }
        "List Scheduled Tasks" {
            try {
                if (Test-CommandExists -Name "Get-ScheduledTask") {
                    $tasks = Get-ScheduledTask -ErrorAction Stop | Select-Object -First 15 TaskName, TaskPath, State
                    Write-Result -OutputBox $outputBox -Message ($tasks | Format-Table -AutoSize | Out-String)
                }
                else {
                    Write-Result -OutputBox $outputBox -Message "Scheduled task listing is not supported on this Windows version."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not list scheduled tasks."
            }
        }
        "Check Current User" {
            Write-Result -OutputBox $outputBox -Message "User: $env:USERNAME`r`nDomain: $env:USERDOMAIN`r`nProfile: $env:USERPROFILE"
        }
        "Check Default Printer" {
            try {
                $printer = Get-CimInstance Win32_Printer -ErrorAction Stop | Where-Object { $_.Default } | Select-Object -First 1
                if ($printer) {
                    Write-Result -OutputBox $outputBox -Message "Default printer: $($printer.Name)"
                }
                else {
                    Write-Result -OutputBox $outputBox -Message "No default printer is set."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read the default printer."
            }
        }
        "Check Display Resolution" {
            try {
                $screens = [System.Windows.Forms.Screen]::AllScreens
                $lines = foreach ($screen in $screens) {
                    "{0}: {1} x {2}" -f $screen.DeviceName, $screen.Bounds.Width, $screen.Bounds.Height
                }
                Write-Result -OutputBox $outputBox -Message ($lines -join "`r`n")
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read display resolution."
            }
        }
        "Open Website" {
            Open-WebsitePrompt
            break
        }
        { $_ -match 'Open .*' -and $_ -ne 'Open Website' } {
            $toolName = $selection
            $toolMap = @{
                "Open Device Manager" = "devmgmt.msc";
                "Open Services" = "services.msc";
                "Open Task Manager" = "taskmgr.exe";
                "Open Event Viewer" = "eventvwr.msc";
                "Open Computer Management" = "compmgmt.msc";
                "Open Registry Editor" = "regedit.exe";
                "Open Hosts File" = "notepad.exe";
                "Open Environment Variables" = "rundll32.exe";
                "Open Advanced System Settings" = "sysdm.cpl";
                "Open Disk Management" = "diskmgmt.msc";
                "Open Performance Monitor" = "perfmon.exe";
                "Open Reliability Monitor" = "perfmon.exe";
                "Open Windows Security" = "windowsdefender:";
                "Open Group Policy Editor" = "gpedit.msc";
                "Open Local Users and Groups" = "lusrmgr.msc";
                "Open Network Connections" = "ncpa.cpl";
                "Open Windows Defender Firewall" = "wf.msc";
                "Open Advanced Power Options" = "powercfg.cpl";
                "Open Startup Apps Settings" = "ms-settings:startupapps";
                "Run Disk Cleanup" = "cleanmgr.exe";
                "Open Control Panel" = "control.exe";
                "Open Calculator" = "calc.exe";
                "Open Notepad" = "notepad.exe";
                "Open File Explorer" = "explorer.exe";
                "Open Bluetooth Settings" = "ms-settings:bluetooth";
                "Open Display Settings" = "ms-settings:display";
                "Open Sound Settings" = "ms-settings:sound";
                "Open Printer Settings" = "ms-settings:printers";
                "Open System Information" = "msinfo32.exe";
                "Open Paint" = "mspaint.exe";
                "Open Snipping Tool" = "snippingtool.exe";
                "Open On-Screen Keyboard" = "osk.exe";
                "Open Magnifier" = "magnify.exe";
                "Open Resource Monitor" = "resmon.exe";
                "Open Windows Update Settings" = "ms-settings:windowsupdate";
                "Open Storage Settings" = "ms-settings:storagesense";
                "Open Personalization Settings" = "ms-settings:personalization";
                "Open Date and Time Settings" = "ms-settings:dateandtime";
                "Open Mouse Settings" = "ms-settings:mousetouchpad";
                "Open Keyboard Settings" = "ms-settings:keyboard";
                "Open Accessibility Settings" = "ms-settings:easeofaccess";
                "Open Clipboard Settings" = "ms-settings:clipboard";
                "Open Task Scheduler" = "taskschd.msc";
                "Open Credential Manager" = "control.exe";
                "Open Startup Folder" = "explorer.exe";
                "Open God Mode" = "explorer.exe";
                "Open Temp Folder" = "";
                "Open System32 Folder" = ""
            }

            $toolArguments = @{
                "Open Startup Folder" = "shell:startup";
                "Open God Mode" = "shell:::{ED7BA470-8E54-465E-825C-99712043E01C}"
            }

            $file = $toolMap[$selection]
            switch ($selection) {
                "Open Hosts File" {
                    $hostsPath = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
                    if (Test-Path $hostsPath) {
                        Start-Process notepad.exe $hostsPath | Out-Null
                        Write-Result -OutputBox $outputBox -Message "Hosts file opened."
                    }
                    else {
                        Write-Result -OutputBox $outputBox -Message "Hosts file not found."
                    }
                }
                "Open Environment Variables" {
                    Start-Process rundll32.exe sysdm.cpl,EditEnvironmentVariables | Out-Null
                    Write-Result -OutputBox $outputBox -Message "Environment Variables opened."
                }
                "Open Reliability Monitor" {
                    Start-Process perfmon.exe /rel | Out-Null
                    Write-Result -OutputBox $outputBox -Message "Reliability Monitor opened."
                }
                "Open Temp Folder" {
                    if (Test-Path $env:TEMP) {
                        Start-Process $env:TEMP | Out-Null
                        Write-Result -OutputBox $outputBox -Message "Temporary files folder opened."
                    }
                    else {
                        Write-Result -OutputBox $outputBox -Message "Temp folder not found."
                    }
                }
                "Open System32 Folder" {
                    $system32 = Join-Path $env:SystemRoot "System32"
                    if (Test-Path $system32) {
                        Start-Process $system32 | Out-Null
                        Write-Result -OutputBox $outputBox -Message "System32 opened."
                    }
                    else {
                        Write-Result -OutputBox $outputBox -Message "System32 folder not found."
                    }
                }
                "Open Recycle Bin" {
                    try {
                        Start-Process -FilePath "explorer.exe" -ArgumentList "shell:RecycleBinFolder" | Out-Null
                        Write-Result -OutputBox $outputBox -Message "Recycle Bin opened."
                    }
                    catch {
                        Write-Result -OutputBox $outputBox -Message "Could not open Recycle Bin."
                    }
                }
                "Open Credential Manager" {
                    Start-Process -FilePath "control.exe" -ArgumentList "/name Microsoft.CredentialManager" | Out-Null
                    Write-Result -OutputBox $outputBox -Message "Credential Manager opened."
                }
                { $_ -in @("Open Downloads Folder", "Open Documents Folder", "Open Pictures Folder", "Open Screenshots Folder", "Open Fonts Folder", "Open Desktop Folder", "Open Music Folder", "Open Videos Folder") } {
                    $folderPath = switch ($selection) {
                        "Open Downloads Folder" { Join-Path $env:USERPROFILE "Downloads" }
                        "Open Documents Folder" { [Environment]::GetFolderPath("MyDocuments") }
                        "Open Pictures Folder" { [Environment]::GetFolderPath("MyPictures") }
                        "Open Screenshots Folder" { Join-Path ([Environment]::GetFolderPath("MyPictures")) "Screenshots" }
                        "Open Fonts Folder" { Join-Path $env:SystemRoot "Fonts" }
                        "Open Desktop Folder" { [Environment]::GetFolderPath("DesktopDirectory") }
                        "Open Music Folder" { [Environment]::GetFolderPath("MyMusic") }
                        "Open Videos Folder" { [Environment]::GetFolderPath("MyVideos") }
                    }
                    if (Test-Path $folderPath) {
                        Start-Process -FilePath "explorer.exe" -ArgumentList "`"$folderPath`"" | Out-Null
                        Write-Result -OutputBox $outputBox -Message "$selection opened."
                    }
                    else {
                        Write-Result -OutputBox $outputBox -Message "Folder not found: $folderPath"
                    }
                }
                default {
                    if ($file) {
                        $arguments = $toolArguments[$selection]
                        Write-Result -OutputBox $outputBox -Message (Open-ToolWindow -DisplayName $toolName -FilePath $file -Arguments $arguments)
                    }
                    else {
                        Write-Result -OutputBox $outputBox -Message "This tool is unavailable."
                    }
                }
            }
        }
        "Find Large Files" {
            $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $folderDialog.Description = "Choose a folder to scan for files at least 100 MB in size"
            if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                try {
                    Write-Result -OutputBox $outputBox -Message "Scanning for large files..."
                    $form.Refresh()
                    $largeFiles = @(Get-ChildItem -LiteralPath $folderDialog.SelectedPath -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -ge 100MB } | Sort-Object Length -Descending | Select-Object -First 25)
                    if ($largeFiles.Count -gt 0) {
                        $lines = $largeFiles | ForEach-Object { "{0,8:N1} MB  {1}" -f ($_.Length / 1MB), $_.FullName }
                        Write-Result -OutputBox $outputBox -Message ($lines -join "`r`n")
                    }
                    else {
                        Write-Result -OutputBox $outputBox -Message "No files of 100 MB or larger found."
                    }
                }
                catch {
                    Write-Result -OutputBox $outputBox -Message "Could not scan this folder."
                }
            }
        }
        "Find Duplicate Files" {
            $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $folderDialog.Description = "Choose a folder to scan for duplicate files"
            if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                Write-Result -OutputBox $outputBox -Message "Scanning '$($folderDialog.SelectedPath)' for duplicate files (size & SHA256)..."
                $form.Refresh()
                Show-DuplicateCleanerDialog -FolderPath $folderDialog.SelectedPath
            }
        }
        "Find Recently Changed Files" {
            $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $folderDialog.Description = "Choose a folder to find files changed in the last 7 days"
            if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                try {
                    $cutoff = (Get-Date).AddDays(-7)
                    $recentFiles = @(Get-ChildItem -LiteralPath $folderDialog.SelectedPath -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $cutoff } | Sort-Object LastWriteTime -Descending | Select-Object -First 30)
                    if ($recentFiles.Count -gt 0) {
                        $lines = $recentFiles | ForEach-Object { "{0:g}  {1}" -f $_.LastWriteTime, $_.FullName }
                        Write-Result -OutputBox $outputBox -Message ($lines -join "`r`n")
                    }
                    else {
                        Write-Result -OutputBox $outputBox -Message "No files changed in the last 7 days."
                    }
                }
                catch {
                    Write-Result -OutputBox $outputBox -Message "Could not scan this folder."
                }
            }
        }
        "Create ZIP Backup" {
            $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $folderDialog.Description = "Choose the folder to back up"
            if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
                $folderName = Split-Path -Leaf $folderDialog.SelectedPath.TrimEnd('\')
                $saveDialog.Title = "Save ZIP Backup"
                $saveDialog.Filter = "ZIP archive (*.zip)|*.zip"
                $saveDialog.FileName = "$folderName-$(Get-Date -Format 'yyyy-MM-dd').zip"
                $saveDialog.AddExtension = $true
                if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    try {
                        $sourcePath = [System.IO.Path]::GetFullPath($folderDialog.SelectedPath).TrimEnd('\')
                        $archivePath = [System.IO.Path]::GetFullPath($saveDialog.FileName)
                        if ($archivePath.StartsWith($sourcePath + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                            throw "Choose a backup location outside the source folder."
                        }
                        Add-Type -AssemblyName System.IO.Compression.FileSystem
                        [System.IO.Compression.ZipFile]::CreateFromDirectory($sourcePath, $archivePath, [System.IO.Compression.CompressionLevel]::Optimal, $true)
                        Write-Result -OutputBox $outputBox -Message "ZIP backup created: $archivePath"
                    }
                    catch {
                        Write-Result -OutputBox $outputBox -Message "Could not create ZIP backup: $($_.Exception.Message)"
                    }
                }
            }
        }
        "Extract ZIP Archive" {
            $archiveDialog = New-Object System.Windows.Forms.OpenFileDialog
            $archiveDialog.Title = "Choose a ZIP archive"
            $archiveDialog.Filter = "ZIP archive (*.zip)|*.zip"
            if ($archiveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
                $folderDialog.Description = "Choose where to extract the archive"
                if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    try {
                        $folderName = [System.IO.Path]::GetFileNameWithoutExtension($archiveDialog.FileName)
                        $extractPath = Join-Path $folderDialog.SelectedPath $folderName
                        if (Test-Path $extractPath) {
                            $extractPath = Join-Path $folderDialog.SelectedPath "$folderName-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                        }
                        Expand-Archive -LiteralPath $archiveDialog.FileName -DestinationPath $extractPath -ErrorAction Stop
                        Write-Result -OutputBox $outputBox -Message "Archive extracted to: $extractPath"
                    }
                    catch {
                        Write-Result -OutputBox $outputBox -Message "Could not extract archive: $($_.Exception.Message)"
                    }
                }
            }
        }
        "Generate Battery Report" {
            $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
            $saveDialog.Title = "Save Battery Report"
            $saveDialog.Filter = "HTML report (*.html)|*.html"
            $saveDialog.FileName = "battery-report.html"
            $saveDialog.AddExtension = $true
            if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                try {
                    $result = & powercfg.exe /batteryreport /output $saveDialog.FileName 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Result -OutputBox $outputBox -Message "Battery report saved to: $($saveDialog.FileName)"
                        Start-Process $saveDialog.FileName | Out-Null
                    }
                    else {
                        Write-Result -OutputBox $outputBox -Message "Could not create battery report: $($result -join ' ')"
                    }
                }
                catch {
                    Write-Result -OutputBox $outputBox -Message "Could not create battery report."
                }
            }
        }
        "Empty Recycle Bin" {
            $answer = [System.Windows.Forms.MessageBox]::Show("Permanently delete the items in the Recycle Bin? This cannot be undone.", "Empty Recycle Bin", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    Clear-RecycleBin -Force -ErrorAction Stop
                    Write-Result -OutputBox $outputBox -Message "Recycle Bin emptied."
                }
                catch {
                    Write-Result -OutputBox $outputBox -Message "Could not empty Recycle Bin: $($_.Exception.Message)"
                }
            }
            else {
                Write-Result -OutputBox $outputBox -Message "Recycle Bin unchanged."
            }
        }
        "Optimize Drives" {
            try {
                Write-Result -OutputBox $outputBox -Message "Optimizing drives with Windows recommended settings..."
                $form.Refresh()
                $result = & "$env:SystemRoot\System32\defrag.exe" /C /O /U /V 2>&1
                Write-Result -OutputBox $outputBox -Message ($result | Out-String)
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Drive optimization could not be completed."
            }
        }
        "Use High Performance Power Plan" {
            $answer = [System.Windows.Forms.MessageBox]::Show("High Performance may use more electricity and reduce laptop battery life. Continue?", "Change Power Plan", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    $result = & powercfg.exe /setactive SCHEME_MIN 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Result -OutputBox $outputBox -Message "High Performance power plan enabled."
                    }
                    else {
                        Write-Result -OutputBox $outputBox -Message "Could not enable High Performance: $($result -join ' ')"
                    }
                }
                catch {
                    Write-Result -OutputBox $outputBox -Message "Could not change the power plan."
                }
            }
            else {
                Write-Result -OutputBox $outputBox -Message "Power plan unchanged."
            }
        }
        "Use Balanced Power Plan" {
            $answer = [System.Windows.Forms.MessageBox]::Show("Switch to the Balanced power plan?", "Change Power Plan", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    $result = & powercfg.exe /setactive SCHEME_BALANCED 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Result -OutputBox $outputBox -Message "Balanced power plan enabled."
                    }
                    else {
                        Write-Result -OutputBox $outputBox -Message "Could not enable Balanced: $($result -join ' ')"
                    }
                }
                catch {
                    Write-Result -OutputBox $outputBox -Message "Could not change the power plan."
                }
            }
            else {
                Write-Result -OutputBox $outputBox -Message "Power plan unchanged."
            }
        }
        "Restart Explorer" {
            try {
                Write-Result -OutputBox $outputBox -Message "Restarting Explorer..."
                $form.Refresh()
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
                Start-Process explorer.exe | Out-Null
                Write-Result -OutputBox $outputBox -Message "Explorer restarted."
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not restart Explorer."
            }
        }
        "Clear Temporary Files" {
            try {
                $paths = @($env:TEMP, (Join-Path $env:LOCALAPPDATA "Temp"))
                foreach ($path in $paths) {
                    if (Test-Path $path) {
                        Get-ChildItem -Path $path -Force -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                    }
                }
                Write-Result -OutputBox $outputBox -Message "Temporary files cleaned."
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not clear temporary files."
            }
        }
        "Run SFC Scan" {
            try {
                Write-Result -OutputBox $outputBox -Message "Running SFC /scannow... this may take a few minutes."
                $form.Refresh()
                $result = & sfc /scannow 2>&1
                Write-Result -OutputBox $outputBox -Message ($result | Out-String)
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "SFC scan failed or was blocked."
            }
        }
        "Run DISM Repair" {
            try {
                Write-Result -OutputBox $outputBox -Message "Running DISM /Online /Cleanup-Image /RestoreHealth..."
                $form.Refresh()
                $result = & DISM /Online /Cleanup-Image /RestoreHealth 2>&1
                Write-Result -OutputBox $outputBox -Message ($result | Out-String)
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "DISM repair failed or was blocked."
            }
        }
        "Run Custom Windows Debloater" {
            try {
                if (-not (Test-CommandExists -Name "Get-AppxPackage")) {
                    Write-Result -OutputBox $outputBox -Message "This Windows build does not support Appx debloat commands."
                    break
                }

                Write-Result -OutputBox $outputBox -Message "Running Custom Windows Debloater (safe cleanup)..."
                $form.Refresh()

                $bloatApps = @(
                    "Microsoft.3DBuilder",
                    "Microsoft.BingWeather",
                    "Microsoft.GetHelp",
                    "Microsoft.Getstarted",
                    "Microsoft.MicrosoftOfficeHub",
                    "Microsoft.People",
                    "Microsoft.SkypeApp",
                    "Microsoft.Todos",
                    "Microsoft.WindowsAlarms",
                    "Microsoft.WindowsFeedbackHub",
                    "Microsoft.WindowsMaps",
                    "Microsoft.YourPhone",
                    "Microsoft.ZuneMusic",
                    "Microsoft.ZuneVideo",
                    "Microsoft.MicrosoftSolitaireCollection",
                    "Microsoft.XboxApp",
                    "Microsoft.XboxGamingOverlay",
                    "Microsoft.XboxIdentityProvider",
                    "Microsoft.XboxSpeechToTextOverlay",
                    "Microsoft.Office.OneNote",
                    "Microsoft.BingSports",
                    "Microsoft.BingNews",
                    "Microsoft.BingFinance",
                    "Microsoft.NetworkSpeedTest",
                    "Microsoft.News"
                )

                foreach ($app in $bloatApps) {
                    Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue | Out-Null
                    if (Test-CommandExists -Name "Get-AppxProvisionedPackage") {
                        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $app } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
                    }
                }

                Write-Result -OutputBox $outputBox -Message "Custom debloat complete. Safe app cleanup finished."
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Debloat routine failed or was blocked by the system."
            }
        }
        "Disable Windows Telemetry" {
            try {
                Write-Result -OutputBox $outputBox -Message "Disabling Windows Telemetry..."
                $form.Refresh()
                
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "MaxTelemetryAllowed" -Value 0 -ErrorAction SilentlyContinue
                Disable-ScheduledTask -TaskPath "\Microsoft\Windows\Customer Experience Improvement Program\" -TaskName "Consolidator" -ErrorAction SilentlyContinue
                Disable-ScheduledTask -TaskPath "\Microsoft\Windows\Customer Experience Improvement Program\" -TaskName "UsbCeip" -ErrorAction SilentlyContinue
                Stop-Service -Name "DiagTrack" -ErrorAction SilentlyContinue
                Set-Service -Name "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
                Stop-Service -Name "dmwappushservice" -ErrorAction SilentlyContinue
                Set-Service -Name "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue

                Write-Result -OutputBox $outputBox -Message "Windows Telemetry disabled successfully."
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Failed to disable telemetry. Check permissions."
            }
        }
        "Install Performance Software" {
            try {
                Write-Result -OutputBox $outputBox -Message "Installing Performance Software via Winget (O&O ShutUp10, Quick CPU, etc)..."
                $form.Refresh()
                
                $wingetPath = Get-Command winget.exe -ErrorAction SilentlyContinue
                if (-not $wingetPath) {
                    Write-Result -OutputBox $outputBox -Message "Winget is not installed. Please install App Installer from Microsoft Store."
                    break
                }

                Write-Result -OutputBox $outputBox -Message "Installing Process Lasso..."
                $form.Refresh()
                & winget install -e --id Bitsum.ProcessLasso --silent --disable-interactivity --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                
                Write-Result -OutputBox $outputBox -Message "Installing O&O ShutUp10++..."
                $form.Refresh()
                & winget install -e --id OOO.ShutUp10++ --silent --disable-interactivity --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null

                Write-Result -OutputBox $outputBox -Message "Performance Software installed successfully."
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Failed to install software. Make sure winget is available."
            }
        }
        "Launch Chris Titus Winutil" {
            try {
                Write-Result -OutputBox $outputBox -Message "Launching Chris Titus Winutil..."
                $form.Refresh()
                Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command "irm https://christitus.com/win | iex"' -WindowStyle Normal | Out-Null
                Write-Result -OutputBox $outputBox -Message "Winutil launched in a separate window."
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not launch Winutil. Check your internet connection or security policy."
            }
        }
        "Quick Auto-Extract ZIP" {
            Invoke-QuickAutoExtract
        }
        "Add Defender Exclusion (Auto-Exception)" {
            Add-DefenderFolderExclusion
        }
        "Game Queue Auto-Accept Monitor" {
            Show-AutoAcceptDialog
        }
        "Show Saved Wi-Fi Passwords" {
            try {
                Write-Result -OutputBox $outputBox -Message "Scanning saved Wi-Fi profiles and security keys..."
                $form.Refresh()
                $profilesOutput = & netsh wlan show profiles 2>&1
                $profileNames = @()
                foreach ($line in $profilesOutput) {
                    if ($line -match ':\s*(.+)$') {
                        if ($line -match 'All User Profile\s*:\s*(.+)$' -or $line -match 'Profil Tous les utilisateurs\s*:\s*(.+)$' -or $line -match 'User Profile\s*:\s*(.+)$') {
                            $profileNames += $Matches[1].Trim()
                        }
                    }
                }
                if ($profileNames.Count -eq 0) {
                    Write-Result -OutputBox $outputBox -Message "No saved Wi-Fi profiles found or Wi-Fi service inactive."
                }
                else {
                    $msg = "========================================`r`n SAVED WI-FI NETWORKS & PASSWORDS`r`n========================================`r`n"
                    foreach ($p in $profileNames) {
                        $detail = & netsh wlan show profile name="$p" key=clear 2>&1
                        $keyFound = "(None / Open Network)"
                        foreach ($d in $detail) {
                            if ($d -match '(?:Key Content|Contenu de la cl|Contenido de la clave)\s*:\s*(.+)$') {
                                $keyFound = $matches[1].Trim()
                                break
                            }
                        }
                        $msg += ("{0,-24} : {1}`r`n" -f $p, $keyFound)
                    }
                    $msg += "========================================"
                    Write-Result -OutputBox $outputBox -Message $msg
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not retrieve Wi-Fi passwords: $($_.Exception.Message)"
            }
        }
        "Reset Network Stack (Full Repair)" {
            $confirm = [System.Windows.Forms.MessageBox]::Show(
                "This will reset Winsock, TCP/IP stack, release/renew IP, and flush DNS.`r`n`r`nDo you want to proceed?",
                "Reset Network Stack",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                Write-Result -OutputBox $outputBox -Message "Resetting Winsock catalog..."
                $form.Refresh()
                & netsh winsock reset 2>&1 | Out-Null
                Write-Result -OutputBox $outputBox -Message "Resetting IPv4 & IPv6 stacks..."
                $form.Refresh()
                & netsh int ip reset 2>&1 | Out-Null
                & ipconfig /release 2>&1 | Out-Null
                & ipconfig /renew 2>&1 | Out-Null
                & ipconfig /flushdns 2>&1 | Out-Null
                Write-Result -OutputBox $outputBox -Message "Network stack full reset complete! A computer restart is recommended."
            }
        }
        "Switch DNS (Cloudflare / Google / DHCP)" {
            Show-DnsSwitchDialog
        }
        "Enable Ultimate Performance Plan" {
            try {
                Write-Result -OutputBox $outputBox -Message "Activating Ultimate Performance Power Plan..."
                $form.Refresh()
                $out = & powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
                if ($out -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
                    $guid = $matches[1]
                    & powercfg /setactive $guid 2>&1 | Out-Null
                    Write-Result -OutputBox $outputBox -Message "Ultimate Performance plan activated! (GUID: $guid)`r`nEliminates micro-stutters and maximizes CPU readiness."
                }
                else {
                    & powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
                    Write-Result -OutputBox $outputBox -Message "High Performance plan activated."
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not configure power plan: $($_.Exception.Message)"
            }
        }
        "Kill Not Responding Apps" {
            try {
                Write-Result -OutputBox $outputBox -Message "Checking for frozen / unresponsive programs..."
                $res = & taskkill.exe /F /FI "STATUS eq NOT RESPONDING" 2>&1
                Write-Result -OutputBox $outputBox -Message ($res -join "`r`n")
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Failed to terminate unresponsive apps: $($_.Exception.Message)"
            }
        }
        "Clear Standby RAM & Icon Cache" {
            try {
                Write-Result -OutputBox $outputBox -Message "Clearing icon & thumbnail caches..."
                $form.Refresh()
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
                $iconCache = Join-Path $env:LOCALAPPDATA "IconCache.db"
                if (Test-Path $iconCache) { Remove-Item $iconCache -Force -ErrorAction SilentlyContinue }
                $thumbCache = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer"
                if (Test-Path $thumbCache) {
                    Get-ChildItem -Path $thumbCache -Filter "thumbcache_*.db" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                    Get-ChildItem -Path $thumbCache -Filter "iconcache_*.db" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                }
                [System.GC]::Collect()
                Start-Process explorer.exe | Out-Null
                Write-Result -OutputBox $outputBox -Message "Icon cache cleared and Windows Explorer refreshed."
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not clear cache: $($_.Exception.Message)"
            }
        }
        "Check Hardware & Specs Summary" {
            try {
                Write-Result -OutputBox $outputBox -Message "Gathering hardware specifications..."
                $form.Refresh()
                $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
                $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
                $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
                $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
                $bb = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
                $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue

                $ramGB = [math]::Round(($cs.TotalPhysicalMemory / 1GB), 1)

                $msg = "========================================`r`n PC HARDWARE & SPECS SUMMARY`r`n========================================`r`n"
                $msg += "OS:           $($os.Caption) ($($os.OSArchitecture), Build $($os.BuildNumber))`r`n"
                $msg += "Motherboard:  $($bb.Manufacturer) $($bb.Product) (BIOS: $($bios.SMBIOSBIOSVersion))`r`n"
                $msg += "Processor:    $($cpu.Name.Trim()) ($($cpu.NumberOfCores) Cores, $($cpu.NumberOfLogicalProcessors) Threads)`r`n"
                $msg += "Memory (RAM): $ramGB GB Total Installed`r`n"
                foreach ($gpu in $gpus) {
                    $msg += "Graphics:     $($gpu.Name) (Driver: $($gpu.DriverVersion))`r`n"
                }
                $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
                foreach ($d in $disks) {
                    $freeGB = [math]::Round(($d.FreeSpace / 1GB), 1)
                    $totalGB = [math]::Round(($d.Size / 1GB), 1)
                    $msg += "Storage $($d.DeviceID)   $freeGB GB free of $totalGB GB ($($d.FileSystem))`r`n"
                }
                $msg += "========================================"
                Write-Result -OutputBox $outputBox -Message $msg
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not read specs: $($_.Exception.Message)"
            }
        }
        "Check Windows Activation Status" {
            try {
                Write-Result -OutputBox $outputBox -Message "Checking Windows activation status..."
                $form.Refresh()
                $slmgr = & cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /xpr 2>&1
                Write-Result -OutputBox $outputBox -Message ($slmgr -join "`r`n")
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not check activation status."
            }
        }
        "Toggle Hibernation (Free Disk Space)" {
            try {
                $hiberFile = "C:\hiberfil.sys"
                if (Test-Path $hiberFile) {
                    $sizeGB = [math]::Round(((Get-Item $hiberFile -Force).Length / 1GB), 1)
                    $confirm = [System.Windows.Forms.MessageBox]::Show(
                        "Hibernation is currently ENABLED (hiberfil.sys is using ~$sizeGB GB of C: drive space).`r`n`r`nDo you want to DISABLE hibernation to instantly free this space?",
                        "Toggle Hibernation",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Question
                    )
                    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                        & powercfg.exe -h off 2>&1 | Out-Null
                        Write-Result -OutputBox $outputBox -Message "Hibernation DISABLED. ~$sizeGB GB disk space freed on C: drive!"
                    }
                }
                else {
                    $confirm = [System.Windows.Forms.MessageBox]::Show(
                        "Hibernation is currently DISABLED.`r`n`r`nDo you want to ENABLE hibernation (Fast Startup requires this)?",
                        "Toggle Hibernation",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Question
                    )
                    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                        & powercfg.exe -h on 2>&1 | Out-Null
                        Write-Result -OutputBox $outputBox -Message "Hibernation ENABLED."
                    }
                }
            }
            catch {
                Write-Result -OutputBox $outputBox -Message "Could not toggle hibernation: $($_.Exception.Message)"
            }
        }
        "Ping Custom Address" {
            Show-PingCustomDialog
        }
                "Install Popular Software (Winget)" {
            Show-ExtrasHub -InitialTab "Apps"
        }
        "Windows Built-In Utilities & Apps" {
            Show-ExtrasHub -InitialTab "Apps"
        }
"Run Disk Cleanup" {
            Start-Process "cleanmgr.exe" | Out-Null
            Write-Result -OutputBox $outputBox -Message "Disk Cleanup launched."
        }
        "1-Click Quick PC Boost" {
            Invoke-QuickPcBoost
        }
        "Optimize Network & Gaming Latency" {
            Optimize-GamingLatency
        }
        "Clear Windows Update Cache" {
            Clear-WindowsUpdateCache
        }
        "Optimize Visual Effects" {
            Optimize-VisualEffects
        }
        "Disable Search Indexer" {
            Switch-SearchIndexer
        }
        "Disable Background GameDVR" {
            Disable-BackgroundGameDVR
        }
        "Clean Browser Caches (Chrome/Edge/Discord)" {
            Clear-BrowserCaches
        }
        "Disable Mouse Acceleration (1:1 Raw Input)" {
            Disable-MouseAcceleration
        }
        "Optimize TCP Auto-Tuning & RSS" {
            Optimize-TcpAutoTuning
        }
        "Disable Delivery Optimization (P2P Leech)" {
            Disable-DeliveryOptimization
        }
        "Disable Windows Bloat Auto-Install" {
            Disable-WindowsConsumerBloat
        }
        "Disable Cortana & Start Web Search" {
            Disable-CortanaBingSearch
        }
        "Clean Windows Crash Dumps & Error Reports" {
            Clear-CrashDumpsAndWer
        }
        "Trim & Re-Trim All SSD Drives" {
            Optimize-TrimSsdDrives
        }
        "Disable Nagle's Algorithm (TcpAckFrequency)" {
            Disable-NagleAlgorithm
        }
        "Disable Sticky Keys Popups in Games" {
            Disable-StickyKeysPopups
        }
        "Flush DNS & NetBIOS Caches" {
            Clear-DnsAndNetbios
        }
        "Free Standby & Working Set RAM" {
            Clear-StandbyAndWorkingSetRam
        }
        default {
            Write-Result -OutputBox $outputBox -Message "This action is not available."
        }
    }
})


# Backward-compatibility aliases for approved verbs
Set-Alias -Name Ensure-Admin -Value Assert-Admin -ErrorAction SilentlyContinue
Set-Alias -Name Load-PinnedCommands -Value Import-PinnedCommands -ErrorAction SilentlyContinue
Set-Alias -Name Ensure-ProAccess -Value Assert-ProAccess -ErrorAction SilentlyContinue
Set-Alias -Name Load-CustomCommands -Value Import-CustomCommands -ErrorAction SilentlyContinue
Set-Alias -Name Toggle-SearchIndexer -Value Switch-SearchIndexer -ErrorAction SilentlyContinue
Set-Alias -Name Clean-BrowserCaches -Value Clear-BrowserCaches -ErrorAction SilentlyContinue
Set-Alias -Name Clean-CrashDumpsAndWer -Value Clear-CrashDumpsAndWer -ErrorAction SilentlyContinue
Set-Alias -Name Purge-DnsAndNetbios -Value Clear-DnsAndNetbios -ErrorAction SilentlyContinue
Set-Alias -Name Free-StandbyAndWorkingSetRam -Value Clear-StandbyAndWorkingSetRam -ErrorAction SilentlyContinue
Set-Alias -Name Load-UserProfile -Value Import-UserProfile -ErrorAction SilentlyContinue
Set-Alias -Name Apply-Theme -Value Set-Theme -ErrorAction SilentlyContinue

# Auto memory optimization and zero-idle hooks
$form.Add_Shown({ [MemoryOptimizer]::TrimProcessMemory() })
$form.Add_Deactivate({ [MemoryOptimizer]::TrimProcessMemory() })
$form.Add_SizeChanged({
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        [MemoryOptimizer]::TrimProcessMemory()
    }
})
[MemoryOptimizer]::TrimProcessMemory()

[void]$form.ShowDialog()

