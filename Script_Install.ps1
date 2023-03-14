
################################################################################################################
###                                                                                                          ###
###							      		       Edited by Eddows                                              ###
###                                                                                                          ###
################################################################################################################

<#
.NOTES
    Author         : Chris Titus @christitustech edited by EDDOWs for eFM
    Runspace Author: @DeveloperDurp
    GitHub         : https://github.com/ChrisTitusTech
    Version        : 23.03.07
#>

Start-Transcript $ENV:TEMP\Winutil.log -Append

#Load DLLs
Add-Type -AssemblyName System.Windows.Forms

# variable to sync between runspaces
$sync = [Hashtable]::Synchronized(@{})
$sync.PSScriptRoot = $PSScriptRoot

$sync.configs = @{}
$sync.ProcessRunning = $false
Function Get-WinUtilCheckBoxes {

    <#

        .DESCRIPTION
        Function is meant to find all checkboxes that are checked on the specefic tab and input them into a script.

        Outputed data will be the names of the checkboxes that were checked

        .EXAMPLE

        Get-WinUtilCheckBoxes "WPFInstall"

    #>

    Param(
        $Group,
        [boolean]$unCheck = $true
    )


    $Output = New-Object System.Collections.Generic.List[System.Object]

    if($Group -eq "WPFInstall"){
        $CheckBoxes = get-variable | Where-Object {$psitem.name -like "WPFInstall*" -and $psitem.value.GetType().name -eq "CheckBox"}
        Foreach ($CheckBox in $CheckBoxes){
            if($CheckBox.value.ischecked -eq $true){
                $sync.configs.applications.$($CheckBox.name).winget -split ";" | ForEach-Object {
                    $Output.Add($psitem)
                }
                if ($uncheck -eq $true){
                    $CheckBox.value.ischecked = $false
                }
                
            }
        }
    }
    if($Group -eq "WPFTweaks"){
        $CheckBoxes = get-variable | Where-Object {$psitem.name -like "WPF*Tweaks*" -and $psitem.value.GetType().name -eq "CheckBox"}
        Foreach ($CheckBox in $CheckBoxes){
            if($CheckBox.value.ischecked -eq $true){
                $Output.Add($Checkbox.Name)
                
                if ($uncheck -eq $true){
                    $CheckBox.value.ischecked = $false
                }
            }
        }
    }

    Write-Output $($Output | Select-Object -Unique)
}
Function Get-WinUtilDarkMode {
    <#
    
        .DESCRIPTION
        Meant to pull the registry keys responsible for Dark Mode and returns true or false
    
    #>
    $app = (Get-ItemProperty -path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize').AppsUseLightTheme
    $system = (Get-ItemProperty -path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize').SystemUsesLightTheme
    if($app -eq 0 -and $system -eq 0){
        return $true
    } 
    else{
        return $false
    }
}
function Get-WinUtilInstallerProcess {
    <#
    
        .DESCRIPTION
        Meant to check for running processes and will return a boolean response
    
    #>

    param($Process)

    if ($Null -eq $Process){
        return $false
    }
    if (Get-Process -Id $Process.Id -ErrorAction SilentlyContinue){
        return $true
    }
    return $false
}
function Install-WinUtilChoco {

    <#
    
        .DESCRIPTION
        Function is meant to ensure Choco is installed 
    
    #>

    try{
        Write-Host "Checking if Chocolatey is Installed..."

        if((Test-WinUtilPackageManager -choco)){
            Write-Host "Chocolatey Already Installed"
            return
        }
    
        Write-Host "Seems Chocolatey is not installed, installing now?"
        #Let user decide if he wants to install Chocolatey
        $confirmation = Read-Host "Are you Sure You Want To Proceed:(y/n)"
        if ($confirmation -eq 'y') {
            Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')) -ErrorAction Stop
            powershell choco feature enable -n allowGlobalConfirmation
        }
    }
    Catch{
        throw [ChocoFailedInstall]::new('Failed to install')
    }

}
Function Install-WinUtilProgramWinget {

    <#
    
        .DESCRIPTION
        This will install programs via Winget using a new powershell.exe instance to prevent the GUI from locking up.

        Note the triple quotes are required any time you need a " in a normal script block.
    
    #>

    param($ProgramsToInstall)

    $x = 0
    $count = $($ProgramsToInstall -split ",").Count

    Write-Progress -Activity "Installing Applications" -Status "Starting" -PercentComplete 0

    Foreach ($Program in $($ProgramsToInstall -split ",")){
    
        Write-Progress -Activity "Installing Applications" -Status "Installing $Program $($x + 1) of $count" -PercentComplete $($x/$count*100)
        Start-Process -FilePath winget -ArgumentList "install -e --accept-source-agreements --accept-package-agreements --silent $Program" -NoNewWindow -Wait;
        $X++
    }

    Write-Progress -Activity "Installing Applications" -Status "Finished" -Completed

}
function Install-WinUtilWinget {
    
    <#
    
        .DESCRIPTION
        Function is meant to ensure winget is installed 
    
    #>
    Try{
        Write-Host "Checking if Winget is Installed..."
        if (Test-WinUtilPackageManager -winget) {
            #Checks if winget executable exists and if the Windows Version is 1809 or higher
            Write-Host "Winget Already Installed"
            return
        }

        #Gets the computer's information
        if ($null -eq $sync.ComputerInfo){
            $ComputerInfo = Get-ComputerInfo -ErrorAction Stop
        }
        Else {
            $ComputerInfo = $sync.ComputerInfo
        }

        if (($ComputerInfo.WindowsVersion) -lt "1809") {
            #Checks if Windows Version is too old for winget
            Write-Host "Winget is not supported on this version of Windows (Pre-1809)"
            return
        }

        #Gets the Windows Edition
        $OSName = if ($ComputerInfo.OSName) {
            $ComputerInfo.OSName
        }else {
            $ComputerInfo.WindowsProductName
        }

        if (((($OSName.IndexOf("LTSC")) -ne -1) -or ($OSName.IndexOf("Server") -ne -1)) -and (($ComputerInfo.WindowsVersion) -ge "1809")) {

            Write-Host "Running Alternative Installer for LTSC/Server Editions"

            # Switching to winget-install from PSGallery from asheroto
            # Source: https://github.com/asheroto/winget-installer

            Start-Process powershell.exe -Verb RunAs -ArgumentList "-command irm https://raw.githubusercontent.com/ChrisTitusTech/winutil/$BranchToUse/winget.ps1 | iex | Out-Host" -WindowStyle Normal -ErrorAction Stop

            if(!(Test-WinUtilPackageManager -winget)){
                break
            }
        }

        else {
            #Installing Winget from the Microsoft Store
            Write-Host "Winget not found, installing it now."
            Start-Process "ms-appinstaller:?source=https://aka.ms/getwinget"
            $nid = (Get-Process AppInstaller).Id
            Wait-Process -Id $nid

            if(!(Test-WinUtilPackageManager -winget)){
                break
            }
        }
        Write-Host "Winget Installed"
    }
    Catch{
        throw [WingetFailedInstall]::new('Failed to install')
    }
}
function Invoke-WinUtilScript {
    <#
    
        .DESCRIPTION
        This function will run a seperate powershell script. Meant for things that can't be handled with the other functions

        .EXAMPLE

        $Scriptblock = [scriptblock]::Create({"Write-output 'Hello World'"})
        Invoke-WinUtilScript -ScriptBlock $scriptblock -Name "Hello World"
    
    #>
    param (
        $Name,
        [scriptblock]$scriptblock
    )

    Try{
        Invoke-Command $scriptblock -ErrorAction stop
        Write-Host "Running Script for $name"
    }
    Catch{
        Write-Warning "Unable to run script for $name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace 
    }
}
function Invoke-WinUtilTweaks {
    <#
    
        .DESCRIPTION
        This function converts all the values from the tweaks.json and routes them to the appropriate function
    
    #>

    param(
        $CheckBox,
        $undo = $false
    )
    if($undo){
        $Values = @{
            Registry = "OriginalValue"
            ScheduledTask = "OriginalState"
            Service = "OriginalType"
        }
    }    
    Else{
        $Values = @{
            Registry = "Value"
            ScheduledTask = "State"
            Service = "StartupType"
        }
    }

    if($sync.configs.tweaks.$CheckBox.registry){
        $sync.configs.tweaks.$CheckBox.registry | ForEach-Object {
            Set-WinUtilRegistry -Name $psitem.Name -Path $psitem.Path -Type $psitem.Type -Value $psitem.$($values.registry)
        }
    }
    if($sync.configs.tweaks.$CheckBox.ScheduledTask){
        $sync.configs.tweaks.$CheckBox.ScheduledTask | ForEach-Object {
            Set-WinUtilScheduledTask -Name $psitem.Name -State $psitem.$($values.ScheduledTask)
        }
    }
    if($sync.configs.tweaks.$CheckBox.service){
        $sync.configs.tweaks.$CheckBox.service | ForEach-Object {
            Set-WinUtilService -Name $psitem.Name -StartupType $psitem.$($values.Service)
        }
    }

    if(!$undo){
        if($sync.configs.tweaks.$CheckBox.appx){
            $sync.configs.tweaks.$CheckBox.appx | ForEach-Object {
                Remove-WinUtilAPPX -Name $psitem
            }
        }
        if($sync.configs.tweaks.$CheckBox.InvokeScript){
            $sync.configs.tweaks.$CheckBox.InvokeScript | ForEach-Object {
                $Scriptblock = [scriptblock]::Create($psitem)
                Invoke-WinUtilScript -ScriptBlock $scriptblock -Name $CheckBox
            }
        }
    }
}
function Remove-WinUtilAPPX {
    <#
    
        .DESCRIPTION
        This function will remove any of the provided APPX names

        .EXAMPLE

        Remove-WinUtilAPPX -Name "Microsoft.Microsoft3DViewer"
    
    #>
    param (
        $Name
    )

    Try{
        Write-Host "Removing $Name"
        Get-AppxPackage "*$Name*" | Remove-AppxPackage -ErrorAction SilentlyContinue
        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*$Name*" | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    }
    Catch [System.Exception] {
        if($psitem.Exception.Message -like "*The requested operation requires elevation*"){
            Write-Warning "Unable to uninstall $name due to a Security Exception"
        }
        Else{
            Write-Warning "Unable to uninstall $name due to unhandled exception"
            Write-Warning $psitem.Exception.StackTrace 
        }
    }
    Catch{
        Write-Warning "Unable to uninstall $name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace 
    }
}
function Set-WinUtilDNS {
    <#
    
        .DESCRIPTION
        This function will set the DNS of all interfaces that are in the "Up" state. It will lookup the values from the DNS.Json file

        .EXAMPLE

        Set-WinUtilDNS -DNSProvider "google"
    
    #>
    param($DNSProvider)
    if($DNSProvider -eq "Default"){return}
    Try{
        $Adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
        Write-Host "Ensuring DNS is set to $DNSProvider on the following interfaces"
        Write-Host $($Adapters | Out-String)

        Foreach ($Adapter in $Adapters){
            if($DNSProvider -eq "DHCP"){
                Set-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ResetServerAddresses
            }
            Else{
                Set-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ServerAddresses ("$($sync.configs.dns.$DNSProvider.Primary)", "$($sync.configs.dns.$DNSProvider.Secondary)")
            }
        }
    }
    Catch{
        Write-Warning "Unable to set DNS Provider due to an unhandled exception"
        Write-Warning $psitem.Exception.StackTrace 
    }
}
function Set-WinUtilRegistry {
    <#
    
        .DESCRIPTION
        This function will make all modifications to the registry

        .EXAMPLE

        Set-WinUtilRegistry -Name "PublishUserActivities" -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Type "DWord" -Value "0"
    
    #>    
    param (
        $Name,
        $Path,
        $Type,
        $Value
    )

    Try{      
        if(!(Test-Path 'HKU:\')){New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS}

        If (!(Test-Path $Path)) {
            Write-Host "$Path was not found, Creating..."
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }

        Write-Host "Set $Path\$Name to $Value"
        Set-ItemProperty -Path $Path -Name $Name -Type $Type -Value $Value -Force -ErrorAction Stop | Out-Null
    }
    Catch [System.Security.SecurityException] {
        Write-Warning "Unable to set $Path\$Name to $Value due to a Security Exception"
    }
    Catch [System.Management.Automation.ItemNotFoundException] {
        Write-Warning $psitem.Exception.ErrorRecord
    }
    Catch{
        Write-Warning "Unable to set $Name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
function Set-WinUtilScheduledTask {
    <#
    
        .DESCRIPTION
        This function will enable/disable the provided Scheduled Task

        .EXAMPLE

        Set-WinUtilScheduledTask -Name "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" -State "Disabled"
    
    #>
    param (
        $Name,
        $State
    )

    Try{
        if($State -eq "Disabled"){
            Write-Host "Disabling Scheduled Task $Name"
            Disable-ScheduledTask -TaskName $Name -ErrorAction Stop
        }
        if($State -eq "Enabled"){
            Write-Host "Enabling Scheduled Task $Name"
            Enable-ScheduledTask -TaskName $Name -ErrorAction Stop
        }
    }
    Catch [System.Exception]{
        if($psitem.Exception.Message -like "*The system cannot find the file specified*"){
            Write-Warning "Scheduled Task $name was not Found"
        }
        Else{
            Write-Warning "Unable to set $Name due to unhandled exception"
            Write-Warning $psitem.Exception.Message
        }
    }
    Catch{
        Write-Warning "Unable to run script for $name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace 
    }
}
Function Set-WinUtilService {
    <#
    
        .DESCRIPTION
        This function will change the startup type of services and start/stop them as needed

        .EXAMPLE

        Set-WinUtilService -Name "HomeGroupListener" -StartupType "Manual"
    
    #>   
    param (
        $Name,
        $StartupType
    )
    Try{
        Write-Host "Setting Services $Name to $StartupType"
        Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop

        if($StartupType -eq "Disabled"){
            Write-Host "Stopping $Name"
            Stop-Service -Name $Name -Force -ErrorAction Stop
        }
        if($StartupType -eq "Enabled"){
            Write-Host "Starting $Name"
            Start-Service -Name $Name -Force -ErrorAction Stop
        }
    }
    Catch [System.Exception]{
        if($psitem.Exception.Message -like "*Cannot find any service with service name*" -or 
           $psitem.Exception.Message -like "*was not found on computer*"){
            Write-Warning "Service $name was not Found"
        }
        Else{
            Write-Warning "Unable to set $Name due to unhandled exception"
            Write-Warning $psitem.Exception.Message
        }
    }
    Catch{
        Write-Warning "Unable to set $Name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
function Test-WinUtilPackageManager {
    <#
    
        .DESCRIPTION
        Checks for Winget or Choco depending on the paramater
    
    #>

    Param(
        [System.Management.Automation.SwitchParameter]$winget,
        [System.Management.Automation.SwitchParameter]$choco
    )

    if($winget){
        if (Test-Path ~\AppData\Local\Microsoft\WindowsApps\winget.exe) {
            return $true
        }
    }

    if($choco){
        if ((Get-Command -Name choco -ErrorAction Ignore) -and ($chocoVersion = (Get-Item "$env:ChocolateyInstall\choco.exe" -ErrorAction Ignore).VersionInfo.ProductVersion)){
            return $true
        }
    }

    return $false
}
Function Update-WinUtilProgramWinget {

    <#
    
        .DESCRIPTION
        This will update programs via Winget using a new powershell.exe instance to prevent the GUI from locking up.
    
    #>

    [ScriptBlock]$wingetinstall = {

        $host.ui.RawUI.WindowTitle = """Winget Install"""

        Start-Transcript $ENV:TEMP\winget-update.log -Append
        winget upgrade --all

        Pause
    }

    $global:WinGetInstall = Start-Process -Verb runas powershell -ArgumentList "-command invoke-command -scriptblock {$wingetinstall} -argumentlist '$($ProgramsToInstall -join ",")'" -PassThru

}
function Invoke-WPFButton {

    <#
    
        .DESCRIPTION
        Meant to make creating buttons easier. There is a section below in the gui that will assign this function to every button.
        This way you can dictate what each button does from this function. 
    
        Input will be the name of the button that is clicked. 
    #>
    
    Param ([string]$Button) 

    #Use this to get the name of the button
    #[System.Windows.MessageBox]::Show("$Button","Chris Titus Tech's Windows Utility","OK","Info")

    Switch -Wildcard ($Button){

        "WPFTab?BT" {Invoke-WPFTab $Button}
        "WPFinstall" {Invoke-WPFInstall}
        "WPFInstallUpgrade" {Invoke-WPFInstallUpgrade}
        "WPFdesktop" {Invoke-WPFPresets "Desktop"}
        "WPFlaptop" {Invoke-WPFPresets "laptop"}
        "WPFminimal" {Invoke-WPFPresets "minimal"}
        "WPFexport" {Invoke-WPFImpex -type "export"}
        "WPFimport" {Invoke-WPFImpex -type "import"}
        "WPFclear" {Invoke-WPFPresets -preset $null -imported $true}
        "WPFtweaksbutton" {Invoke-WPFtweaksbutton}
        "WPFAddUltPerf" {Invoke-WPFUltimatePerformance -State "Enabled"}
        "WPFRemoveUltPerf" {Invoke-WPFUltimatePerformance -State "Disabled"}
        "WPFToggleDarkMode" {Invoke-WPFDarkMode -DarkMoveEnabled $(Get-WinUtilDarkMode)}
        "WPFundoall" {Invoke-WPFundoall}
        "WPFFeatureInstall" {Invoke-WPFFeatureInstall}
        "WPFPanelDISM" {Invoke-WPFPanelDISM}
        "WPFPanelAutologin" {Invoke-WPFPanelAutologin}
        "WPFPanelcontrol" {Invoke-WPFControlPanel -Panel $button}
        "WPFPanelnetwork" {Invoke-WPFControlPanel -Panel $button}
        "WPFPanelpower" {Invoke-WPFControlPanel -Panel $button}
        "WPFPanelsound" {Invoke-WPFControlPanel -Panel $button}
        "WPFPanelsystem" {Invoke-WPFControlPanel -Panel $button}
        "WPFPaneluser" {Invoke-WPFControlPanel -Panel $button}
        "WPFUpdatesdefault" {Invoke-WPFUpdatesdefault}
        "WPFFixesUpdate" {Invoke-WPFFixesUpdate}
        "WPFUpdatesdisable" {Invoke-WPFUpdatesdisable}
        "WPFUpdatessecurity" {Invoke-WPFUpdatessecurity}


    }
}
function Invoke-WPFControlPanel {
        <#
    
        .DESCRIPTION
        Simple Switch for lagacy windows
    
    #>
    param($Panel)

    switch ($Panel){
        "WPFPanelcontrol" {cmd /c control}
        "WPFPanelnetwork" {cmd /c ncpa.cpl}
        "WPFPanelpower"   {cmd /c powercfg.cpl}
        "WPFPanelsound"   {cmd /c mmsys.cpl}
        "WPFPanelsystem"  {cmd /c sysdm.cpl}
        "WPFPaneluser"    {cmd /c "control userpasswords2"}
    }
}
Function Invoke-WPFDarkMode {
        <#
    
        .DESCRIPTION
        Sets Dark Mode on or off
    
    #>
    Param($DarkMoveEnabled)
    Try{
        if ($DarkMoveEnabled -eq $false){
            Write-Host "Enabling Dark Mode"
            $DarkMoveValue = 0
        }
        else {
            Write-Host "Disabling Dark Mode"
            $DarkMoveValue = 1
        }
    
        $Theme = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        Set-ItemProperty -Path $Theme -Name AppsUseLightTheme -Value $DarkMoveValue
        Set-ItemProperty -Path $Theme -Name SystemUsesLightTheme -Value $DarkMoveValue
    }
    Catch [System.Security.SecurityException] {
        Write-Warning "Unable to set $Path\$Name to $Value due to a Security Exception"
    }
    Catch [System.Management.Automation.ItemNotFoundException] {
        Write-Warning $psitem.Exception.ErrorRecord
    }
    Catch{
        Write-Warning "Unable to set $Name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
function Invoke-WPFFeatureInstall {
        <#
    
        .DESCRIPTION
        GUI Function to install Windows Features
    
    #>
    If ( $WPFFeaturesdotnet.IsChecked -eq $true ) {
        Enable-WindowsOptionalFeature -Online -FeatureName "NetFx4-AdvSrvs" -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName "NetFx3" -All -NoRestart
    }
    If ( $WPFFeatureshyperv.IsChecked -eq $true ) {
        Enable-WindowsOptionalFeature -Online -FeatureName "HypervisorPlatform" -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All" -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V" -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-Tools-All" -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-Management-PowerShell" -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-Hypervisor" -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-Services" -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-Management-Clients" -All -NoRestart
        cmd /c bcdedit /set hypervisorschedulertype classic
        Write-Host "HyperV is now installed and configured. Please Reboot before using."
    }
    If ( $WPFFeatureslegacymedia.IsChecked -eq $true ) {
        Enable-WindowsOptionalFeature -Online -FeatureName "WindowsMediaPlayer" -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName "MediaPlayback" -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName "DirectPlay" -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName "LegacyComponents" -All -NoRestart
    }
    If ( $WPFFeaturewsl.IsChecked -eq $true ) {
        Enable-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform" -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux" -All -NoRestart
        Write-Host "WSL is now installed and configured. Please Reboot before using."
    }
    If ( $WPFFeaturenfs.IsChecked -eq $true ) {
        Enable-WindowsOptionalFeature -Online -FeatureName "ServicesForNFS-ClientOnly" -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName "ClientForNFS-Infrastructure" -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName "NFS-Administration" -All -NoRestart
        nfsadmin client stop
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ClientForNFS\CurrentVersion\Default" -Name "AnonymousUID" -Type DWord -Value 0
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ClientForNFS\CurrentVersion\Default" -Name "AnonymousGID" -Type DWord -Value 0
        nfsadmin client start
        nfsadmin client localhost config fileaccess=755 SecFlavors=+sys -krb5 -krb5i
        Write-Host "NFS is now setup for user based NFS mounts"
    }
    $ButtonType = [System.Windows.MessageBoxButton]::OK
    $MessageboxTitle = "All features are now installed "
    $Messageboxbody = ("Done")
    $MessageIcon = [System.Windows.MessageBoxImage]::Information

    [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)

    Write-Host "================================="
    Write-Host "---  Features are Installed   ---"
    Write-Host "================================="
}
function Invoke-WPFFixesUpdate {

    <#
    
        .DESCRIPTION
        PlaceHolder
    
    #>

    ### Reset Windows Update Script - reregister dlls, services, and remove registry entires.
    Write-Host "1. Stopping Windows Update Services..."
    Stop-Service -Name BITS
    Stop-Service -Name wuauserv
    Stop-Service -Name appidsvc
    Stop-Service -Name cryptsvc

    Write-Host "2. Remove QMGR Data file..."
    Remove-Item "$env:allusersprofile\Application Data\Microsoft\Network\Downloader\qmgr*.dat" -ErrorAction SilentlyContinue

    Write-Host "3. Renaming the Software Distribution and CatRoot Folder..."
    Rename-Item $env:systemroot\SoftwareDistribution SoftwareDistribution.bak -ErrorAction SilentlyContinue
    Rename-Item $env:systemroot\System32\Catroot2 catroot2.bak -ErrorAction SilentlyContinue

    Write-Host "4. Removing old Windows Update log..."
    Remove-Item $env:systemroot\WindowsUpdate.log -ErrorAction SilentlyContinue

    Write-Host "5. Resetting the Windows Update Services to defualt settings..."
    "sc.exe sdset bits D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)"
    "sc.exe sdset wuauserv D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)"
    Set-Location $env:systemroot\system32

    Write-Host "6. Registering some DLLs..."
    regsvr32.exe /s atl.dll
    regsvr32.exe /s urlmon.dll
    regsvr32.exe /s mshtml.dll
    regsvr32.exe /s shdocvw.dll
    regsvr32.exe /s browseui.dll
    regsvr32.exe /s jscript.dll
    regsvr32.exe /s vbscript.dll
    regsvr32.exe /s scrrun.dll
    regsvr32.exe /s msxml.dll
    regsvr32.exe /s msxml3.dll
    regsvr32.exe /s msxml6.dll
    regsvr32.exe /s actxprxy.dll
    regsvr32.exe /s softpub.dll
    regsvr32.exe /s wintrust.dll
    regsvr32.exe /s dssenh.dll
    regsvr32.exe /s rsaenh.dll
    regsvr32.exe /s gpkcsp.dll
    regsvr32.exe /s sccbase.dll
    regsvr32.exe /s slbcsp.dll
    regsvr32.exe /s cryptdlg.dll
    regsvr32.exe /s oleaut32.dll
    regsvr32.exe /s ole32.dll
    regsvr32.exe /s shell32.dll
    regsvr32.exe /s initpki.dll
    regsvr32.exe /s wuapi.dll
    regsvr32.exe /s wuaueng.dll
    regsvr32.exe /s wuaueng1.dll
    regsvr32.exe /s wucltui.dll
    regsvr32.exe /s wups.dll
    regsvr32.exe /s wups2.dll
    regsvr32.exe /s wuweb.dll
    regsvr32.exe /s qmgr.dll
    regsvr32.exe /s qmgrprxy.dll
    regsvr32.exe /s wucltux.dll
    regsvr32.exe /s muweb.dll
    regsvr32.exe /s wuwebv.dll

    Write-Host "7) Removing WSUS client settings..."
    REG DELETE "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" /v AccountDomainSid /f
    REG DELETE "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" /v PingID /f
    REG DELETE "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" /v SusClientId /f

    Write-Host "8) Resetting the WinSock..."
    netsh winsock reset
    netsh winhttp reset proxy
    netsh int ip reset

    Write-Host "9) Delete all BITS jobs..."
    Get-BitsTransfer | Remove-BitsTransfer

    Write-Host "10) Attempting to install the Windows Update Agent..."
    If ([System.Environment]::Is64BitOperatingSystem) {
        wusa Windows8-RT-KB2937636-x64 /quiet
    }
    else {
        wusa Windows8-RT-KB2937636-x86 /quiet
    }

    Write-Host "11) Starting Windows Update Services..."
    Start-Service -Name BITS
    Start-Service -Name wuauserv
    Start-Service -Name appidsvc
    Start-Service -Name cryptsvc

    Write-Host "12) Forcing discovery..."
    wuauclt /resetauthorization /detectnow

    Write-Host "Process complete. Please reboot your computer."

    $ButtonType = [System.Windows.MessageBoxButton]::OK
    $MessageboxTitle = "Reset Windows Update "
    $Messageboxbody = ("Stock settings loaded.`n Please reboot your computer")
    $MessageIcon = [System.Windows.MessageBoxImage]::Information

    [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)
    Write-Host "================================="
    Write-Host "-- Reset ALL Updates to Factory -"
    Write-Host "================================="
}
Function Invoke-WPFFormVariables {
    <#
    
        .DESCRIPTION
        PlaceHolder
    
    #>
    #If ($global:ReadmeDisplay -ne $true) { Write-Host "If you need to reference this display again, run Get-FormVariables" -ForegroundColor Yellow; $global:ReadmeDisplay = $true }


    Write-Host ""
    Write-Host "    CCCCCCCCCCCCCTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT   "
    Write-Host " CCC::::::::::::CT:::::::::::::::::::::TT:::::::::::::::::::::T   "
    Write-Host "CC:::::::::::::::CT:::::::::::::::::::::TT:::::::::::::::::::::T  "
    Write-Host "C:::::CCCCCCCC::::CT:::::TT:::::::TT:::::TT:::::TT:::::::TT:::::T "
    Write-Host "C:::::C       CCCCCCTTTTTT  T:::::T  TTTTTTTTTTTT  T:::::T  TTTTTT"
    Write-Host "C:::::C                     T:::::T                T:::::T        "
    Write-Host "C:::::C                     T:::::T                T:::::T        "
    Write-Host "C:::::C                     T:::::T                T:::::T        "
    Write-Host "C:::::C                     T:::::T                T:::::T        "
    Write-Host "C:::::C                     T:::::T                T:::::T        "
    Write-Host "C:::::C                     T:::::T                T:::::T        "
    Write-Host "C:::::C       CCCCCC        T:::::T                T:::::T        "
    Write-Host "C:::::CCCCCCCC::::C      TT:::::::TT            TT:::::::TT       "
    Write-Host "CC:::::::::::::::C       T:::::::::T            T:::::::::T       "
    Write-Host "CCC::::::::::::C         T:::::::::T            T:::::::::T       "
    Write-Host "  CCCCCCCCCCCCC          TTTTTTTTTTT            TTTTTTTTTTT       "
    Write-Host ""
    Write-Host "====Chris Titus Tech====="
    Write-Host "=====Windows Toolbox====="


    #====DEBUG GUI Elements====

    #Write-Host "Found the following interactable elements from our form" -ForegroundColor Cyan
    #get-variable WPF*
}
function Invoke-WPFImpex {
    <#
    
        .DESCRIPTION
        This function handles importing and exporting of the checkboxes checked for the tweaks section

        .EXAMPLE

        Invoke-WPFImpex -type "export"
    
    #>
    param($type)

    if ($type -eq "export"){
        $FileBrowser = New-Object System.Windows.Forms.SaveFileDialog
    }
    if ($type -eq "import"){
        $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog 
    }

    $FileBrowser.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    $FileBrowser.Filter = "JSON Files (*.json)|*.json"
    $FileBrowser.ShowDialog() | Out-Null

    if($FileBrowser.FileName -eq ""){
        return
    }
    
    if ($type -eq "export"){
        $jsonFile = Get-WinUtilCheckBoxes WPFTweaks -unCheck $false
        $jsonFile | ConvertTo-Json | Out-File $FileBrowser.FileName -Force
    }
    if ($type -eq "import"){
        $jsonFile = Get-Content $FileBrowser.FileName | ConvertFrom-Json
        Invoke-WPFPresets -preset $jsonFile -imported $true
    }
}
function Invoke-WPFInstall {
    <#
    
        .DESCRIPTION
        PlaceHolder
    
    #>

    if($sync.ProcessRunning){
        $msg = "Install process is currently running."
        [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $WingetInstall = Get-WinUtilCheckBoxes -Group "WPFInstall"

    if ($wingetinstall.Count -eq 0) {
        $WarningMsg = "Please select the program(s) to install"
        [System.Windows.MessageBox]::Show($WarningMsg, $AppTitle, [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    Invoke-WPFRunspace -ArgumentList $WingetInstall -scriptblock {
        param($WingetInstall)
        try{
            $sync.ProcessRunning = $true

            # Ensure winget is installed
            Install-WinUtilWinget

            # Install all winget programs in new window
            Install-WinUtilProgramWinget -ProgramsToInstall $WingetInstall

            $ButtonType = [System.Windows.MessageBoxButton]::OK
            $MessageboxTitle = "Installs are Finished "
            $Messageboxbody = ("Done")
            $MessageIcon = [System.Windows.MessageBoxImage]::Information
        
            [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)

            Write-Host "==========================================="
            Write-Host "--      Installs have finished          ---"
            Write-Host "==========================================="
        }
        Catch {
            Write-Host "==========================================="
            Write-Host "--      Winget failed to install        ---"
            Write-Host "==========================================="
        }
        $sync.ProcessRunning = $False
    }
}
function Invoke-WPFInstallUpgrade {
    <#
    
        .DESCRIPTION
        PlaceHolder
    
    #>
    if(!(Test-WinUtilPackageManager -winget)){
        Write-Host "==========================================="
        Write-Host "--       Winget is not installed        ---"
        Write-Host "==========================================="
        return
    }

    if(Get-WinUtilInstallerProcess -Process $global:WinGetInstall){
        $msg = "Install process is currently running. Please check for a powershell window labled 'Winget Install'"
        [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    Update-WinUtilProgramWinget

    Write-Host "==========================================="
    Write-Host "--           Updates started            ---"
    Write-Host "-- You can close this window if desired ---"
    Write-Host "==========================================="
}
function Invoke-WPFPanelAutologin {
    <#
    
        .DESCRIPTION
        PlaceHolder
    
    #>
    curl.exe -ss "https://live.sysinternals.com/Autologon.exe" -o $env:temp\autologin.exe # Official Microsoft recommendation https://learn.microsoft.com/en-us/sysinternals/downloads/autologon
    cmd /c $env:temp\autologin.exe
}
function Invoke-WPFPanelDISM {
    <#
    
        .DESCRIPTION
        PlaceHolder
    
    #>
    Start-Process PowerShell -ArgumentList "Write-Host '(1/4) Chkdsk' -ForegroundColor Green; Chkdsk /scan;
    Write-Host '`n(2/4) SFC - 1st scan' -ForegroundColor Green; sfc /scannow;
    Write-Host '`n(3/4) DISM' -ForegroundColor Green; DISM /Online /Cleanup-Image /Restorehealth;
    Write-Host '`n(4/4) SFC - 2nd scan' -ForegroundColor Green; sfc /scannow;
    Read-Host '`nPress Enter to Continue'" -verb runas
}
function Invoke-WPFPresets {
    <#

        .DESCRIPTION
        Meant to make settings presets easier in the tweaks tab. Will pull the data from config/preset.json

    #>

    param(
        $preset,
        [bool]$imported = $false
    )
    if($imported -eq $true){
        $CheckBoxesToCheck = $preset
    }
    Else{
        $CheckBoxesToCheck = $sync.configs.preset.$preset
    }

    #Uncheck all
    get-variable | Where-Object {$_.name -like "*tweaks*"} | ForEach-Object {
        if ($psitem.value.gettype().name -eq "CheckBox"){
            $CheckBox = Get-Variable $psitem.Name
            if ($CheckBoxesToCheck -contains $CheckBox.name){
                $checkbox.value.ischecked = $true
            }
            else{$checkbox.value.ischecked = $false}
        }
    }

}
function Invoke-WPFRunspace {

    <#
    
        .DESCRIPTION
        Simple function to make it easier to invoke a runspace from inside the script. 

        .EXAMPLE

        $params = @{
            ScriptBlock = $sync.ScriptsInstallPrograms
            ArgumentList = "Installadvancedip,Installbitwarden"
            Verbose = $true
        }

        Invoke-WPFRunspace @params
    
    #>

    [CmdletBinding()]
    Param (
        $ScriptBlock,
        $ArgumentList
    ) 

    #Configure max thread count for RunspacePool.
    $maxthreads = [int]$env:NUMBER_OF_PROCESSORS

    #Create a new session state for parsing variables ie hashtable into our runspace.
    $hashVars = New-object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'sync',$sync,$Null
    $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

    #Add the variable to the RunspacePool sessionstate
    $InitialSessionState.Variables.Add($hashVars)

    #Add functions
    $functions = Get-ChildItem function:\ | Where-Object {$_.name -like "*winutil*" -or $_.name -like "*WPF*"}
    foreach ($function in $functions){
      $functionDefinition = Get-Content function:\$($function.name)
      $functionEntry = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $($function.name), $functionDefinition
        
      # And add it to the iss object
      $initialSessionState.Commands.Add($functionEntry)
    }

    #Create our runspace pool. We are entering three parameters here min thread count, max thread count and host machine of where these runspaces should be made.
    $script:runspace = [runspacefactory]::CreateRunspacePool(1,$maxthreads,$InitialSessionState, $Host)


    #Crate a PowerShell instance.
    $script:powershell = [powershell]::Create()

    #Open a RunspacePool instance.
    $script:runspace.Open()

    #Add Scriptblock and Arguments to runspace
    $script:powershell.AddScript($ScriptBlock)
    $script:powershell.AddArgument($ArgumentList)
    $script:powershell.RunspacePool = $script:runspace
    
    #Run our RunspacePool.
    $script:handle = $script:powershell.BeginInvoke()

    #Cleanup our RunspacePool threads when they are complete ie. GC.
    if ($script:handle.IsCompleted)
    {
        $script:powershell.EndInvoke($script:handle)
        $script:powershell.Dispose()
        $script:runspace.Dispose()
        $script:runspace.Close()
        [System.GC]::Collect()
    }
}
function Invoke-WPFTab {

    <#
    
        .DESCRIPTION
        Sole purpose of this fuction reduce duplicated code for switching between tabs. 
    
    #>

    Param ($ClickedTab)
    $Tabs = Get-Variable WPFTab?BT
    $TabNav = Get-Variable WPFTabNav
    $x = [int]($ClickedTab -replace "WPFTab","" -replace "BT","") - 1

    0..($Tabs.Count -1 ) | ForEach-Object {
        
        if ($x -eq $psitem){
            $TabNav.value.Items[$psitem].IsSelected = $true
        }
        else{
            $TabNav.value.Items[$psitem].IsSelected = $false
        }
    }
}
function Invoke-WPFtweaksbutton {
  <#
    
        .DESCRIPTION
        PlaceHolder
    
    #>

  if($sync.ProcessRunning){
    $msg = "Install process is currently running."
    [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    return
}

  $Tweaks = Get-WinUtilCheckBoxes -Group "WPFTweaks"

  Set-WinUtilDNS -DNSProvider $WPFchangedns.text

  Invoke-WPFRunspace -ArgumentList $Tweaks -ScriptBlock {
    param($Tweaks)

    $sync.ProcessRunning = $true

    Foreach ($tweak in $tweaks){
        Invoke-WinUtilTweaks $tweak
    }

    $sync.ProcessRunning = $false
    Write-Host "================================="
    Write-Host "--     Tweaks are Finished    ---"
    Write-Host "================================="

    $ButtonType = [System.Windows.MessageBoxButton]::OK
    $MessageboxTitle = "Tweaks are Finished "
    $Messageboxbody = ("Done")
    $MessageIcon = [System.Windows.MessageBoxImage]::Information

    [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)
  }
}
Function Invoke-WPFUltimatePerformance {
    <#
    
        .DESCRIPTION
        PlaceHolder
    
    #>
    param($State)
    Try{
        $guid = "e9a42b02-d5df-448d-aa00-03f14749eb61"

        if($state -eq "Enabled"){
            Write-Host "Adding Ultimate Performance Profile"
            [scriptblock]$command = {powercfg -duplicatescheme $guid}
            
        }
        if($state -eq "Disabled"){
            Write-Host "Removing Ultimate Performance Profile"
            [scriptblock]$command = {powercfg -delete $guid}
        }
        
        $output = Invoke-Command -ScriptBlock $command
        if($output -like "*does not exist*"){
            throw [GenericException]::new('Failed to modify profile')
        }
    }
    Catch{
        Write-Warning $psitem.Exception.Message
    }
}
function Invoke-WPFundoall {
    <#
    
        .DESCRIPTION
        PlaceHolder
    
    #>

    if($sync.ProcessRunning){
        $msg = "Install process is currently running."
        [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    
      $Tweaks = Get-WinUtilCheckBoxes -Group "WPFTweaks"
        
      Invoke-WPFRunspace -ArgumentList $Tweaks -ScriptBlock {
        param($Tweaks)
    
        $sync.ProcessRunning = $true
    
        Foreach ($tweak in $tweaks){
            Invoke-WinUtilTweaks $tweak -undo $true
        }
    
        $sync.ProcessRunning = $false
        Write-Host "=================================="
        Write-Host "---  Undo Tweaks are Finished  ---"
        Write-Host "=================================="
    
        $ButtonType = [System.Windows.MessageBoxButton]::OK
        $MessageboxTitle = "Tweaks are Finished "
        $Messageboxbody = ("Done")
        $MessageIcon = [System.Windows.MessageBoxImage]::Information
    
        [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)
      }

<#

    Write-Host "Creating Restore Point in case something bad happens"
    Enable-ComputerRestore -Drive "$env:SystemDrive"
    Checkpoint-Computer -Description "RestorePoint1" -RestorePointType "MODIFY_SETTINGS"

    Write-Host "Enabling Telemetry..."
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Type DWord -Value 1
    Write-Host "Enabling Wi-Fi Sense"
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Name "Value" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots" -Name "Value" -Type DWord -Value 1
    Write-Host "Enabling Application suggestions..."
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "ContentDeliveryAllowed" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "OemPreInstalledAppsEnabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "PreInstalledAppsEnabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "PreInstalledAppsEverEnabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SilentInstalledAppsEnabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338387Enabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338388Enabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353698Enabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Type DWord -Value 1
    If (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent") {
        Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Recurse -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Type DWord -Value 0
    Write-Host "Enabling Activity History..."
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "UploadUserActivities" -Type DWord -Value 1
    Write-Host "Enable Location Tracking..."
    If (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location") {
        Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Recurse -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Type String -Value "Allow"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" -Name "SensorPermissionState" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration" -Name "Status" -Type DWord -Value 1
    Write-Host "Enabling automatic Maps updates..."
    Set-ItemProperty -Path "HKLM:\SYSTEM\Maps" -Name "AutoUpdateEnabled" -Type DWord -Value 1
    Write-Host "Enabling Feedback..."
    If (Test-Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules") {
        Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" -Recurse -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -Type DWord -Value 0
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Type DWord -Value 0
    Write-Host "Enabling Tailored Experiences..."
    If (Test-Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent") {
        Remove-Item -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Recurse -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableTailoredExperiencesWithDiagnosticData" -Type DWord -Value 0
    Write-Host "Disabling Advertising ID..."
    If (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo") {
        Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Recurse -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -Type DWord -Value 0
    Write-Host "Allow Error reporting..."
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Type DWord -Value 0
    Write-Host "Allowing Diagnostics Tracking Service..."
    Stop-Service "DiagTrack" -WarningAction SilentlyContinue
    Set-Service "DiagTrack" -StartupType Manual
    Write-Host "Allowing WAP Push Service..."
    Stop-Service "dmwappushservice" -WarningAction SilentlyContinue
    Set-Service "dmwappushservice" -StartupType Manual
    Write-Host "Allowing Home Groups services..."
    Stop-Service "HomeGroupListener" -WarningAction SilentlyContinue
    Set-Service "HomeGroupListener" -StartupType Manual
    Stop-Service "HomeGroupProvider" -WarningAction SilentlyContinue
    Set-Service "HomeGroupProvider" -StartupType Manual
    Write-Host "Enabling Storage Sense..."
    New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" | Out-Null
    Write-Host "Allowing Superfetch service..."
    Stop-Service "SysMain" -WarningAction SilentlyContinue
    Set-Service "SysMain" -StartupType Manual
    Write-Host "Setting BIOS time to Local Time instead of UTC..."
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" -Name "RealTimeIsUniversal" -Type DWord -Value 0
    Write-Host "Enabling Hibernation..."
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Session Manager\Power" -Name "HibernteEnabled" -Type Dword -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -Name "ShowHibernateOption" -Type Dword -Value 1
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreen" -ErrorAction SilentlyContinue

    Write-Host "Hiding file operations details..."
    If (Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager") {
        Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Recurse -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Name "EnthusiastMode" -Type DWord -Value 0
    Write-Host "Showing Task View button..."
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Name "PeopleBand" -Type DWord -Value 1

    Write-Host "Changing default Explorer view to Quick Access..."
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Type DWord -Value 0

    Write-Host "Unrestricting AutoLogger directory"
    $autoLoggerDir = "$env:PROGRAMDATA\Microsoft\Diagnosis\ETLLogs\AutoLogger"
    icacls $autoLoggerDir /grant:r SYSTEM:`(OI`)`(CI`)F | Out-Null

    Write-Host "Enabling and starting Diagnostics Tracking Service"
    Set-Service "DiagTrack" -StartupType Automatic
    Start-Service "DiagTrack"

    Write-Host "Hiding known file extensions"
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Type DWord -Value 1

    Write-Host "Reset Local Group Policies to Stock Defaults"
    # cmd /c secedit /configure /cfg %windir%\inf\defltbase.inf /db defltbase.sdb /verbose
    cmd /c RD /S /Q "%WinDir%\System32\GroupPolicyUsers"
    cmd /c RD /S /Q "%WinDir%\System32\GroupPolicy"
    cmd /c gpupdate /force
    # Considered using Invoke-GPUpdate but requires module most people won't have installed

    Write-Host "Adjusting visual effects for appearance..."
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Type String -Value 1
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Type String -Value 400
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Type Binary -Value ([byte[]](158, 30, 7, 128, 18, 0, 0, 0))
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Type String -Value 1
    Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewAlphaSelect" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewShadow" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Type DWord -Value 3
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "EnableAeroPeek" -Type DWord -Value 1
    Remove-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "HungAppTimeout" -ErrorAction SilentlyContinue
    Write-Host "Restoring Clipboard History..."
    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Clipboard" -Name "EnableClipboardHistory" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "AllowClipboardHistory" -ErrorAction SilentlyContinue
    Write-Host "Enabling Notifications and Action Center"
    Remove-Item -Path HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer -Force
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "ToastEnabled"
    Write-Host "Restoring Default Right Click Menu Layout"
    Remove-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Confirm:$false -Force

    Write-Host "Reset News and Interests"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Type DWord -Value 1
    # Remove "News and Interest" from taskbar
    Set-ItemProperty -Path  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Type DWord -Value 0
    Write-Host "Done - Reverted to Stock Settings"

    Write-Host "Essential Undo Completed"

    $ButtonType = [System.Windows.MessageBoxButton]::OK
    $MessageboxTitle = "Undo All"
    $Messageboxbody = ("Done")
    $MessageIcon = [System.Windows.MessageBoxImage]::Information

    [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)

    Write-Host "================================="
    Write-Host "---   Undo All is Finished    ---"
    Write-Host "================================="
    #>
}
function Invoke-WPFUpdatesdefault {
    <#
    
        .DESCRIPTION
        PlaceHolder
    
    #>
    If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Type DWord -Value 0
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Type DWord -Value 3
    If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config")) {
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Type DWord -Value 1

    $services = @(
        "BITS"
        "wuauserv"
    )

    foreach ($service in $services) {
        # -ErrorAction SilentlyContinue is so it doesn't write an error to stdout if a service doesn't exist

        Write-Host "Setting $service StartupType to Automatic"
        Get-Service -Name $service -ErrorAction SilentlyContinue | Set-Service -StartupType Automatic
    }
    Write-Host "Enabling driver offering through Windows Update..."
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DriverUpdateWizardWuSearchEnabled" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue
    Write-Host "Enabling Windows Update automatic restart..."
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUPowerManagement" -ErrorAction SilentlyContinue
    Write-Host "Enabled driver offering through Windows Update"
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "BranchReadinessLevel" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferFeatureUpdatesPeriodInDays" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferQualityUpdatesPeriodInDays " -ErrorAction SilentlyContinue
    Write-Host "================================="
    Write-Host "---  Updates Set to Default   ---"
    Write-Host "================================="
}
function Invoke-WPFUpdatesdisable {
    <#
    
        .DESCRIPTION
        PlaceHolder
    
    #>
    If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Type DWord -Value 1
    If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config")) {
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Type DWord -Value 0

    $services = @(
        "BITS"
        "wuauserv"
    )

    foreach ($service in $services) {
        # -ErrorAction SilentlyContinue is so it doesn't write an error to stdout if a service doesn't exist

        Write-Host "Setting $service StartupType to Disabled"
        Get-Service -Name $service -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled
    }
    Write-Host "================================="
    Write-Host "---  Updates ARE DISABLED     ---"
    Write-Host "================================="
}
function Invoke-WPFUpdatessecurity {
    <#
    
        .DESCRIPTION
        PlaceHolder
    
    #>
    Write-Host "Disabling driver offering through Windows Update..."
        If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata")) {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Type DWord -Value 1
        If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching")) {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -Type DWord -Value 1
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -Type DWord -Value 1
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DriverUpdateWizardWuSearchEnabled" -Type DWord -Value 0
        If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate")) {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -Type DWord -Value 1
        Write-Host "Disabling Windows Update automatic restart..."
        If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU")) {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -Type DWord -Value 1
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUPowerManagement" -Type DWord -Value 0
        Write-Host "Disabled driver offering through Windows Update"
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "BranchReadinessLevel" -Type DWord -Value 20
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferFeatureUpdatesPeriodInDays" -Type DWord -Value 365
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferQualityUpdatesPeriodInDays " -Type DWord -Value 4

        $ButtonType = [System.Windows.MessageBoxButton]::OK
        $MessageboxTitle = "Set Security Updates"
        $Messageboxbody = ("Recommended Update settings loaded")
        $MessageIcon = [System.Windows.MessageBoxImage]::Information

        [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)
        Write-Host "================================="
        Write-Host "-- Updates Set to Recommended ---"
        Write-Host "================================="
}
$inputXML = '<Window x:Class="WinUtility.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:local="clr-namespace:WinUtility"
        mc:Ignorable="d"
        Background="#777777"
        WindowStartupLocation="CenterScreen"
        Title="Chris Titus Tech''s Windows Utility" Height="800" Width="1200">
    <Window.Resources>
        <Style x:Key="ToggleSwitchStyle" TargetType="CheckBox">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <StackPanel>
                            <Grid>
                                <Border Width="45" 
                                        Height="20"
                                        Background="#555555" 
                                        CornerRadius="10" 
                                        Margin="5,0"
                                />
                                <Border Name="ToggleSwitchButton"
                                        Width="25" 
                                        Height="25"
                                        Background="Black" 
                                        CornerRadius="12.5" 
                                        HorizontalAlignment="Left"
                                />
                                <ContentPresenter Name="ToggleSwitchContent"
                                                  Margin="10,0,0,0"
                                                  Content="{TemplateBinding Content}"
                                                  VerticalAlignment="Center"
                                />
                            </Grid>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="false">
                                <Trigger.ExitActions>
                                    <RemoveStoryboard BeginStoryboardName="ToggleSwitchLeft" />
                                    <BeginStoryboard x:Name="ToggleSwitchRight">
                                        <Storyboard>
                                            <ThicknessAnimation Storyboard.TargetProperty="Margin"
                                                    Storyboard.TargetName="ToggleSwitchButton"
                                                    Duration="0:0:0:0"
                                                    From="0,0,0,0"
                                                    To="28,0,0,0">
                                            </ThicknessAnimation>
                                        </Storyboard>
                                    </BeginStoryboard>
                                </Trigger.ExitActions>
                                <Setter TargetName="ToggleSwitchButton"
                                        Property="Background"
                                        Value="#fff9f4f4"
                                />
                            </Trigger>
                            <Trigger Property="IsChecked" Value="true">
                                <Trigger.ExitActions>
                                    <RemoveStoryboard BeginStoryboardName="ToggleSwitchRight" />
                                    <BeginStoryboard x:Name="ToggleSwitchLeft">
                                        <Storyboard>
                                            <ThicknessAnimation Storyboard.TargetProperty="Margin"
                                                    Storyboard.TargetName="ToggleSwitchButton"
                                                    Duration="0:0:0:0"
                                                    From="28,0,0,0"
                                                    To="0,0,0,0">
                                            </ThicknessAnimation>
                                        </Storyboard>
                                    </BeginStoryboard>
                                </Trigger.ExitActions>
                                <Setter TargetName="ToggleSwitchButton"
                                        Property="Background"
                                        Value="#ff060600"
                                />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border Name="dummy" Grid.Column="0" Grid.Row="0">
        <Viewbox Stretch="Uniform" VerticalAlignment="Top">
            <Grid Background="#777777" ShowGridLines="False" Name="MainGrid">
                <Grid.RowDefinitions>
                    <RowDefinition Height=".1*"/>
                    <RowDefinition Height=".9*"/>
                </Grid.RowDefinitions>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <DockPanel Background="#777777" SnapsToDevicePixels="True" Grid.Row="0" Width="1100">
                    <Image Height="50" Width="100" Name="Icon" SnapsToDevicePixels="True" Source="https://christitus.com/images/logo-full.png" Margin="0,10,0,10"/>
                    <Button Content="Install" HorizontalAlignment="Left" Height="40" Width="100" Background="#222222" BorderThickness="0,0,0,0" FontWeight="Bold" Foreground="#ffffff" Name="Tab1BT"/>
                    <Button Content="Tweaks" HorizontalAlignment="Left" Height="40" Width="100" Background="#333333" BorderThickness="0,0,0,0" FontWeight="Bold" Foreground="#ffffff" Name="Tab2BT"/>
                    <Button Content="Config" HorizontalAlignment="Left" Height="40" Width="100" Background="#444444" BorderThickness="0,0,0,0" FontWeight="Bold" Foreground="#ffffff" Name="Tab3BT"/>
                    <Button Content="Updates" HorizontalAlignment="Left" Height="40" Width="100" Background="#555555" BorderThickness="0,0,0,0" FontWeight="Bold" Foreground="#ffffff" Name="Tab4BT"/>
                </DockPanel>
                <TabControl Grid.Row="1" Padding="-1" Name="TabNav" Background="#222222">
                    <TabItem Header="Install" Visibility="Collapsed" Name="Tab1">
                        <Grid Background="#222222">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <StackPanel Background="#777777" SnapsToDevicePixels="True" Grid.Column="0" Margin="10">
                                <Label Content="Browsers" FontSize="16" Margin="5,0"/>
                                <CheckBox Name="Installbrave" Content="Brave" Margin="5,0"/>
                                
                                <CheckBox Name="Installchromium" Content="Chromium" Margin="5,0"/>
                                <CheckBox Name="Installedge" Content="Edge" Margin="5,0"/>
                                <CheckBox Name="Installlibrewolf" Content="LibreWolf" Margin="5,0"/>
                                <CheckBox Name="Installtor" Content="Tor Browser" Margin="5,0"/>
                                <CheckBox Name="Installvivaldi" Content="Vivaldi" Margin="5,0"/>
                                <CheckBox Name="Installwaterfox" Content="Waterfox" Margin="5,0"/>
                                <Label Content="Communications" FontSize="16" Margin="5,0"/>
                                <CheckBox Name="Installdiscord" Content="Discord" Margin="5,0"/>
                                <CheckBox Name="Installhexchat" Content="Hexchat" Margin="5,0"/>
                                <CheckBox Name="Installjami" Content="Jami" Margin="5,0"/>
                                <CheckBox Name="Installmatrix" Content="Matrix" Margin="5,0"/>
                                <CheckBox Name="Installsignal" Content="Signal" Margin="5,0"/>
                                <CheckBox Name="Installskype" Content="Skype" Margin="5,0"/>
                                <CheckBox Name="Installslack" Content="Slack" Margin="5,0"/>
                                <CheckBox Name="Installtelegram" Content="Telegram" Margin="5,0"/>
                                <CheckBox Name="Installviber" Content="Viber" Margin="5,0"/>
                                <CheckBox Name="Installzoom" Content="Zoom" Margin="5,0"/>
                            </StackPanel>
                            <StackPanel Background="#777777" SnapsToDevicePixels="True" Grid.Column="1" Margin="10">
                                <Label Content="Development" FontSize="16" Margin="5,0"/>
                                <CheckBox Name="Installatom" Content="Atom" Margin="5,0"/>
                                <CheckBox Name="Installgit" Content="Git" Margin="5,0"/>
                                <CheckBox Name="Installgithubdesktop" Content="GitHub Desktop" Margin="5,0"/>
                                <CheckBox Name="Installjava8" Content="OpenJDK Java 8" Margin="5,0"/>
                                <CheckBox Name="Installjava16" Content="OpenJDK Java 16" Margin="5,0"/>
                                <CheckBox Name="Installjava18" Content="Oracle Java 18" Margin="5,0"/>
                                <CheckBox Name="Installjetbrains" Content="Jetbrains Toolbox" Margin="5,0"/>
                                <CheckBox Name="Installnodejs" Content="NodeJS" Margin="5,0"/>
                                <CheckBox Name="Installnodejslts" Content="NodeJS LTS" Margin="5,0"/>
                                <CheckBox Name="Installpython3" Content="Python3" Margin="5,0"/>
                                <CheckBox Name="Installrustlang" Content="Rust" Margin="5,0"/>
                                <CheckBox Name="Installgolang" Content="GoLang" Margin="5,0"/>
                                <CheckBox Name="Installsublime" Content="Sublime" Margin="5,0"/>
                                <CheckBox Name="Installunity" Content="Unity Game Engine" Margin="5,0"/>
                                <CheckBox Name="Installvisualstudio" Content="Visual Studio 2022" Margin="5,0"/>
                                <CheckBox Name="Installvscode" Content="VS Code" Margin="5,0"/>
                                <CheckBox Name="Installvscodium" Content="VS Codium" Margin="5,0"/>

                                <Label Content="Document" FontSize="16" Margin="5,0"/>
                                
                                <CheckBox Name="Installfoxpdf" Content="Foxit PDF" Margin="5,0"/>
                                <CheckBox Name="Installjoplin" Content="Joplin (FOSS Notes)" Margin="5,0"/>
                                <CheckBox Name="Installobsidian" Content="Obsidian" Margin="5,0"/>
                                <CheckBox Name="Installonlyoffice" Content="ONLYOffice Desktop" Margin="5,0"/>
                                <CheckBox Name="Installopenoffice" Content="Apache OpenOffice" Margin="5,0"/>
                                <CheckBox Name="Installsumatra" Content="Sumatra PDF" Margin="5,0"/>
                                <CheckBox Name="Installwinmerge" Content="WinMerge" Margin="5,0"/>

                            </StackPanel>
                            <StackPanel Background="#777777" SnapsToDevicePixels="True" Grid.Column="2" Margin="10">

							<Label Content="Utilities" FontSize="16" Margin="5,0"/>
                                
                                <CheckBox Name="Installalacritty" Content="Alacritty Terminal" Margin="5,0"/>
                                <CheckBox Name="Installanydesk" Content="AnyDesk" Margin="5,0"/>
                                <CheckBox Name="Installautohotkey" Content="AutoHotkey" Margin="5,0"/>
                                <CheckBox Name="Installbitwarden" Content="Bitwarden" Margin="5,0"/>
                                <CheckBox Name="Installcpuz" Content="CPU-Z" Margin="5,0"/>
                                <CheckBox Name="Installetcher" Content="Etcher USB Creator" Margin="5,0"/>
                                <CheckBox Name="Installesearch" Content="Everything Search" Margin="5,0"/>
                                <CheckBox Name="Installflux" Content="f.lux Redshift" Margin="5,0"/>
                                <CheckBox Name="Installgpuz" Content="GPU-Z" Margin="5,0"/>
                                <CheckBox Name="Installglaryutilities" Content="Glary Utilities" Margin="5,0"/>
                                <CheckBox Name="Installhwinfo" Content="HWInfo" Margin="5,0"/>
                                <CheckBox Name="Installidm" Content="Internet Download Manager" Margin="5,0"/>
                                <CheckBox Name="Installjdownloader" Content="J Download Manager" Margin="5,0"/>
                                <CheckBox Name="Installkeepass" Content="KeePassXC" Margin="5,0"/>
                                <CheckBox Name="Installmalwarebytes" Content="MalwareBytes" Margin="5,0"/>
                                <CheckBox Name="Installnvclean" Content="NVCleanstall" Margin="5,0"/>
                                <CheckBox Name="Installopenshell" Content="Open Shell (Start Menu)" Margin="5,0"/>
                                <CheckBox Name="Installprocesslasso" Content="Process Lasso" Margin="5,0"/>
                                <CheckBox Name="Installqbittorrent" Content="qBittorrent" Margin="5,0"/>
                                <CheckBox Name="Installrevo" Content="RevoUninstaller" Margin="5,0"/>
                                <CheckBox Name="Installrufus" Content="Rufus Imager" Margin="5,0"/>
                                <CheckBox Name="Installsandboxie" Content="Sandboxie Plus" Margin="5,0"/>
                                <CheckBox Name="Installshell" Content="Shell (Expanded Context Menu)" Margin="5,0"/>
                                
                                <CheckBox Name="Installttaskbar" Content="Translucent Taskbar" Margin="5,0"/>
                                <CheckBox Name="Installtreesize" Content="TreeSize Free" Margin="5,0"/>
                                <CheckBox Name="Installtwinkletray" Content="Twinkle Tray" Margin="5,0"/>
                                <CheckBox Name="Installwindirstat" Content="WinDirStat" Margin="5,0"/>
                                <CheckBox Name="Installwiztree" Content="WizTree" Margin="5,0"/>
                                
                                <Label Content="Pro Tools" FontSize="16" Margin="5,0"/>
                                <CheckBox Name="Installadvancedip" Content="Advanced IP Scanner" Margin="5,0"/>
                                <CheckBox Name="Installmremoteng" Content="mRemoteNG" Margin="5,0"/>
                                <CheckBox Name="Installputty" Content="Putty" Margin="5,0"/>
                                <CheckBox Name="Installrustdesk" Content="Rust Remote Desktop (FOSS)" Margin="5,0"/>
                                <CheckBox Name="Installsimplewall" Content="SimpleWall" Margin="5,0"/>
                                <CheckBox Name="Installwireshark" Content="WireShark" Margin="5,0"/>

                                <Label Content="Microsoft Tools" FontSize="16" Margin="5,0"/>
                                <CheckBox Name="Installdotnet3" Content=".NET Desktop Runtime 3.1" Margin="5,0"/>
                                <CheckBox Name="Installdotnet5" Content=".NET Desktop Runtime 5" Margin="5,0"/>
                                <CheckBox Name="Installdotnet6" Content=".NET Desktop Runtime 6" Margin="5,0"/>
                                <CheckBox Name="Installnuget" Content="Nuget" Margin="5,0"/>
                                <CheckBox Name="Installonedrive" Content="OneDrive" Margin="5,0"/>
                                <CheckBox Name="Installpowershell" Content="PowerShell" Margin="5,0"/>
                                <CheckBox Name="Installpowertoys" Content="Powertoys" Margin="5,0"/>
                                <CheckBox Name="Installprocessmonitor" Content="SysInternals Process Monitor" Margin="5,0"/>
                                <CheckBox Name="Installvc2015_64" Content="Visual C++ 2015-2022 64-bit" Margin="5,0"/>
                                <CheckBox Name="Installvc2015_32" Content="Visual C++ 2015-2022 32-bit" Margin="5,0"/>
                                <CheckBox Name="Installterminal" Content="Windows Terminal" Margin="5,0"/>


                            </StackPanel>
                            <StackPanel Background="#777777" SnapsToDevicePixels="True" Grid.Column="3" Margin="10">
                                <Label Content="Multimedia Tools" FontSize="16" Margin="5,0"/>
                                <CheckBox Name="Installaudacity" Content="Audacity" Margin="5,0"/>
                                <CheckBox Name="Installblender" Content="Blender (3D Graphics)" Margin="5,0"/>
                                <CheckBox Name="Installcider" Content="Cider (FOSS Music Player)" Margin="5,0"/>
                                <CheckBox Name="Installeartrumpet" Content="Eartrumpet (Audio)" Margin="5,0"/>
                                <CheckBox Name="Installflameshot" Content="Flameshot (Screenshots)" Margin="5,0"/>
                                <CheckBox Name="Installfoobar" Content="Foobar2000 (Music Player)" Margin="5,0"/>
                                <CheckBox Name="Installgimp" Content="GIMP (Image Editor)" Margin="5,0"/>
                                <CheckBox Name="Installhandbrake" Content="HandBrake" Margin="5,0"/>
                                <CheckBox Name="Installimageglass" Content="ImageGlass (Image Viewer)" Margin="5,0"/>
                                <CheckBox Name="Installinkscape" Content="Inkscape" Margin="5,0"/>
                                <CheckBox Name="Installkdenlive" Content="Kdenlive (Video Editor)" Margin="5,0"/>
                                <CheckBox Name="Installkodi" Content="Kodi Media Center" Margin="5,0"/>
                                <CheckBox Name="Installklite" Content="K-Lite Codec Standard" Margin="5,0"/>
                                <CheckBox Name="Installkrita" Content="Krita (Image Editor)" Margin="5,0"/>
                                <CheckBox Name="Installmpc" Content="Media Player Classic (Video Player)" Margin="5,0"/>
                                <CheckBox Name="Installobs" Content="OBS Studio" Margin="5,0"/>
                                <CheckBox Name="Installnglide" Content="nGlide (3dfx compatibility)" Margin="5,0"/>
                                <CheckBox Name="Installsharex" Content="ShareX (Screenshots)" Margin="5,0"/>
                                <CheckBox Name="Installstrawberry" Content="Strawberry (Music Player)" Margin="5,0"/>
                                <CheckBox Name="Installvlc" Content="VLC (Video Player)" Margin="5,0"/>
                                <CheckBox Name="Installvoicemeeter" Content="Voicemeeter (Audio)" Margin="5,0"/>
                            </StackPanel>
                            <StackPanel Background="#777777" SnapsToDevicePixels="True" Grid.Column="4" Margin="10">
			    <Label Content="Eddow" FontSize="16" Margin="5,0"/>
                                <CheckBox Name="Installpowerbi" Content="Power BI" Margin="5,0"/>
                                <CheckBox Name="Installpdf24creator" Content="PDF24 Creator" Margin="5,0"/>
                                <CheckBox Name="Installfilezilla" Content="FileZilla" Margin="5,0"/>
                                <CheckBox Name="Installdisplaylink" Content="Display Link" Margin="5,0"/>
                                <CheckBox Name="Installeset" Content="Eset EndpointAntivirus" Margin="5,0"/>
				<CheckBox Name="Installscp" Content="WinSCP" Margin="5,0"/>
				<CheckBox Name="Installsevenzip" Content="7-Zip" Margin="5,0"/>
				<CheckBox Name="Installnotepadplus" Content="Notepad++" Margin="5,0"/>
				<CheckBox Name="Installdbeaver" Content="DBeaver CE" Margin="5,0"/>
				<CheckBox Name="Installadobe" Content="Adobe Reader DC" Margin="5,0"/>
				<CheckBox Name="Installoffice" Content="Office" Margin="5,0"/>
				<CheckBox Name="Installteams" Content="Teams" Margin="5,0"/>
				<CheckBox Name="Installfirefox" Content="Firefox" Margin="5,0"/>
				<CheckBox Name="Installchrome" Content="Chrome" Margin="5,0"/>
				<CheckBox Name="Installclickshare" Content="ClickShare" Margin="5,0"/>
				<CheckBox Name="Installteamviewer" Content="TeamViewer" Margin="5,0"/>
				Write-Host "  "
				Write-Host "  "
                                
                                <Button Name="install" Background="AliceBlue" Content="Start Install" HorizontalAlignment = "Left" Margin="5,0" Padding="20,5" Width="150" ToolTip="Install all checked programs"/>
                                <Button Name="InstallUpgrade" Background="AliceBlue" Content="Upgrade Installs" HorizontalAlignment = "Left" Margin="5,0,0,5" Padding="20,5" Width="150" ToolTip="Upgrade All Existing Programs on System"/>

                            </StackPanel>
                        </Grid>
                    </TabItem>
                    <TabItem Header="Tweaks" Visibility="Collapsed" Name="Tab2">
                        <Grid Background="#333333">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions>
                                <RowDefinition Height=".10*"/>
                                <RowDefinition Height=".70*"/>
                                <RowDefinition Height=".10*"/>
                            </Grid.RowDefinitions>
                            <StackPanel Background="#777777" Orientation="Horizontal" Grid.Row="0" HorizontalAlignment="Center" Grid.Column="0" Margin="10">
                                <Label Content="Recommended Selections:" FontSize="17" VerticalAlignment="Center"/>
                                <Button Name="desktop" Content=" Desktop " Margin="7"/>
                                <Button Name="laptop" Content=" Laptop " Margin="7"/>
                                <Button Name="minimal" Content=" Minimal " Margin="7"/>
                                <Button Name="clear" Content=" Clear " Margin="7"/>
                            </StackPanel>
                            <StackPanel Background="#777777" Orientation="Horizontal" Grid.Row="0" HorizontalAlignment="Center" Grid.Column="1" Margin="10">
                                <Label Content="Configuration File:" FontSize="17" VerticalAlignment="Center"/>
                                <Button Name="import" Content=" Import " Margin="7"/>
                                <Button Name="export" Content=" Export " Margin="7"/>
                            </StackPanel>
                            <StackPanel Background="#777777" Orientation="Horizontal" Grid.Row="2" HorizontalAlignment="Center" Grid.ColumnSpan="2" Margin="10">
                                <TextBlock Padding="10">
                                    Note: Hover over items to get a better description. Please be careful as many of these tweaks will heavily modify your system.
                                    <LineBreak/>Recommended selections are for normal users and if you are unsure do NOT check anything else!
                                </TextBlock>
                            </StackPanel>
                            <StackPanel Background="#777777" SnapsToDevicePixels="True" Grid.Row="1" Grid.Column="0" Margin="10,5">
                                <Label FontSize="16" Content="Essential Tweaks"/>
                                <CheckBox Name="EssTweaksRP" Content="Create Restore Point" Margin="5,0" ToolTip="Creates a Windows Restore point before modifying system. Can use Windows System Restore to rollback to before tweaks were applied"/>
                                <CheckBox Name="EssTweaksOO" Content="Run OO Shutup" Margin="5,0" ToolTip="Runs OO Shutup from https://www.oo-software.com/en/shutup10"/>
                                <CheckBox Name="EssTweaksTele" Content="Disable Telemetry" Margin="5,0" ToolTip="Disables Microsoft Telemetry. Note: This will lock many Edge Browser settings. Microsoft spys heavily on you when using the Edge browser."/>
                                <CheckBox Name="EssTweaksWifi" Content="Disable Wifi-Sense" Margin="5,0" ToolTip="Wifi Sense is a spying service that phones home all nearby scaned wifi networks and your current geo location."/>
                                <CheckBox Name="EssTweaksAH" Content="Disable Activity History" Margin="5,0" ToolTip="This erases recent docs, clipboard, and run history."/>
                                <CheckBox Name="EssTweaksDeleteTempFiles" Content="Delete Temporary Files" Margin="5,0" ToolTip="Erases TEMP Folders"/>
                                <CheckBox Name="EssTweaksDiskCleanup" Content="Run Disk Cleanup" Margin="5,0" ToolTip="Runs Disk Cleanup on Drive C: and removes old Windows Updates."/>
                                <CheckBox Name="EssTweaksLoc" Content="Disable Location Tracking" Margin="5,0" ToolTip="Disables Location Tracking...DUH!"/>
                                <CheckBox Name="EssTweaksHome" Content="Disable Homegroup" Margin="5,0" ToolTip="Disables HomeGroup - Windows 11 doesn''t have this, it was awful."/>
                                <CheckBox Name="EssTweaksStorage" Content="Disable Storage Sense" Margin="5,0" ToolTip="Storage Sense is supposed to delete temp files automatically, but often runs at wierd times and mostly doesn''t do much. Although when it was introduced in Win 10 (1809 Version) it deleted people''s documents... So there is that."/>
                                <CheckBox Name="EssTweaksHiber" Content="Disable Hibernation" Margin="5,0" ToolTip="Hibernation is really meant for laptops as it saves whats in memory before turning the pc off. It really should never be used, but some people are lazy and rely on it. Don''t be like Bob. Bob likes hibernation."/>
                                <CheckBox Name="EssTweaksDVR" Content="Disable GameDVR" Margin="5,0" ToolTip="GameDVR is a Windows App that is a dependancy for some Store Games. I''ve never met someone that likes it, but it''s there for the XBOX crowd."/>
                                <CheckBox Name="EssTweaksServices" Content="Set Services to Manual" Margin="5,0" ToolTip="Turns a bunch of system services to manual that don''t need to be running all the time. This is pretty harmless as if the service is needed, it will simply start on demand."/>
                                <Label Content="Dark Theme" />
                                <StackPanel Orientation="Horizontal">
                                    <Label Content="Off" />
                                    <CheckBox Name="ToggleDarkMode" Style="{StaticResource ToggleSwitchStyle}" Margin="2.5,0"/>
                                    <Label Content="On" />
                                </StackPanel>
							<Label Content="Performance Plans" />
                                <Button Name="AddUltPerf" Background="AliceBlue" Content="Add Ultimate Performance Profile" HorizontalAlignment = "Left" Margin="5,0" Padding="20,5" Width="300"/>
                                <Button Name="RemoveUltPerf" Background="AliceBlue" Content="Remove Ultimate Performance Profile" HorizontalAlignment = "Left" Margin="5,0,0,5" Padding="20,5" Width="300"/>

                            </StackPanel>
                            <StackPanel Background="#777777" SnapsToDevicePixels="True" Grid.Row="1" Grid.Column="1" Margin="10,5">
                                <Label FontSize="16" Content="Misc. Tweaks"/>
                                <CheckBox Name="MiscTweaksPower" Content="Disable Power Throttling" Margin="5,0" ToolTip="This is mainly for Laptops, It disables Power Throttling and will use more battery."/>
                                <CheckBox Name="MiscTweaksLapPower" Content="Enable Power Throttling" Margin="5,0" ToolTip="ONLY FOR LAPTOPS! Do not use on a desktop."/>
                                <CheckBox Name="MiscTweaksNum" Content="Enable NumLock on Startup" Margin="5,0" ToolTip="This creates a time vortex and send you back to the past... or it simply turns numlock on at startup"/>
                                <CheckBox Name="MiscTweaksLapNum" Content="Disable Numlock on Startup" Margin="5,0" ToolTip="Disables Numlock... Very useful when you are on a laptop WITHOUT 9-key and this fixes that issue when the numlock is enabled!"/>
                                <CheckBox Name="MiscTweaksExt" Content="Show File Extensions" Margin="5,0"/>
                                <CheckBox Name="MiscTweaksDisplay" Content="Set Display for Performance" Margin="5,0" ToolTip="Sets the system preferences to performance. You can do this manually with sysdm.cpl as well."/>
                                <CheckBox Name="MiscTweaksUTC" Content="Set Time to UTC (Dual Boot)" Margin="5,0" ToolTip="Essential for computers that are dual booting. Fixes the time sync with Linux Systems."/>
                                <CheckBox Name="MiscTweaksDisableUAC" Content="Disable UAC" Margin="5,0" ToolTip="Disables User Account Control. Only recommended for Expert Users."/>
                                <CheckBox Name="MiscTweaksDisableNotifications" Content="Disable Notification" Margin="5,0" ToolTip="Disables all Notifications"/>
                                <CheckBox Name="MiscTweaksDisableTPMCheck" Content="Disable TPM on Update" Margin="5,0" ToolTip="Add the Windows 11 Bypass for those that want to upgrade their Windows 10."/>
                                <CheckBox Name="EssTweaksDeBloat" Content="Remove ALL MS Store Apps" Margin="5,0" ToolTip="USE WITH CAUTION!!!!! This will remove ALL Microsoft store apps other than the essentials to make winget work. Games installed by MS Store ARE INCLUDED!"/>
                                <CheckBox Name="EssTweaksRemoveCortana" Content="Remove Cortana" Margin="5,0" ToolTip="Removes Cortana, but often breaks search... if you are a heavy windows search users, this is NOT recommended."/>
                                <CheckBox Name="EssTweaksRemoveEdge" Content="Remove Microsoft Edge" Margin="5,0" ToolTip="Removes MS Edge when it gets reinstalled by updates."/>
                                <CheckBox Name="MiscTweaksRightClickMenu" Content="Set Classic Right-Click Menu " Margin="5,0" ToolTip="Great Windows 11 tweak to bring back good context menus when right clicking things in explorer."/>
                                <CheckBox Name="MiscTweaksDisableMouseAcceleration" Content="Disable Mouse Acceleration" Margin="5,0" ToolTip="Disables Mouse Acceleration."/>
                                <CheckBox Name="MiscTweaksEnableMouseAcceleration" Content="Enable Mouse Acceleration" Margin="5,0" ToolTip="Enables Mouse Acceleration."/>
                                <Label Content="DNS" />
							    <ComboBox Name="changedns"  Height = "20" Width = "150" HorizontalAlignment = "Left" Margin="5,5"> 
								    <ComboBoxItem IsSelected="True" Content = "Default"/> 
                                    <ComboBoxItem Content = "DHCP"/> 
								    <ComboBoxItem Content = "Google"/> 
								    <ComboBoxItem Content = "Cloudflare"/> 
                                    <ComboBoxItem Content = "Cloudflare_Malware"/> 
                                    <ComboBoxItem Content = "Cloudflare_Malware_Adult"/> 
								    <ComboBoxItem Content = "Level3"/> 
								    <ComboBoxItem Content = "Open_DNS"/> 
                                    <ComboBoxItem Content = "Quad9"/>
							    </ComboBox> 
                                <Button Name="tweaksbutton" Background="AliceBlue" Content="Run Tweaks  " HorizontalAlignment = "Left" Margin="5,0" Padding="20,5" Width="150"/>
                                <Button Name="undoall" Background="AliceBlue" Content="Undo Tweaks" HorizontalAlignment = "Left" Margin="5,0" Padding="20,5" Width="150"/>
                            </StackPanel>
                        </Grid>
                    </TabItem>
                    <TabItem Header="Config" Visibility="Collapsed" Name="Tab3">
                        <Grid Background="#444444">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Background="#777777" SnapsToDevicePixels="True" Grid.Column="0" Margin="10,5">
                                <Label Content="Features" FontSize="16"/>
                                <CheckBox Name="Featuresdotnet" Content="All .Net Framework (2,3,4)" Margin="5,0"/>
                                <CheckBox Name="Featureshyperv" Content="HyperV Virtualization" Margin="5,0"/>
                                <CheckBox Name="Featureslegacymedia" Content="Legacy Media (WMP, DirectPlay)" Margin="5,0"/>
                                <CheckBox Name="Featurenfs" Content="NFS - Network File System" Margin="5,0"/>
                                <CheckBox Name="Featurewsl" Content="Windows Subsystem for Linux" Margin="5,0"/>
                                <Button Name="FeatureInstall" FontSize="14" Background="AliceBlue" Content="Install Features" HorizontalAlignment = "Left" Margin="5" Padding="20,5" Width="150"/>
                                <Label Content="Fixes" FontSize="16"/>
                                <Button Name="PanelAutologin" FontSize="14" Background="AliceBlue" Content="Set Up Autologin" HorizontalAlignment = "Left" Margin="5,2" Padding="20,5" Width="300"/>
                                <Button Name="FixesUpdate" FontSize="14" Background="AliceBlue" Content="Reset Windows Update" HorizontalAlignment = "Left" Margin="5,2" Padding="20,5" Width="300"/>
                                <Button Name="PanelDISM" FontSize="14" Background="AliceBlue" Content="System Corruption Scan" HorizontalAlignment = "Left" Margin="5,2" Padding="20,5" Width="300"/>
                            </StackPanel>
                            <StackPanel Background="#777777" SnapsToDevicePixels="True" Grid.Column="1" Margin="10,5">
                                <Label Content="Legacy Windows Panels" FontSize="16"/>
                                <Button Name="Panelcontrol" FontSize="14" Background="AliceBlue" Content="Control Panel" HorizontalAlignment = "Left" Margin="5" Padding="20,5" Width="200"/>
                                <Button Name="Panelnetwork" FontSize="14" Background="AliceBlue" Content="Network Connections" HorizontalAlignment = "Left" Margin="5" Padding="20,5" Width="200"/>
                                <Button Name="Panelpower" FontSize="14" Background="AliceBlue" Content="Power Panel" HorizontalAlignment = "Left" Margin="5" Padding="20,5" Width="200"/>
                                <Button Name="Panelsound" FontSize="14" Background="AliceBlue" Content="Sound Settings" HorizontalAlignment = "Left" Margin="5" Padding="20,5" Width="200"/>
                                <Button Name="Panelsystem" FontSize="14" Background="AliceBlue" Content="System Properties" HorizontalAlignment = "Left" Margin="5" Padding="20,5" Width="200"/>
                                <Button Name="Paneluser" FontSize="14" Background="AliceBlue" Content="User Accounts" HorizontalAlignment = "Left" Margin="5" Padding="20,5" Width="200"/>
                            </StackPanel>
                        </Grid>
                    </TabItem>
                    <TabItem Header="Updates" Visibility="Collapsed" Name="Tab4">
                        <Grid Background="#555555">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Background="#777777" SnapsToDevicePixels="True" Grid.Column="0" Margin="10,5">
                                <Button Name="Updatesdefault" FontSize="16" Background="AliceBlue" Content="Default (Out of Box) Settings" Margin="20,0,20,10" Padding="10"/>
                                <TextBlock Margin="20,0,20,0" Padding="10" TextWrapping="WrapWithOverflow" MaxWidth="300">This is the default settings that come with Windows. <LineBreak/><LineBreak/> No modifications are made and will remove any custom windows update settings.<LineBreak/><LineBreak/>Note: If you still encounter update errors, reset all updates in the config tab. That will restore ALL Microsoft Update Services from their servers and reinstall them to default settings.</TextBlock>
                            </StackPanel>
                            <StackPanel Background="#777777" SnapsToDevicePixels="True" Grid.Column="1" Margin="10,5">
                                <Button Name="Updatessecurity" FontSize="16" Background="AliceBlue" Content="Security (Recommended) Settings" Margin="20,0,20,10" Padding="10"/>
                                <TextBlock Margin="20,0,20,0" Padding="10" TextWrapping="WrapWithOverflow" MaxWidth="300">This is my recommended setting I use on all computers.<LineBreak/><LineBreak/> It will delay feature updates by 2 years and will install security updates 4 days after release.<LineBreak/><LineBreak/>Feature Updates: Adds features and often bugs to systems when they are released. You want to delay these as long as possible.<LineBreak/><LineBreak/>Security Updates: Typically these are pressing security flaws that need to be patched quickly. You only want to delay these a couple of days just to see if they are safe and don''t break other systems. You don''t want to go without these for ANY extended periods of time.</TextBlock>
                            </StackPanel>
                            <StackPanel Background="#777777" SnapsToDevicePixels="True" Grid.Column="2" Margin="10,5">
                                <Button Name="Updatesdisable" FontSize="16" Background="AliceBlue" Content="Disable ALL Updates (NOT RECOMMENDED!)" Margin="20,0,20,10" Padding="10,10,10,10"/>
                                <TextBlock Margin="20,0,20,0" Padding="10" TextWrapping="WrapWithOverflow" MaxWidth="300">This completely disables ALL Windows Updates and is NOT RECOMMENDED.<LineBreak/><LineBreak/> However, it can be suitable if you use your system for a select purpose and do not actively browse the internet. <LineBreak/><LineBreak/>Note: Your system will be easier to hack and infect without security updates.</TextBlock>
                                <TextBlock Text=" " Margin="20,0,20,0" Padding="10" TextWrapping="WrapWithOverflow" MaxWidth="300"/>

                            </StackPanel>

                        </Grid>
                    </TabItem>
                </TabControl>
            </Grid>
        </Viewbox>
    </Border>
</Window>'
$sync.configs.applications = '{
  "WPFInstalladobe": {
    "winget": "Adobe.Acrobat.Reader.64-bit",
    "choco": "adobereader"
  },
  "WPFInstalladvancedip": {
    "winget": "Famatech.AdvancedIPScanner",
    "choco": "advanced-ip-scanner"
  },
  "WPFInstallanydesk": {
    "winget": "AnyDeskSoftwareGmbH.AnyDesk",
    "choco": "anydesk"
  },
  "WPFInstallatom": {
    "winget": "GitHub.Atom",
    "choco": "atom"
  },
  "WPFInstallaudacity": {
    "winget": "Audacity.Audacity",
    "choco": "audacity"
  },
  "WPFInstallautohotkey": {
    "winget": "Lexikos.AutoHotkey",
    "choco": "autohotkey"
  },
  "WPFInstallbitwarden": {
    "winget": "Bitwarden.Bitwarden",
    "choco": "bitwarden"
  },
  "WPFInstallblender": {
    "winget": "BlenderFoundation.Blender",
    "choco": "blender"
  },
  "WPFInstallbrave": {
    "winget": "Brave.Brave",
    "choco": "brave"
  },
  "WPFInstallchrome": {
    "winget": "Google.Chrome",
    "choco": "googlechrome"
  },
  "WPFInstallchromium": {
    "winget": "eloston.ungoogled-chromium",
    "choco": "chromium"
  },
  "WPFInstallcpuz": {
    "winget": "CPUID.CPU-Z",
    "choco": "cpu-z"
  },
  "WPFInstalldeluge": {
    "winget": "DelugeTeam.Deluge",
    "choco": "deluge"
  },
  "WPFInstalldiscord": {
    "winget": "Discord.Discord",
    "choco": "discord"
  },
  "WPFInstalleartrumpet": {
    "winget": "File-New-Project.EarTrumpet",
    "choco": "eartrumpet"
  },
  "WPFInstallpdf24creator": {
    "winget": "geeksoftwareGmbH.PDF24Creator",
    "choco": "pdf24"
  },
  "WPFInstallesearch": {
    "winget": "voidtools.Everything",
    "choco": "everything"
  },
  "WPFInstalletcher": {
    "winget": "Balena.Etcher",
    "choco": "etcher"
  },
  "WPFInstallfirefox": {
    "winget": "Mozilla.Firefox",
    "choco": "firefox"
  },
  "WPFInstallflameshot": {
    "winget": "Flameshot.Flameshot",
    "choco": "na"
  },
  "WPFInstallfoobar": {
    "winget": "PeterPawlowski.foobar2000",
    "choco": "foobar2000"
  },
  "WPFInstallgimp": {
    "winget": "GIMP.GIMP",
    "choco": "gimp"
  },
  "WPFInstallgithubdesktop": {
    "winget": "Git.Git;GitHub.GitHubDesktop",
    "choco": "git;github-desktop"
  },
  "WPFInstallfilezilla": {
    "winget": "filezilla",
    "choco": "filezilla"
  },
  "WPFInstallgpuz": {
    "winget": "TechPowerUp.GPU-Z",
    "choco": "gpu-z"
  },
  "WPFInstalldbeaver": {
    "winget": "9PNKDR50694P",
    "choco": "dbeaver"
  },
  "WPFInstallhandbrake": {
    "winget": "HandBrake.HandBrake",
    "choco": "handbrake"
  },
  "WPFInstallhexchat": {
    "winget": "HexChat.HexChat",
    "choco": "hexchat"
  },
  "WPFInstallhwinfo": {
    "winget": "REALiX.HWiNFO",
    "choco": "hwinfo"
  },
  "WPFInstallimageglass": {
    "winget": "DuongDieuPhap.ImageGlass",
    "choco": "imageglass"
  },
  "WPFInstallinkscape": {
    "winget": "Inkscape.Inkscape",
    "choco": "inkscape"
  },
  "WPFInstalljava16": {
    "winget": "AdoptOpenJDK.OpenJDK.16",
    "choco": "temurin16jre"
  },
  "WPFInstalljava18": {
    "winget": "EclipseAdoptium.Temurin.18.JRE",
    "choco": "temurin18jre"
  },
  "WPFInstalljava8": {
    "winget": "EclipseAdoptium.Temurin.8.JRE",
    "choco": "temurin8jre"
  },
  "WPFInstalljava19": {
    "winget": "EclipseAdoptium.Temurin.19.JRE",
    "choco": "temurin19jre"
  },
  "WPFInstalljava17": {
    "winget": "EclipseAdoptium.Temurin.17.JRE",
    "choco": "temurin17jre"
  },
  "WPFInstalljava11": {
    "winget": "EclipseAdoptium.Temurin.11.JRE",
    "choco": "javaruntime"
  },
  "WPFInstalljetbrains": {
    "winget": "JetBrains.Toolbox",
    "choco": "jetbrainstoolbox"
  },
  "WPFInstallkeepass": {
    "winget": "KeePassXCTeam.KeePassXC",
    "choco": "keepassxc"
  },
  "WPFInstalllibrewolf": {
    "winget": "LibreWolf.LibreWolf",
    "choco": "librewolf"
  },
  "WPFInstallmalwarebytes": {
    "winget": "Malwarebytes.Malwarebytes",
    "choco": "malwarebytes"
  },
  "WPFInstallmatrix": {
    "winget": "Element.Element",
    "choco": "element-desktop"
  },
  "WPFInstallmpc": {
    "winget": "clsid2.mpc-hc",
    "choco": "mpc-hc"
  },
  "WPFInstallmremoteng": {
    "winget": "mRemoteNG.mRemoteNG",
    "choco": "mremoteng"
  },
  "WPFInstallnodejs": {
    "winget": "OpenJS.NodeJS",
    "choco": "nodejs"
  },
  "WPFInstallnodejslts": {
    "winget": "OpenJS.NodeJS.LTS",
    "choco": "nodejs-lts"
  },
  "WPFInstallnotepadplus": {
    "winget": "Notepad++.Notepad++",
    "choco": "notepadplusplus"
  },
  "WPFInstallnvclean": {
    "winget": "TechPowerUp.NVCleanstall",
    "choco": "na"
  },
  "WPFInstallobs": {
    "winget": "OBSProject.OBSStudio",
    "choco": "obs-studio"
  },
  "WPFInstallobsidian": {
    "winget": "Obsidian.Obsidian",
    "choco": "obsidian"
  },
  "WPFInstallpowertoys": {
    "winget": "Microsoft.PowerToys",
    "choco": "powertoys"
  },
  "WPFInstallputty": {
    "winget": "PuTTY.PuTTY",
    "choco": "putty"
  },
  "WPFInstallpython3": {
    "winget": "Python.Python.3.11",
    "choco": "python"
  },
  "WPFInstallrevo": {
    "winget": "RevoUnInstaller.RevoUnInstaller",
    "choco": "revo-uninstaller"
  },
  "WPFInstallrufus": {
    "winget": "Rufus.Rufus",
    "choco": "rufus"
  },
  "WPFInstallsevenzip": {
    "winget": "7zip.7zip",
    "choco": "7zip"
  },
  "WPFInstallsharex": {
    "winget": "ShareX.ShareX",
    "choco": "sharex"
  },
  "WPFInstallsignal": {
    "winget": "OpenWhisperSystems.Signal",
    "choco": "signal"
  },
  "WPFInstallskype": {
    "winget": "Microsoft.Skype",
    "choco": "skype"
  },
  "WPFInstallslack": {
    "winget": "SlackTechnologies.Slack",
    "choco": "slack"
  },
  "WPFInstalleset": {
    "winget": "ESET.EndpointAntivirus",
    "choco": "eset-antivirus"
  },
  "WPFInstallsublime": {
    "winget": "SublimeHQ.SublimeText.4",
    "choco": "sublimetext4"
  },
  "WPFInstallsumatra": {
    "winget": "SumatraPDF.SumatraPDF",
    "choco": "sumatrapdf"
  },
  "WPFInstallteams": {
    "winget": "Microsoft.Teams",
    "choco": "microsoft-teams"
  },
  "WPFInstallteamviewer": {
    "winget": "TeamViewer.TeamViewer",
    "choco": "teamviewer9"
  },
  "WPFInstallterminal": {
    "winget": "Microsoft.WindowsTerminal",
    "choco": "microsoft-windows-terminal"
  },
  "WPFInstalltreesize": {
    "winget": "JAMSoftware.TreeSize.Free",
    "choco": "treesizefree"
  },
  "WPFInstallttaskbar": {
    "winget": "TranslucentTB.TranslucentTB",
    "choco": "translucenttb"
  },
  "WPFInstallvisualstudio": {
    "winget": "Microsoft.VisualStudio.2022.Community",
    "choco": "visualstudio2022community"
  },
  "WPFInstallvivaldi": {
    "winget": "VivaldiTechnologies.Vivaldi",
    "choco": "vivaldi"
  },
  "WPFInstallvlc": {
    "winget": "VideoLAN.VLC",
    "choco": "vlc"
  },
  "WPFInstallvoicemeeter": {
    "winget": "VB-Audio.Voicemeeter",
    "choco": "voicemeeter"
  },
  "WPFInstallvscode": {
    "winget": "Git.Git;Microsoft.VisualStudioCode",
    "choco": "vscode"
  },
  "WPFInstallvscodium": {
    "winget": "Git.Git;VSCodium.VSCodium",
    "choco": "vscodium"
  },
  "WPFInstallwindirstat": {
    "winget": "WinDirStat.WinDirStat",
    "choco": "windirstat"
  },
  "WPFInstallscp": {
    "winget": "WinSCP.WinSCP",
    "choco": "winscp"
  },
  "WPFInstallwireshark": {
    "winget": "WiresharkFoundation.Wireshark",
    "choco": "wireshark"
  },
  "WPFInstallzoom": {
    "winget": "Zoom.Zoom",
    "choco": "zoom"
  },
  "WPFInstalloffice": {
    "winget": "Microsoft.Office",
    "choco": "na"
  },
  "WPFInstallshell": {
    "winget": "Nilesoft.Shell",
    "choco": "na"
  },
  "WPFInstallklite": {
    "winget": "CodecGuide.K-LiteCodecPack.Standard",
    "choco": "k-litecodecpack-standard"
  },
  "WPFInstallsandboxie": {
    "winget": "Sandboxie.Plus",
    "choco": "sandboxie"
  },
  "WPFInstallprocesslasso": {
    "winget": "BitSum.ProcessLasso",
    "choco": "plasso"
  },
  "WPFInstallwinmerge": {
    "winget": "WinMerge.WinMerge",
    "choco": "winmerge"
  },
  "WPFInstalldotnet3": {
    "winget": "Microsoft.DotNet.DesktopRuntime.3_1",
    "choco": "dotnetcore3-desktop-runtime"
  },
  "WPFInstalldotnet5": {
    "winget": "Microsoft.DotNet.DesktopRuntime.5",
    "choco": "dotnet-5.0-runtime"
  },
  "WPFInstalldotnet6": {
    "winget": "Microsoft.DotNet.DesktopRuntime.6",
    "choco": "dotnet-6.0-runtime"
  },
  "WPFInstallvc2015_64": {
    "winget": "Microsoft.VC++2015-2022Redist-x64",
    "choco": "na"
  },
  "WPFInstallvc2015_32": {
    "winget": "Microsoft.VC++2015-2022Redist-x86",
    "choco": "na"
  },
  "WPFInstallfoxpdf": {
    "winget": "Foxit.PhantomPDF",
    "choco": "na"
  },
  "WPFInstallonlyoffice": {
    "winget": "ONLYOFFICE.DesktopEditors",
    "choco": "onlyoffice"
  },
  "WPFInstallflux": {
    "winget": "flux.flux",
    "choco": "flux"
  },
  "WPFInstallclickshare": {
    "winget": "clickshare-desktop",
    "choco": "clickshare-desktop"
  },
  "WPFInstallcider": {
    "winget": "CiderCollective.Cider",
    "choco": "cider"
  },
  "WPFInstalljoplin": {
    "winget": "Joplin.Joplin",
    "choco": "joplin"
  },
  "WPFInstallopenoffice": {
    "winget": "Apache.OpenOffice",
    "choco": "openoffice"
  },
  "WPFInstallrustdesk": {
    "winget": "RustDesk.RustDesk",
    "choco": "rustdesk.portable"
  },
  "WPFInstalljami": {
    "winget": "SFLinux.Jami",
    "choco": "jami"
  },
  "WPFInstalljdownloader": {
    "winget": "AppWork.JDownloader",
    "choco": "jdownloader"
  },
  "WPFInstallsimplewall": {
    "Winget": "Henry++.simplewall",
    "choco": "simplewall"
  },
  "WPFInstallrustlang": {
    "Winget": "Rustlang.Rust.MSVC",
    "choco": "rust"
  },
  "WPFInstallgolang": {
    "Winget": "GoLang.Go.1.19",
    "choco": "golang"
  },
  "WPFInstallalacritty": {
    "Winget": "Alacritty.Alacritty",
    "choco": "alacritty"
  },
  "WPFInstallkdenlive": {
    "Winget": "KDE.Kdenlive",
    "choco": "kdenlive"
  },
  "WPFInstallglaryutilities": {
    "Winget": "Glarysoft.GlaryUtilities",
    "choco": "glaryutilities-free"
  },
  "WPFInstalltwinkletray": {
    "Winget": "xanderfrangos.twinkletray",
    "choco": "na"
  },
  "WPFInstallidm": {
    "Winget": "Tonec.InternetDownloadManager",
    "choco": "internet-download-manager"
  },
  "WPFInstallviber": {
    "Winget": "Viber.Viber",
    "choco": "viber"
  },
  "WPFInstallgit": {
    "Winget": "Git.Git",
    "choco": "git"
  },
  "WPFInstallwiztree": {
    "Winget": "AntibodySoftware.WizTree",
    "choco": "wiztree\\"
  },
  "WPFInstalltor": {
    "Winget": "TorProject.TorBrowser",
    "choco": "tor-browser"
  },
  "WPFInstallkrita": {
    "winget": "KDE.Krita",
    "choco": "krita"
  },
  "WPFInstallnglide": {
    "winget": "ZeusSoftware.nGlide",
    "choco": "na"
  },
  "WPFInstallkodi": {
    "winget": "XBMCFoundation.Kodi",
    "choco": "kodi"
  },
  "WPFInstalltelegram": {
    "winget": "Telegram.TelegramDesktop",
    "choco": "telegram"
  },
  "WPFInstallunity": {
    "winget": "UnityTechnologies.UnityHub",
    "choco": "unityhub"
  },
  "WPFInstallqbittorrent": {
    "winget": "qBittorrent.qBittorrent",
    "choco": "qbittorrent"
  },
  "WPFInstalldisplaylink": {
    "winget": "DisplayLink.GraphicsDriver",
    "choco": "displaylink"
  },
  "WPFInstallopenshell": {
    "winget": "Open-Shell.Open-Shell-Menu",
    "choco": "open-shell"
  },
  "WPFInstallpowerbi": {
    "winget": "Microsoft.PowerBI",
    "choco": "powerbi"
  },
  "WPFInstallstrawberry": {
    "winget": "StrawberryMusicPlayer.Strawberry",
    "choco": "strawberrymusicplayer"
  },
  "WPFInstallsqlstudio": {
    "winget": "Microsoft.SQLServerManagementStudio",
    "choco": "sql-server-management-studio"
  },
  "WPFInstallwaterfox": {
    "winget": "Waterfox.Waterfox",
    "choco": "waterfox"
  },
  "WPFInstallpowershell": {
    "winget": "Microsoft.PowerShell",
    "choco": "powershell-core"
  },
  "WPFInstallprocessmonitor": {
    "winget": "Microsoft.Sysinternals.ProcessMonitor",
    "choco": "procexp"
  },
  "WPFInstallonedrive": {
    "winget": "Microsoft.OneDrive",
    "choco": "onedrive"
  },
  "WPFInstalledge": {
    "winget": "Microsoft.Edge",
    "choco": "microsoft-edge"
  },
  "WPFInstallnuget": {
    "winget": "Microsoft.NuGet",
    "choco": "nuget.commandline"
  }
}' | convertfrom-json
$sync.configs.dns = '{
    "Google":{
        "Primary": "8.8.8.8",
        "Secondary": "8.8.4.4"
    },
    "Cloudflare":{
        "Primary": "1.1.1.1",
        "Secondary": "1.0.0.1"
    },
    "Cloudflare_Malware":{
        "Primary": "1.1.1.2",
        "Secondary": "1.0.0.2"
    },
    "Cloudflare_Malware_Adult":{
        "Primary": "1.1.1.3",
        "Secondary": "1.0.0.3"
    },
    "Level3":{
        "Primary": "4.2.2.2",
        "Secondary": "4.2.2.1"
    },
    "Open_DNS":{
        "Primary": "208.67.222.222",
        "Secondary": "208.67.220.220"
    },
    "Quad9":{
        "Primary": "9.9.9.9",
        "Secondary": "149.112.112.112"
    }
}' | convertfrom-json
$sync.configs.feature = '{
  "Featuresdotnet": [
    "NetFx4-AdvSrvs",
    "NetFx3"
  ],
  "Featureshyperv": [
    "HypervisorPlatform",
    "Microsoft-Hyper-V-All",
    "Microsoft-Hyper-V",
    "Microsoft-Hyper-V-Tools-All",
    "Microsoft-Hyper-V-Management-PowerShell",
    "Microsoft-Hyper-V-Hypervisor",
    "Microsoft-Hyper-V-Services",
    "Microsoft-Hyper-V-Management-Clients"
  ],
  "Featureslegacymedia": [
    "WindowsMediaPlayer",
    "MediaPlayback",
    "DirectPlay",
    "LegacyComponents"
  ],
  "Featurewsl": [
    "VirtualMachinePlatform",
    "Microsoft-Windows-Subsystem-Linux"
  ],
  "Featurenfs": [
    "ServicesForNFS-ClientOnly",
    "ClientForNFS-Infrastructure",
    "NFS-Administration"
  ]
}' | convertfrom-json
$sync.configs.preset = '{
  "desktop": [
    "WPFEssTweaksAH",
    "WPFEssTweaksDVR",
    "WPFEssTweaksHiber",
    "WPFEssTweaksHome",
    "WPFEssTweaksLoc",
    "WPFEssTweaksOO",
    "WPFEssTweaksRP",
    "WPFEssTweaksServices",
    "WPFEssTweaksStorage",
    "WPFEssTweaksTele",
    "WPFEssTweaksWifi",
    "WPFMiscTweaksPower",
    "WPFMiscTweaksNum"
  ],
  "laptop": [
    "WPFEssTweaksAH",
    "WPFEssTweaksDVR",
    "WPFEssTweaksHome",
    "WPFEssTweaksLoc",
    "WPFEssTweaksOO",
    "WPFEssTweaksRP",
    "WPFEssTweaksServices",
    "WPFEssTweaksStorage",
    "WPFEssTweaksTele",
    "WPFEssTweaksWifi",
    "WPFMiscTweaksLapPower",
    "WPFMiscTweaksLapNum"
  ],
  "minimal": [
    "WPFEssTweaksHome",
    "WPFEssTweaksOO",
    "WPFEssTweaksRP",
    "WPFEssTweaksServices",
    "WPFEssTweaksTele"
  ]
}' | convertfrom-json
$sync.configs.tweaks = '{
  "WPFEssTweaksAH": {
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
        "Name": "EnableActivityFeed",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
        "Name": "PublishUserActivities",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
        "Name": "UploadUserActivities",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      }
    ]
  },
  "WPFEssTweaksHiber": {
    "registry": [
      {
        "Path": "HKLM:\\System\\CurrentControlSet\\Control\\Session Manager\\Power",
        "Name": "HibernateEnabled",
        "Type": "Dword",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FlyoutMenuSettings",
        "Name": "ShowHibernateOption",
        "Type": "Dword",
        "Value": "0",
        "OriginalValue": "1"
      }
    ]
  },
  "WPFEssTweaksHome": {
    "service": [
      {
        "Name": "HomeGroupListener",
        "StartupType": "Manual",
        "OriginalType": "Automatic"
      },
      {
        "Name": "HomeGroupProvider",
        "StartupType": "Manual",
        "OriginalType": "Automatic"
      }
    ]
  },
  "WPFEssTweaksLoc": {
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\location",
        "Name": "Value",
        "Type": "String",
        "Value": "Deny",
        "OriginalValue": "Allow"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Sensor\\Overrides\\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}",
        "Name": "SensorPermissionState",
        "Type": "Dword",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\lfsvc\\Service\\Configuration",
        "Name": "Status",
        "Type": "Dword",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\SYSTEM\\Maps",
        "Name": "AutoUpdateEnabled",
        "Type": "Dword",
        "Value": "0",
        "OriginalValue": "1"
      }
    ]
  },
  "WPFEssTweaksServices": {
    "service": [
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "diagnosticshub.standardcollector.service"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "DiagTrack"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "DPS"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "dmwappushservice"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "lfsvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "MapsBroker"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "NetTcpPortSharing"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "RemoteAccess"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "RemoteRegistry"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "SharedAccess"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "TrkWks"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "WMPNetworkSvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "WSearch"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "XblAuthManager"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "XblGameSave"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "XboxNetApiSvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "XboxGipSvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "ndu"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "WerSvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "Fax"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "fhsvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "gupdate"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "gupdatem"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "stisvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "AJRouter"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "MSDTC"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "WpcMonSvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "PhoneSvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "PrintNotify"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "PcaSvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "WPDBusEnum"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "seclogon"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "SysMain"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "lmhosts"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "wisvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "FontCache"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "RetailDemo"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "ALG"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "SCardSvr"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "EntAppSvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "BthAvctpSvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "Browser"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "BthAvctpSvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "iphlpsvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "edgeupdate"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "MicrosoftEdgeElevationService"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "edgeupdatem"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "SEMgrSvc"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "PerfHost"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "BcastDVRUserService_48486de"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "CaptureService_48486de"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "cbdhsvc_48486de"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "WpnService"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "RtkBtManServ"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "QWAVE"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "HPAppHelperCap"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "HPDiagsCap"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "HPNetworkCap"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "HPSysInfoCap"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "HpTouchpointAnalyticsService"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "HvHost"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "vmickvpexchange"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "vmicguestinterface"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "vmicshutdown"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "vmicheartbeat"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "vmicvmsession"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "vmicrdv"
      },
      {
        "StartupType": "Manual",
        "OriginalType": "Automatic",
        "Name": "vmictimesync"
      }
    ]
  },
  "WPFEssTweaksTele": {
    "ScheduledTask": [
      {
        "Name": "Microsoft\\Windows\\Application Experience\\Microsoft Compatibility Appraiser",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Application Experience\\ProgramDataUpdater",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Autochk\\Proxy",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Customer Experience Improvement Program\\Consolidator",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Customer Experience Improvement Program\\UsbCeip",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\DiskDiagnostic\\Microsoft-Windows-DiskDiagnosticDataCollector",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Feedback\\Siuf\\DmClient",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Feedback\\Siuf\\DmClientOnScenarioDownload",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Windows Error Reporting\\QueueReporting",
        "State": "Disabled",
        "OriginalState": "Enabled"
      }
    ],
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\DataCollection",
        "type": "Dword",
        "value": 0,
        "name": "AllowTelemetry",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection",
        "OriginalValue": "1",
        "name": "AllowTelemetry",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "name": "ContentDeliveryAllowed",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "name": "OemPreInstalledAppsEnabled",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "name": "PreInstalledAppsEnabled",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "name": "PreInstalledAppsEverEnabled",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "name": "SilentInstalledAppsEnabled",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "name": "SubscribedContent-338387Enabled",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "name": "SubscribedContent-338388Enabled",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "name": "SubscribedContent-338389Enabled",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "name": "SubscribedContent-353698Enabled",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "name": "SystemPaneSuggestionsEnabled",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent",
        "OriginalValue": "0",
        "name": "DisableWindowsConsumerFeatures",
        "value": 1,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Siuf\\Rules",
        "OriginalValue": "0",
        "name": "NumberOfSIUFInPeriod",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection",
        "OriginalValue": "0",
        "name": "DoNotShowFeedbackNotifications",
        "value": 1,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent",
        "OriginalValue": "0",
        "name": "DisableTailoredExperiencesWithDiagnosticData",
        "value": 1,
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\AdvertisingInfo",
        "OriginalValue": "0",
        "name": "DisabledByGroupPolicy",
        "value": 1,
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\Windows Error Reporting",
        "OriginalValue": "0",
        "name": "Disabled",
        "value": 1,
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\DeliveryOptimization\\Config",
        "OriginalValue": "1",
        "name": "DODownloadMode",
        "value": 1,
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Remote Assistance",
        "OriginalValue": "1",
        "name": "fAllowToGetHelp",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\OperationStatusManager",
        "OriginalValue": "0",
        "name": "EnthusiastMode",
        "value": 1,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "OriginalValue": "1",
        "name": "ShowTaskViewButton",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\\People",
        "OriginalValue": "1",
        "name": "PeopleBand",
        "value": 0,
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "OriginalValue": "1",
        "name": "LaunchTo",
        "value": 1,
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\FileSystem",
        "OriginalValue": "0",
        "name": "LongPathsEnabled",
        "value": 1,
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\DriverSearching",
        "OriginalValue": "1",
        "name": "SearchOrderConfig",
        "value": "0",
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile",
        "OriginalValue": "1",
        "name": "SystemResponsiveness",
        "value": "0",
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile",
        "OriginalValue": "1",
        "name": "NetworkThrottlingIndex",
        "value": "4294967295",
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\Control Panel\\Desktop",
        "OriginalValue": "1",
        "name": "MenuShowDelay",
        "value": "1",
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\Control Panel\\Desktop",
        "OriginalValue": "1",
        "name": "AutoEndTasks",
        "value": "1",
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management",
        "OriginalValue": "0",
        "name": "ClearPageFileAtShutdown",
        "value": "0",
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SYSTEM\\ControlSet001\\Services\\Ndu",
        "OriginalValue": "1",
        "name": "Start",
        "value": "00000004",
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\Control Panel\\Mouse",
        "OriginalValue": "1",
        "name": "MouseHoverTime",
        "value": "400",
        "type": "String"
      },
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\LanmanServer\\Parameters",
        "OriginalValue": "1",
        "name": "IRPStackSize",
        "value": "20",
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Windows Feeds",
        "OriginalValue": "1",
        "name": "EnableFeeds",
        "value": "0",
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Feeds",
        "OriginalValue": "1",
        "name": "ShellFeedsTaskbarViewMode",
        "value": "2",
        "type": "Dword"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer",
        "OriginalValue": "1",
        "name": "HideSCAMeetNow",
        "value": "1",
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile\\Tasks\\Games",
        "OriginalValue": "1",
        "name": "GPU Priority",
        "value": "8",
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile\\Tasks\\Games",
        "OriginalValue": "1",
        "name": "Priority",
        "value": "6",
        "type": "Dword"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile\\Tasks\\Games",
        "OriginalValue": "High",
        "name": "Scheduling Category",
        "value": "High",
        "type": "String"
      }
    ],
    "service": [
      {
        "Name": "DiagTrack",
        "StartupType": "Disabled",
        "OriginalType": "Automatic"
      },
      {
        "Name": "dmwappushservice",
        "StartupType": "Disabled",
        "OriginalType": "Manual"
      },
      {
        "Name": "SysMain",
        "StartupType": "Disabled",
        "OriginalType": "Manual"
      }
    ],
    "InvokeScript": [
      "bcdedit /set `{current`} bootmenupolicy Legacy | Out-Null
        If ((get-ItemProperty -Path \"HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\" -Name CurrentBuild).CurrentBuild -lt 22557) {
            $taskmgr = Start-Process -WindowStyle Hidden -FilePath taskmgr.exe -PassThru
            Do {
                Start-Sleep -Milliseconds 100
                $preferences = Get-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\TaskManager\" -Name \"Preferences\" -ErrorAction SilentlyContinue
            } Until ($preferences)
            Stop-Process $taskmgr
            $preferences.Preferences[28] = 0
            Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\TaskManager\" -Name \"Preferences\" -Type Binary -Value $preferences.Preferences
        }
        Remove-Item -Path \"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\MyComputer\\NameSpace\\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}\" -Recurse -ErrorAction SilentlyContinue  

        # Group svchost.exe processes
        $ram = (Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1kb
        Set-ItemProperty -Path \"HKLM:\\SYSTEM\\CurrentControlSet\\Control\" -Name \"SvcHostSplitThresholdInKB\" -Type DWord -Value $ram -Force

        $autoLoggerDir = \"$env:PROGRAMDATA\\Microsoft\\Diagnosis\\ETLLogs\\AutoLogger\"
        If (Test-Path \"$autoLoggerDir\\AutoLogger-Diagtrack-Listener.etl\") {
            Remove-Item \"$autoLoggerDir\\AutoLogger-Diagtrack-Listener.etl\"
        }
        icacls $autoLoggerDir /deny SYSTEM:`(OI`)`(CI`)F | Out-Null

        #Timeout Tweaks cause flickering on Windows now
        #Remove-ItemProperty -Path \"HKCU:\\Control Panel\\Desktop\" -Name \"WaitToKillAppTimeout\" -ErrorAction SilentlyContinue
        #Remove-ItemProperty -Path \"HKCU:\\Control Panel\\Desktop\" -Name \"HungAppTimeout\" -ErrorAction SilentlyContinue
        #Remove-ItemProperty -Path \"HKLM:\\SYSTEM\\CurrentControlSet\\Control\" -Name \"WaitToKillServiceTimeout\" -ErrorAction SilentlyContinue
        #Remove-ItemProperty -Path \"HKCU:\\Control Panel\\Desktop\" -Name \"LowLevelHooksTimeout\" -ErrorAction SilentlyContinue
        #Remove-ItemProperty -Path \"HKCU:\\Control Panel\\Desktop\" -Name \"WaitToKillServiceTimeout\" -ErrorAction SilentlyContinue

        $ram = (Get-CimInstance -ClassName \"Win32_PhysicalMemory\" | Measure-Object -Property Capacity -Sum).Sum / 1kb
        Set-ItemProperty -Path \"HKLM:\\SYSTEM\\CurrentControlSet\\Control\" -Name \"SvcHostSplitThresholdInKB\" -Type DWord -Value $ram -Force
        "
    ]
  },
  "WPFEssTweaksWifi": {
    "registry": [
      {
        "Path": "HKLM:\\Software\\Microsoft\\PolicyManager\\default\\WiFi\\AllowWiFiHotSpotReporting",
        "Name": "Value",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\Software\\Microsoft\\PolicyManager\\default\\WiFi\\AllowAutoConnectToWiFiSenseHotspots",
        "Name": "Value",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      }
    ]
  },
  "WPFMiscTweaksLapPower": {
    "registry": [
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Power\\PowerThrottling",
        "Name": "PowerThrottlingOff",
        "Type": "DWord",
        "Value": "00000000",
        "OriginalValue": "00000001"
      },
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Power",
        "Name": "HiberbootEnabled",
        "Type": "DWord",
        "Value": "0000001",
        "OriginalValue": "0000000"
      }
    ]
  },
  "WPFMiscTweaksPower": {
    "registry": [
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Power\\PowerThrottling",
        "Name": "PowerThrottlingOff",
        "Type": "DWord",
        "Value": "00000001",
        "OriginalValue": "00000000"
      },
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Power",
        "Name": "HiberbootEnabled",
        "Type": "DWord",
        "Value": "0000000",
        "OriginalValue": "00000001"
      }
    ]
  },
  "WPFMiscTweaksExt": {
    "registry": [
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "Name": "HideFileExt",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      }
    ]
  },
  "WPFMiscTweaksUTC": {
    "registry": [
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\TimeZoneInformation",
        "Name": "RealTimeIsUniversal",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "0"
      }
    ]
  },
  "WPFMiscTweaksDisplay": {
    "registry": [
      {
        "path": "HKCU:\\Control Panel\\Desktop",
        "OriginalValue": "1",
        "name": "DragFullWindows",
        "value": "0",
        "type": "String"
      },
      {
        "path": "HKCU:\\Control Panel\\Desktop",
        "OriginalValue": "1",
        "name": "MenuShowDelay",
        "value": "200",
        "type": "String"
      },
      {
        "path": "HKCU:\\Control Panel\\Desktop\\WindowMetrics",
        "OriginalValue": "1",
        "name": "MinAnimate",
        "value": "0",
        "type": "String"
      },
      {
        "path": "HKCU:\\Control Panel\\Keyboard",
        "OriginalValue": "1",
        "name": "KeyboardDelay",
        "value": "0",
        "type": "DWord"
      },
      {
        "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "OriginalValue": "1",
        "name": "ListviewAlphaSelect",
        "value": "0",
        "type": "DWord"
      },
      {
        "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "OriginalValue": "1",
        "name": "ListviewShadow",
        "value": "0",
        "type": "DWord"
      },
      {
        "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "OriginalValue": "1",
        "name": "TaskbarAnimations",
        "value": "0",
        "type": "DWord"
      },
      {
        "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\VisualEffects",
        "OriginalValue": "1",
        "name": "VisualFXSetting",
        "value": "3",
        "type": "DWord"
      },
      {
        "path": "HKCU:\\Software\\Microsoft\\Windows\\DWM",
        "OriginalValue": "1",
        "name": "EnableAeroPeek",
        "value": "0",
        "type": "DWord"
      }
    ],
    "InvokeScript": [
      "Set-ItemProperty -Path \"HKCU:\\Control Panel\\Desktop\" -Name \"UserPreferencesMask\" -Type Binary -Value ([byte[]](144,18,3,128,16,0,0,0))"
    ]
  },
  "WPFEssTweaksDeBloat": {
    "appx": [
      "Microsoft.Microsoft3DViewer",
      "Microsoft.AppConnector",
      "Microsoft.BingFinance",
      "Microsoft.BingNews",
      "Microsoft.BingSports",
      "Microsoft.BingTranslator",
      "Microsoft.BingWeather",
      "Microsoft.BingFoodAndDrink",
      "Microsoft.BingHealthAndFitness",
      "Microsoft.BingTravel",
      "Microsoft.MinecraftUWP",
      "Microsoft.GamingServices",
      "Microsoft.GetHelp",
      "Microsoft.Getstarted",
      "Microsoft.Messaging",
      "Microsoft.Microsoft3DViewer",
      "Microsoft.MicrosoftSolitaireCollection",
      "Microsoft.NetworkSpeedTest",
      "Microsoft.News",
      "Microsoft.Office.Lens",
      "Microsoft.Office.Sway",
      "Microsoft.Office.OneNote",
      "Microsoft.OneConnect",
      "Microsoft.People",
      "Microsoft.Print3D",
      "Microsoft.SkypeApp",
      "Microsoft.Wallet",
      "Microsoft.Whiteboard",
      "Microsoft.WindowsAlarms",
      "microsoft.windowscommunicationsapps",
      "Microsoft.WindowsFeedbackHub",
      "Microsoft.WindowsMaps",
      "Microsoft.WindowsPhone",
      "Microsoft.WindowsSoundRecorder",
      "Microsoft.XboxApp",
      "Microsoft.ConnectivityStore",
      "Microsoft.CommsPhone",
      "Microsoft.ScreenSketch",
      "Microsoft.Xbox.TCUI",
      "Microsoft.XboxGameOverlay",
      "Microsoft.XboxGameCallableUI",
      "Microsoft.XboxSpeechToTextOverlay",
      "Microsoft.MixedReality.Portal",
      "Microsoft.XboxIdentityProvider",
      "Microsoft.ZuneMusic",
      "Microsoft.ZuneVideo",
      "Microsoft.Getstarted",
      "Microsoft.MicrosoftOfficeHub",
      "*EclipseManager*",
      "*ActiproSoftwareLLC*",
      "*AdobeSystemsIncorporated.AdobePhotoshopExpress*",
      "*Duolingo-LearnLanguagesforFree*",
      "*PandoraMediaInc*",
      "*CandyCrush*",
      "*BubbleWitch3Saga*",
      "*Wunderlist*",
      "*Flipboard*",
      "*Twitter*",
      "*Facebook*",
      "*Royal Revolt*",
      "*Sway*",
      "*Speed Test*",
      "*Dolby*",
      "*Viber*",
      "*ACGMediaPlayer*",
      "*Netflix*",
      "*OneCalendar*",
      "*LinkedInforWindows*",
      "*HiddenCityMysteryofShadows*",
      "*Hulu*",
      "*HiddenCity*",
      "*AdobePhotoshopExpress*",
      "*HotspotShieldFreeVPN*",
      "*Microsoft.Advertising.Xaml*"
    ],
    "InvokeScript": [
      "
        $TeamsPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, ''Microsoft'', ''Teams'')
        $TeamsUpdateExePath = [System.IO.Path]::Combine($TeamsPath, ''Update.exe'')
    
        Write-Host \"Stopping Teams process...\"
        Stop-Process -Name \"*teams*\" -Force -ErrorAction SilentlyContinue
    
        Write-Host \"Uninstalling Teams from AppData\\Microsoft\\Teams\"
        if ([System.IO.File]::Exists($TeamsUpdateExePath)) {
            # Uninstall app
            $proc = Start-Process $TeamsUpdateExePath \"-uninstall -s\" -PassThru
            $proc.WaitForExit()
        }
    
        Write-Host \"Removing Teams AppxPackage...\"
        Get-AppxPackage \"*Teams*\" | Remove-AppxPackage -ErrorAction SilentlyContinue
        Get-AppxPackage \"*Teams*\" -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    
        Write-Host \"Deleting Teams directory\"
        if ([System.IO.Directory]::Exists($TeamsPath)) {
            Remove-Item $TeamsPath -Force -Recurse -ErrorAction SilentlyContinue
        }
    
        Write-Host \"Deleting Teams uninstall registry key\"
        # Uninstall from Uninstall registry key UninstallString
        $us = (Get-ChildItem -Path HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall, HKLM:\\SOFTWARE\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall | Get-ItemProperty | Where-Object { $_.DisplayName -like ''*Teams*''}).UninstallString
        if ($us.Length -gt 0) {
            $us = ($us.Replace(''/I'', ''/uninstall '') + '' /quiet'').Replace(''  '', '' '')
            $FilePath = ($us.Substring(0, $us.IndexOf(''.exe'') + 4).Trim())
            $ProcessArgs = ($us.Substring($us.IndexOf(''.exe'') + 5).Trim().replace(''  '', '' ''))
            $proc = Start-Process -FilePath $FilePath -Args $ProcessArgs -PassThru
            $proc.WaitForExit()
        }
      "
    ]
  },
  "WPFEssTweaksOO": {
    "InvokeScript": [
      "curl.exe -s \"https://raw.githubusercontent.com/ChrisTitusTech/winutil/main/ooshutup10.cfg\" -o $ENV:temp\\ooshutup10.cfg
       curl.exe -s \"https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe\" -o $ENV:temp\\OOSU10.exe
       Start-Process $ENV:temp\\OOSU10.exe -ArgumentList \"$ENV:temp\\ooshutup10.cfg /quiet\"
       "
    ]
  },
  "WPFEssTweaksRP": {
    "InvokeScript": [
      "Enable-ComputerRestore -Drive \"$env:SystemDrive\"
       Checkpoint-Computer -Description \"RestorePoint1\" -RestorePointType \"MODIFY_SETTINGS\""
    ]
  },
  "WPFEssTweaksStorage": {
    "InvokeScript": [
      "Remove-Item -Path \"HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\StorageSense\\Parameters\\StoragePolicy\" -Recurse -ErrorAction SilentlyContinue"
    ]
  },
  "WPFMiscTweaksLapNum": {
    "Registry": [
      {
        "path": "HKU:\\.DEFAULT\\Control Panel\\Keyboard",
        "OriginalValue": "1",
        "name": "InitialKeyboardIndicators",
        "value": "0",
        "type": "DWord"
      }
    ]
  },
  "WPFMiscTweaksNum": {
    "Registry": [
      {
        "path": "HKU:\\.DEFAULT\\Control Panel\\Keyboard",
        "OriginalValue": "1",
        "name": "InitialKeyboardIndicators",
        "value": "80000002",
        "type": "DWord"
      }
    ]
  },
  "WPFEssTweaksRemoveEdge": {
    "InvokeScript": [
      "Invoke-WebRequest -useb https://raw.githubusercontent.com/ChrisTitusTech/winutil/main/Edge_Removal.bat | Invoke-Expression"
    ]
  },
  "WPFMiscTweaksDisableNotifications": {
    "registry": [
      {
        "Path": "HKCU:\\Software\\Policies\\Microsoft\\Windows\\Explorer",
        "Name": "DisableNotificationCenter",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "0"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\PushNotifications",
        "Name": "ToastEnabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      }
    ]
  },
  "WPFMiscTweaksRightClickMenu": {
    "InvokeScript": [
      "New-Item -Path \"HKCU:\\Software\\Classes\\CLSID\\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\" -Name \"InprocServer32\" -force -value \"\" "
    ]
  },
  "WPFEssTweaksDiskCleanup": {
    "InvokeScript": [
      "cleanmgr.exe /d C: /VERYLOWDISK"
    ]
  },
  "WPFMiscTweaksDisableTPMCheck": {
    "registry": [
      {
        "Path": "HKLM:\\SYSTEM\\Setup\\MoSetup",
        "Name": "AllowUpgradesWithUnsupportedTPM",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "0"
      }
    ]
  },
  "WPFMiscTweaksDisableUAC": {
    "registry": [
      {
        "path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System",
        "OriginalValue": "5",
        "name": "ConsentPromptBehaviorAdmin",
        "value": "0",
        "type": "DWord"
      }
    ]
  },
  "WPFMiscTweaksDisableMouseAcceleration": {
    "registry": [
      {
        "path": "HKCU:\\Control Panel\\Mouse",
        "OriginalValue": "1",
        "name": "MouseSpeed",
        "value": "0",
        "type": "String"
      },
      {
        "path": "HKCU:\\Control Panel\\Mouse",
        "OriginalValue": "6",
        "name": "MouseThreshold1",
        "value": "0",
        "type": "String"
      },
      {
        "path": "HKCU:\\Control Panel\\Mouse",
        "OriginalValue": "10",
        "name": "MouseThreshold2",
        "value": "0",
        "type": "String"
      }
    ]
  },
  "WPFMiscTweaksEnableMouseAcceleration": {
    "registry": [
      {
        "path": "HKCU:\\Control Panel\\Mouse",
        "OriginalValue": "1",
        "name": "MouseSpeed",
        "value": "1",
        "type": "String"
      },
      {
        "path": "HKCU:\\Control Panel\\Mouse",
        "OriginalValue": "6",
        "name": "MouseThreshold1",
        "value": "6",
        "type": "String"
      },
      {
        "path": "HKCU:\\Control Panel\\Mouse",
        "OriginalValue": "10",
        "name": "MouseThreshold2",
        "value": "10",
        "type": "String"
      }
    ]
  },
  "WPFEssTweaksDeleteTempFiles": {
    "InvokeScript": [
      "Get-ChildItem -Path \"C:\\Windows\\Temp\" *.* -Recurse | Remove-Item -Force -Recurse
    Get-ChildItem -Path $env:TEMP *.* -Recurse | Remove-Item -Force -Recurse"
    ]
  },
  "WPFEssTweaksRemoveCortana": {
    "InvokeScript": [
      "Get-AppxPackage -allusers Microsoft.549981C3F5F10 | Remove-AppxPackage"
    ]
  },
  "WPFEssTweaksDVR": {
    "registry": [
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_FSEBehavior",
        "Value": "2",
        "OriginalValue": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_Enabled",
        "Value": "0",
        "OriginalValue": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_DXGIHonorFSEWindowsCompatible",
        "Value": "1",
        "OriginalValue": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_HonorUserFSEBehaviorMode",
        "Value": "1",
        "OriginalValue": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_EFSEFeatureFlags",
        "Value": "0",
        "OriginalValue": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\GameDVR",
        "Name": "AllowGameDVR",
        "Value": "0",
        "OriginalValue": "1",
        "Type": "DWord"
      }
    ]
  },
  "WPFBingSearch": {
    "registry": [
      {
        "OriginalValue": "1",
        "Name": "BingSearchEnabled",
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search",
        "Type": "DWORD",
        "Value": "0"
      }
    ]
  }
}' | convertfrom-json
#region exception classes

    class WingetFailedInstall : Exception {
        [string] $additionalData

        WingetFailedInstall($Message) : base($Message) {}
    }
    
    class ChocoFailedInstall : Exception {
        [string] $additionalData

        ChocoFailedInstall($Message) : base($Message) {}
    }

    class GenericException : Exception {
        [string] $additionalData

        GenericException($Message) : base($Message) {}
    }
    
#endregion exception classes

$inputXML = $inputXML -replace 'mc:Ignorable="d"', '' -replace "x:N", 'N' -replace '^<Win.*', '<Window'
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
[xml]$XAML = $inputXML
#Read XAML

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
try { $Form = [Windows.Markup.XamlReader]::Load( $reader ) }
catch [System.Management.Automation.MethodInvocationException] {
    Write-Warning "We ran into a problem with the XAML code.  Check the syntax for this control..."
    Write-Host $error[0].Exception.Message -ForegroundColor Red
    If ($error[0].Exception.Message -like "*button*") {
        write-warning "Ensure your &lt;button in the `$inputXML does NOT have a Click=ButtonClick property.  PS can't handle this`n`n`n`n"
    }
}
catch {
    # If it broke some other way <img draggable="false" role="img" class="emoji" alt="????" src="https://s0.wp.com/wp-content/mu-plugins/wpcom-smileys/twemoji/2/svg/1f600.svg">
    Write-Host "Unable to load Windows.Markup.XamlReader. Double-check syntax and ensure .net is installed."
}

#===========================================================================
# Store Form Objects In PowerShell
#===========================================================================

$xaml.SelectNodes("//*[@Name]") | ForEach-Object { Set-Variable -Name "WPF$($_.Name)" -Value $Form.FindName($_.Name) }

$buttons = get-variable | Where-Object {$psitem.name -like "WPF*" -and $psitem.value -ne $null -and $psitem.value.GetType().name -eq "Button"}
foreach ($button in $buttons){
    $button.value.Add_Click({
        [System.Object]$Sender = $args[0]
        Invoke-WPFButton "WPF$($Sender.name)"
    })
}

$WPFToggleDarkMode.IsChecked = Get-WinUtilDarkMode

#===========================================================================
# Setup background config
#===========================================================================

#Load information in the background
Invoke-WPFRunspace -ScriptBlock {
    $sync.ConfigLoaded = $False

    $sync.ComputerInfo = Get-ComputerInfo

    $sync.ConfigLoaded = $True
} | Out-Null

#===========================================================================
# Shows the form
#===========================================================================

Invoke-WPFFormVariables

try{
    Install-WinUtilChoco
}
Catch [ChocoFailedInstall]{
    Write-Host "==========================================="
    Write-Host "--    Chocolatey failed to install      ---"
    Write-Host "==========================================="
}
$form.title = $form.title + " "
$Form.ShowDialog() | out-null
Stop-Transcript
