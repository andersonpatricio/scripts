#Importing modules...
Import-Module Az.Accounts
Import-Module Az.Resources
Import-Module Az.Compute
Import-Module Az.Automation
Import-Module Az.Storage
Import-Module Az.KeyVault

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
        $vText += "   OK    "
    }Elseif ($type -eq '1'){
        $vText += " WARNING "
    }Else{
        $vText += "  ERROR  " 
    }
    $vText += "]" 
    Write-Output $vText
}

Function VMInventory($VMName){
    $info = "" | Select Name, ResourceGroupName, Location, VMSize, OSDisk, DataDisk, SnapName, TotalDataDisks
    $vm = Get-AzVM -Name $VMName
    $info.Name = $vm.Name
    $info.ResourceGroupName = $vm.ResourceGroupName
    $info.Location = $vm.Location
    $info.VMSize = $vm.HardwareProfile.VmSize
    $info.OSDisk = $vm.StorageProfile.OsDisk
    $info.DataDisk = $vm.StorageProfile.DataDisks
    $info.TotalDataDisks = ($vm.StorageProfile.DataDisks).count
    $info.Snapname = $vSnapName

    #Making sure all disks attached to the VM are on the same version
    $vStatus = $False
    If (!($info.OSDisk.Name -like $vSnapName)) {$vStatus=$true} 
    ForEach ($disk in $info.DataDisk) {
    If (!($disk.Name -like  $vSnapName)) {$vStatus=$true; $vcount++}
    }
    if (!(Get-AzDisk | where-object { $_.Name -like $vSnapName })) {
        $vStatus = $true
    }
    If ($vstatus -eq $true) {
        Return $info
    }Else{
        Return $vstatus
    }
}

#
# Script Body
#

#Global Variables
$vResourceGroupname = "AP-Operations"
$vAutomationAccountName = "AA-CanC-Operations" 
$vaStorageAccount = Get-AzAutomationVariable $vAutomationAccountName -Name "StorageAccount" -ResourceGroupName $vResourceGroupname 

#Storage Connection
$StartTime = Get-Date
$EndTime = $startTime.AddHours(1.0)
$stgAccount = Get-AzStorageAccount -Name $vaStorageAccount.value -ResourceGroupName $vResourceGroupname 
$SASToken = New-AzStorageAccountSASToken -Service Blob -ResourceType Container,Object -Permission "racwdlup" -startTime $StartTime -ExpiryTime $EndTime -Context $StgAccount.Context
$stgcontext = New-AzStorageContext -storageAccountName $stgAccount.StorageAccountName -SasToken $SASToken

Msgbox "Subscription: " ((Get-AzContext).Name) 0 70
$RGs = Get-AzResourcegroup 
ForEach ($rg in $RGs){
    Msgbox "Resource Group: " $rg.ResourceGroupName 0 70
    $VMs= Get-AzVM -ResourceGroupName $rg.ResourceGroupName
    ForEach ($vm in $VMs){
        $tmp = VMInventory $vm.name
        If ($tmp) {
            Msgbox "Generating JSON: " $vm.name 0 70
            $vFileName = ((get-date -format "yyyy-MM-dd-") + ($vm.Name) + ".json") 
            $tmp | convertto-json | out-file $vFileName -Force
            $tmp2 = Set-AzStorageBlobContent -File $vFileName -Container vminventory -Context $stgcontext -Force          
        }
    }
}
