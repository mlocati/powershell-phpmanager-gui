Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$dllPath = [System.IO.Path]::Combine($PSScriptRoot, 'bin', 'CLRCLI.dll')
Import-Module $dllPath | Out-Null

$Script:RootWindow = [CLRCLI.Widgets.RootWindow]::new()
$Script:RootWindow.Visible = $false

$Script:MainDialog = [CLRCLI.Widgets.Dialog]::new($Script:RootWindow)
$Script:MainDialog.Enabled = $false
$Script:MainDialog.Left = 3
$Script:MainDialog.Top = 2
$Script:MainDialog.Width = 60
$Script:MainDialog.Height = 32
$Script:MainDialog.Text = 'Web Server Controller'
$Script:MainDialog.Border = [CLRCLI.BorderStyle]::Thick

$phpVersionLabel = [CLRCLI.Widgets.Label]::new($Script:MainDialog)
$phpVersionLabel.Left = 2
$phpVersionLabel.Top = 1
$phpVersionLabel.Text = 'PHP Version'

$Script:PhpVersionList = [CLRCLI.Widgets.ListBox]::new($Script:MainDialog)
$Script:PhpVersionList.Left = 2
$Script:PhpVersionList.Top = 3
$Script:PhpVersionList.Width = 20
$Script:PhpVersionList.Height = 15
$Script:PhpVersionList.Border = [CLRCLI.BorderStyle]::Thin

$switcher = Get-PhpSwitcher
$Script:SwitcherAlias = $switcher.Alias
if ($switcher.Current -eq '') {
    $Script:PhpVersionList.Items.Add('')
}
$switcherKeys = [string[]]::new($switcher.Targets.Keys.Count)
$switcher.Targets.Keys.CopyTo($switcherKeys, 0)
$switcherKeys | Sort-Object | ForEach-Object {
    $Script:PhpVersionList.Items.Add($_)
    if ($switcher.Current -eq $_) {
        $Script:PhpVersionList.SelectedIndex = $Script:PhpVersionList.Items.Count - 1
    }
}

$phpExtensionsLabel = [CLRCLI.Widgets.Label]::new($Script:MainDialog)
$phpExtensionsLabel.Left = 25
$phpExtensionsLabel.Top = 1
$phpExtensionsLabel.Text = 'Extensions'

$currentPhpVersionLabel = [CLRCLI.Widgets.Label]::new($Script:MainDialog)
$currentPhpVersionLabel.Left = 2
$currentPhpVersionLabel.Top = 20
$currentPhpVersionLabel.Text = 'Current PHP Version:'

$Script:CurrentPhpVersion = [CLRCLI.Widgets.Label]::new($Script:MainDialog)
$Script:CurrentPhpVersion.Left = 2
$Script:CurrentPhpVersion.Top = 22
$Script:CurrentPhpVersion.Background = 'DarkGray'
function SetCurrentPhpVersion {
    param([string] $version)
    $Script:CurrentPhpVersion.Text = $version.PadRight($Script:MainDialog.Width - $Script:CurrentPhpVersion.Left * 2, ' ');    
}

SetCurrentPhpVersion ''

$Script:Spinner = [CLRCLI.Widgets.TinySpinner]::new($Script:MainDialog)
$Script:Spinner.Left = $Script:MainDialog.Width - 2
$Script:Spinner.Top = 0
$Script:Spinner.Visible = $false
$Script:SpinnerHider = [CLRCLI.Widgets.Label]::new($Script:MainDialog)
$Script:SpinnerHider.Left = $Script:Spinner.Left
$Script:SpinnerHider.Top = $Script:Spinner.Top
$Script:SpinnerHider.Text = ' '
$Script:SpinnerHider.Visible = $true
function ShowSpinner {
    param([bool] $show)
    if (-not($Script:RootWindow.Visible)) {
        return
    }
    $Script:Spinner.Spinning = $show
    if ($show) {
        $Script:Spinner.Visible = $true    
        $Script:SpinnerHider.Visible = $false
    }
    else {
        $Script:SpinnerHider.Visible = $true
        $Script:Spinner.Visible = $false
    }
}

$Script:AlertDialog = [CLRCLI.Widgets.Dialog]::new($Script:RootWindow)
$Script:AlertDialog.Background = 'Red'
$Script:AlertDialog.Text = 'Whoops'
$Script:AlertDialog.Width = 40
$Script:AlertDialog.Height = 10
$Script:AlertDialog.Left = ($Script:MainDialog.Width - $Script:AlertDialog.Width) / 2
$Script:AlertDialog.Top = ($Script:MainDialog.Height - $Script:AlertDialog.Height) / 2
$Script:AlertDialog.Border = [CLRCLI.BorderStyle]::Thick
$Script:AlertDialog.Visible = $false
$Script:AlertDialogLabel = [CLRCLI.Widgets.Label]::new($Script:AlertDialog)
$Script:AlertDialogLabel.Left = 1
$Script:AlertDialogLabel.Top = 1
$Script:AlertDialogLabel.Foreground = 'Yellow'
$Script:AlertDialogLabel.Text = ''
$btnCloseAlert = [CLRCLI.Widgets.Button]::new($Script:AlertDialog)
$btnCloseAlert.Width = 9
$btnCloseAlert.Height = 3
$btnCloseAlert.Left = ($Script:AlertDialog.Width - $btnCloseAlert.Width) / 2
$btnCloseAlert.Top = ($Script:AlertDialog.Height - $btnCloseAlert.Height) - 1
$btnCloseAlert.Text = 'Close'
$btnCloseAlert.Add_Clicked( {
        $Script:AlertDialog.Hide()
        $Script:MainDialog.Show()
    })

function ShowAlert {
    param([string] $text)
    if (-not($Script:RootWindow.Visible)) {
        return
    }
    $Script:AlertDialogLabel.Text = $text
    $Script:MainDialog.Hide()
    $Script:AlertDialog.Show()
}
class PhpExtension {
    [string]
    [ValidateNotNull()]
    [ValidateLength(1, [int]::MaxValue)]
    $Handle
    [int]
    $Index
    [System.Object]
    $Checkbox
    PhpExtension([string] $handle) {
        $this.Handle = $handle
        $this.Index = $Script:UIExtensions.Length
        $this.Checkbox = New-Object -TypeName 'CLRCLI.Widgets.Checkbox' -ArgumentList $Script:MainDialog
        #$this.Checkbox = [CLRCLI.Widgets.Checkbox]::new($Script:MainDialog)
        $this.Checkbox.Left = 25
        $this.Checkbox.Top = 3 + $this.Index * 2
        $this.Checkbox.Text = $this.Handle
        $this.Checkbox.Add_Clicked( {
                if (-not($this.Enabled)) {
                    return;
                }
                ShowSpinner $true
                try {
                    if ($this.Checked) {
                        Enable-PhpExtension $this.Text
                    }
                    else {
                        Disable-PhpExtension $this.Text
                    }
                }
                catch {
                    ShowSpinner $false
                    ShowAlert $_
                    ShowSpinner $true
                }
                PhpVersionUpdated
            })
    }
}

$Script:UIExtensions = [PhpExtension[]] @()

[string[]]'xdebug', 'opcache' | ForEach-Object {
    $Script:UIExtensions += [PhpExtension]::new($_)
}

function PhpVersionUpdated {
    ShowSpinner $true
    try {
        $php = Get-Php -Path $Script:SwitcherAlias
    }
    catch {
        $php = $null
    }
    if ($null -eq $php) {
        SetCurrentPhpVersion ''
    }
    else {
        SetCurrentPhpVersion $php.DisplayName
    }
    try {
        $currentExtensions = Get-PhpExtension -Path $Script:SwitcherAlias
        ShowSpinner $false
        $ok = $true
    }
    catch {
        ShowSpinner $false
        ShowAlert $_
        $ok = $false
    }
    $Script:UIExtensions | ForEach-Object {
        $_.Checkbox.Foreground = 'DarkGray'
        $_.Checkbox.Visible = $false
        $_.Checkbox.Enabled = $false
        $_.Checkbox.Checked = $false
        if ($ok) {
            $currentExtension = $currentExtensions | Where-Object -Property Handle -eq $_.Handle
            if ($currentExtension) {
                $_.Checkbox.Foreground = 'White'
                if ($currentExtension.State -eq 'Enabled') {
                    $_.Checkbox.Checked = $true
                }
                $_.Checkbox.Enabled = $true
            }
        }
        $_.Checkbox.Visible = $true
    }
}

PhpVersionUpdated

$Script:PhpVersionList.Add_Clicked( {
        $version = $Script:PhpVersionList.SelectedItem
        if ($version -eq '') {
            return
        }
        ShowSpinner $true
        try {
            Switch-Php $version
        }
        catch {
            ShowSpinner $false
            ShowAlert $_
            return
        }
        PhpVersionUpdated
    })

class ServerService {
    [string]
    [ValidateNotNull()]
    $Name
    [System.Object]
    [ValidateNotNull()]
    $Controller
    [System.Object]
    [ValidateNotNull()]
    $Button
    [System.Timers.Timer]
    $RefreshTimer
    ServerService([System.Object] $controller) {
        $this.Name = ''
        if ($null -ne $controller.DisplayName) {
            $this.Name = $controller.DisplayName;
        }
        if ($this.Name -eq '') {
            $this.Name = $controller.Name;
        }
        $this.Controller = $controller
        $this.Button = New-Object -TypeName 'CLRCLI.Widgets.Button' -ArgumentList $Script:MainDialog
        $this.Button.Width = 20
        $this.Button.Height = 3
        $this.Button.Left = ($Script:MainDialog.Width - $this.Button.Width) / 2
        $this.Button.Top = ($Script:MainDialog.Height - $this.Button.Height) - 1
        $this.RefreshTimer = New-Object Timers.Timer
        $this.RefreshTimer.Interval = 500
        $this.RefreshTimer.Enabled = $false
        $this.RefreshTimer.AutoReset = $false
        Register-ObjectEvent -InputObject $this.RefreshTimer -EventName 'Elapsed' -Action {
            $Script:ServerService.Controller.Refresh();
            $Script:ServerService.RefreshState();
        }
        $this.RefreshState()
        $this.RefreshTimer.Start()
        $this.Button.Add_Clicked( {
                $my = $Script:ServerService
                $my.Controller.Refresh()
                $status = [string]$my.Controller.Status
                switch ($status) {
                    'Stopped' {
                        $my.Execute($false)
                    }
                    'Running' {
                        $my.Execute($true)
                    }
                    'Paused' {
                        $my.Execute($false)
                    }
                    default {
                        ShowAlert $status
                        $my.RefreshState()
                    }
                }
            })
    }
    Execute([bool] $restart) {
        $requireRunAs = $false
        $currentUser = [System.Security.Principal.WindowsPrincipal] [System.Security.Principal.WindowsIdentity]::GetCurrent()
        if (-Not($currentUser.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))) {
            $requireRunAs = $true
        }
        if ($requireRunAs) {
            if ($restart) {
                $exeCommand = "Restart-Service -Name '$($this.Controller.Name)' -WarningAction SilentlyContinue"
            }
            else {
                $exeCommand = "Start-Service -Name '$($this.Controller.Name)' -WarningAction SilentlyContinue"
            }
            try {
                Start-Process -FilePath 'powershell.exe' -ArgumentList "-Command ""$exeCommand""" -WindowStyle Hidden -Verb RunAs -Wait
            }
            catch {
            }
        }
        else {
            if ($restart) {
                Restart-Service -Name $this.Controller.Name 2>&1 -WarningAction SilentlyContinue
            }
            else {
                Start-Service -Name $this.Controller.Name 2>&1 -WarningAction SilentlyContinue
            }
        }
        $this.Controller.Refresh()
        $this.RefreshState()
    }
    RefreshState() {
        $status = [string]$this.Controller.Status
        switch ($status) {
            'Stopped' {
                $this.Button.Enabled = $true
                $this.Button.Text = 'Start ' + $this.Name
            }
            'StartPending' {
                $this.Button.Enabled = $false
                $this.Button.Text = 'Starting ' + $this.Name + '...'
            }
            'StopPending' {
                $this.Button.Enabled = $false
                $this.Button.Text = 'Stopping ' + $this.Name + '...'
            }
            'Running' {
                $this.Button.Enabled = $true
                $this.Button.Text = 'Restart ' + $this.Name
            }
            'ContinuePending' {
                $this.Button.Enabled = $false
                $this.Button.Text = 'Resuming ' + $this.Name + '...'
            }
            'PausePending' {
                $this.Button.Enabled = $false
                $this.Button.Text = 'Pausing ' + $this.Name + '...'
            }
            'Paused' {
                $this.Button.Enabled = $true
                $this.Button.Text = 'Resume ' + $this.Name
            }
            default {
                $this.Button.Enabled = $false
                $this.Button.Text = $this.Controller.Status
            }
        }
        if ($this.Button.Enabled -eq $false) {
            $this.RefreshTimer.Start()
        }
    }
}
$Script:ServerService = $null

$serviceControllers = Get-Service

[string[]]'Nginx', 'Apache' | ForEach-Object {
    if ($null -eq $Script:ServerService) {
        $serviceController = $serviceControllers | Where-Object -Property Name -Match "^$_\s*(v?.?\s*\d.*)?$"
        if ($serviceController) {
            $Script:ServerService = [ServerService]::new($serviceController)
        }
    }
}

$Script:RootWindow.Visible = $true
$Script:RootWindow.Run()
$Script:RootWindow.Detach()
