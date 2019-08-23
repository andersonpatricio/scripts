#Importing modules...
Import-Module Az.Accounts
Import-Module Az.Resources
Import-Module Az.Compute
Import-Module Az.Automation

#
# Connnection Phase
#
$connectionName = "AzureRunAsConnection"
try
{
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName
    Connect-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

#
# Functions
#
Function AddVMArray ($rg){
    $vTiers = '*FS0*','*APP0*','*FE0*','*Sec0*','*RDS0*'
    $fArray = @()
    For ($i=0; $i -le (($vTiers).Count - 1); $i++){
        #Debug: Write-Output $vtiers[$i]
        $tVM = Get-AzVM -Name $vTiers[$i] -ResourceGroupName $rg
        If ((($tVM).Count) -eq 0) {
            $fArray += 'none'
        }else{
            $tVM | ForEach{$fArray += $tVM.Name}
        }
    }
    return $fArray
}

Function VMGroup ($action, $ResourceGroup){
    Write-Output "VMGroup Funtion --> " $ResourceGroup
    Write-Output "VMGroup Funtion --> " $action
    If (($action -eq $null) -or ($ResourceGroup -eq $null)) { Write-Output "Parameter Null in VMGroup Function"; break}
    $vArray = @()
    $vArray = AddVMArray($ResourceGroup)
    $vNumberofServers= ($varray).count - 1

    If ($action -eq "On") {
        for ($i=0; $i -le $vNumberofServers; $i++){
            if ((get-azvm -Name $varray[$i]) -eq $null) { 
                Write-Output "-> Status: VM " $varray[$i] " does not exist" 
            } Else {
                If ((Get-AZVM -Name $varray[$i] -status).PowerState -ne "VM running") {
                    Start-AZVM -Name $varray[$i] -ResourceGroupName $ResourceGroup
                    #Start-AZVM -Name $varray[$i] -ResourceGroupName $ResourceGroup -WhatIf
                    Write-Output "-> Status: VM " $varray[$i] " is being started."
                    Start-Sleep -Seconds $StartupDelay
                } Else {
                    Write-Output "-> Status: VM " $varray[$i] " is already running."
                }
            }
        }
    }
    If ($action -eq "Off") {
        for ($i=$vNumberofServers; $i -ge 0; $i=$i-1){
            if ((get-azvm -Name $varray[$i]) -eq $null) { 
                Write-Output "-> Status: VM " $varray[$i] " does not exist" 
            } Else {
                If ((Get-AZVM -Name $varray[$i] -status).PowerState -ne "VM deallocated") {
                    Stop-AZVM -Name $varray[$i] -ResourceGroupName $ResourceGroup -Force
                    Write-Output "-> Status: VM " $varray[$i] " is being deallocated."
                    Start-Sleep -Seconds $ShutdownDelay
                } Else {
                    Write-Output "-> Status: VM " $varray[$i] " is already deallocated."
                }
            }
        }
    }
}

#
# Main script
#
$ShutdownDelay = 160
$StartupDelay = 350
$vCurrentDayofWeek = Get-Date -UFormat %u
$vCurrentHour = (Get-Date).Hour - 4

$gResourceGroups = Get-AzResourceGroup  | where-object {($_.ResourceGroupName -like '*grpServer*') -and ($_.Tags.PowerOnHours -ne $Null) -and ($_.Tags.PowerOnDaysOfWeek -like ("*" + $vCurrentDayofWeek + "*")) }

$gResourceGroups | % {
    Write-Output "==Working on " $_.ResourceGroupName " =====" 
    Write-Output "Working Days......:" $_.Tags.PowerOnDaysOfWeek
    Write-Output "Hours of the Day..:" $_.Tags.PowerOnHours 
    $vHourTemp = $_.Tags.PowerOnHours.Split("-")
    $vHourStart = $vHourTemp[0]
    $vHourEnd = $vHourTemp[1]
    If (($_.Tags.PowerOnDaysOfWeek -like $vCurrentDayofWeek) -and ( ($vCurrentHour -ge $vHourStart) -and ($vCurrentHour -le $vHourEnd))){
        $vAction = "On"
    }Else{
        $vAction = "Off"
    }
    Write-Output $vAction
    Write-Output $_.ResourceGroupName
        Write-Output $vEnv 
        Write-Output "Action: " $vaction
        Write-Output "rg....: " $_.ResourceGroupName
    VMGroup $vAction $_.ResourceGroupName
}
