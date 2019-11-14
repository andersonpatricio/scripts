Param
(
    [Parameter (Mandatory= $true)]
    [string]$ResourceGroupName,
    [Parameter (Mandatory= $true)]
    [ValidateSet('on','off')]
    [string]$Action
)
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
Function Msgbox($caption,$message,$type,$MaxSize){
    if ($MaxSize -eq $null) { $MaxSize = 90}
    $sCaption = $caption.Length
    $sMessage = $Message.Length
    If (($sCaption + $sMessage) -ge $MaxSize) {
        $MaxSize = ($sCaption + $sMessage) + 20
    }
    $vDynamicSpace = $MaxSize - ($sCaption + $sMessage)
    $vDynamicSpace = " " * $vDynamicSpace
    $vText = $caption + $message + $vDynamicSpace + "[" 
    if ($type -eq '0') {
        $vText += "  OKAY   "
    }Elseif ($type -eq '1'){
        $vText += " WARNING "
    }Else{
        $vText += "  ERROR  " 
    }
    $vText += "]" 
    Write-Output $vText
}

Function fLoadData($ResourceGroupName){
    $ServerList=@{
        1 = @("*FS*")
        2 = @("*SQL*")
        3 = @("*APP0*")
        4 = @("*APP1*","*APP2*")
        5 = @("*MID*")
        6 = @("*FE*")a
        7 = @("*SRV*")
        8 = @("*RDS*")
        }
    For ($i=1; $i -le $ServerList.Keys.Count; $i++){
        If ($ServerList.Item($i).Count -ge 2) {
            For ($x=0; $x -le ($ServerList.Item($i).count -1); $x++){
                $temp = Get-AzVM -Name $ServerList.Item($i)[$x] -ResourceGroupName $ResourceGroupName -ErrorAction:SilentlyContinue
                If ($temp -eq $null) {
                    $ServerList.Item($i) = 'NotFound'
                } else {
                    $ServerList.Item($i)[$x] = $temp.Name
                }
                $temp=$null
            }
        } Else {
            $tVMname = ($ServerList.Item($i)).Trim() #| Out-String #-NoNewline
            $temp = Get-AzVM -Name $tVMName -ResourceGroupName $ResourceGroupName -ErrorAction:SilentlyContinue
            If ($temp -eq $null) {
                $ServerList.Item($i) = "NotFound"
            } else {
                $ServerList.Remove($i) 
                $ServerList.Add($i,$Temp.Name)
            }
            $temp = $null
            $tVMName = ""
        }
    }
    Return $ServerList
}
Function fVMGroup($ServerList,$ResourceGroupName,$Action,$Group){
    $ServerInfo = @()
    If (($ServerList.Item($Group)).Count -ne 1) {
        For ($x=0; $x -le (($ServerList.Item($Group)).count - 1); $x++){
            $ServerInfo += $ServerList.Item($Group)[$x]
        }
    } Else {
        $ServerInfo = $ServerList.Item($Group)
    }
    If ($ServerInfo.Count -ne 1) {
        $ServerInfoSize = $ServerInfo.Count - 1
    }else{
        $ServerInfoSize = 1
    }
    
    If ($Action -eq "on") {
        $vmPowerState = "VM running"
        If (($ServerList.Item($Group)).Count -ne 1) {
            For ($i=0; $i -le $ServerInfoSize; $i++){
                $temp = Start-AzVM -Name $ServerInfo[$i] -ResourceGroupName $ResourceGroupName -AsJob
            }
        } Else{
            $temp = Start-AzVM -Name $ServerInfo -ResourceGroupName $ResourceGroupName -AsJob
        }
    } Else{
        $vmPowerState = "VM deallocated"
        If (($ServerList.Item($Group)).Count -ne 1) {
            For ($i=0; $i -le $ServerInfoSize; $i++){
                $temp = Stop-AzVM -Name $ServerInfo[$i] -ResourceGroupName $ResourceGroupName -Force -AsJob
            }
        } Else {
            $temp = Stop-AzVM -Name $ServerInfo -ResourceGroupName $ResourceGroupName -Force -AsJob
        }
    }

    $vStatus= $False
    $controlSize = $ServerInfoSize
    while ($vStatus -eq $False) {
        If ($ServerInfo.count -eq 1) {
            $temp = Get-AzVM -Name $ServerInfo -Status | Where-Object  { $_.PowerState -eq $vmPowerState}
            If ($temp) {
                $controlSize = -1
            }
            $vCurrentServer = $serverinfo
        } Else {
            For ($i=0; $i -le $ServerInfoSize; $i++){
                If ($ServerInfo[$i]) {
                    $temp = Get-AzVM -Name $ServerInfo[$i] -Status | Where-Object  { $_.PowerState -eq $vmPowerState}
                    If ($temp) {
                        $ServerInfo[$i] = ""
                        $controlSize = $ControlSize - 1
                    }
                }
                $vCurrentServer = $ServerInfo[$i]
            }
        }
        If ($ControlSize -eq -1) {
            $vStatus = $True
        }
    }
}
Function TrackTime($Time){
    If (!($Time)) { Return Get-Date } Else {
        Return ((get-date) - $Time)
    }
}

#
# Main script
#
$vTime = TrackTime $vTime
$Servers = fLoadData $ResourceGroupName
write-output "List of the servers generated with this script"
$servers

If ($Action -eq "on"){
    ForEach ($key in ($servers.keys.GetEnumerator() | Sort-Object)){
        fVMGroup $Servers $ResourceGroupName $Action $key
        Msgbox ("Phase " + $key +" :") "Status complete" 0 70 
    }
}

If ($Action -eq "off"){
    ForEach ($key in ($servers.keys.GetEnumerator() | Sort-Object -Descending)){
        fVMGroup $Servers $ResourceGroupName $Action $key
        Msgbox ("Phase " + $key + " :") "Status complete" 0 70 
    }
}
$vTime = TrackTime $vTime
Msgbox "Information: " ("Total Time: " + $vTime.Minutes) 1 70


