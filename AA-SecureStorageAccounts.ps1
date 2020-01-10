#
# Importing modules...
#
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
        -Subscription 'subscriptionname.here' `
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
    if ($MaxSize -eq $null) { $MaxSize = 95}
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

#
# Script Body
#

#Loading JSON File from the Storage Account container designated for this script
$vResourceGroupname = "ResourceGroupName"
$vAutomationAccountName = "svc-azdev-automation" 
$vContainerName = "storageaccount-security-automated"
#I'm retrieving the storage account name from a Azure Automation variable. You should add that or specify in the code.
$vaStorageAccount = Get-AzAutomationVariable $vAutomationAccountName -Name "StorageAccount" -ResourceGroupName $vResourceGroupname 
$StartTime = Get-Date
$EndTime = $startTime.AddHours(1.0)
$stgAccount = Get-AzStorageAccount -Name $vaStorageAccount.value -ResourceGroupName $vResourceGroupname 
$SASToken = New-AzStorageAccountSASToken -Service Blob -ResourceType Container,Object -Permission "racwdlup" -startTime $StartTime -ExpiryTime $EndTime -Context $StgAccount.Context
$stgcontext = New-AzStorageContext -storageAccountName $stgAccount.StorageAccountName -SasToken $SASToken
$tmpBlobCopyOperation = Get-AzStorageBlobContent -Container $vContainerName -Blob ("PublicIPs.json") -Destination (Get-Location).path -Context $stgcontext

#Global Variables
$JSONPublicIPs = Get-Content -Raw -Path ((Get-Location).Path + "\PublicIPs.json") | ConvertFrom-Json
$vEndPoint = "Microsoft.Storage"
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

#Just remove the ResourceGroupName from the line below to get the entire subscription
$VNETs = Get-AzVirtualNetwork | where { ($_.Location -eq "canadacentral") -or ($_.location -eq "canadaeast")}

ForEach ($SingleVNET in $VNETs){
    $Subnets = Get-AzVirtualNetwork -Name $SingleVNET.Name | Get-AzVirtualNetworkSubnetConfig
    ForEach ($SingleSubnet in $Subnets){
        $tmp = Set-AzVirtualNetworkSubnetConfig -Name $SingleSubnet.Name -VirtualNetwork $SingleVNET -AddressPrefix $SingleSubnet.AddressPrefix -ServiceEndpoint $vEndPoint
    }
    Msgbox "Updating Virtual Network:" $SingleVNET.Name 0
    $tmp = $SingleVNET | Set-AzVirtualNetwork
}

# Storage Account Configuration
$StorageAccounts = Get-AzStorageAccount | Where-Object { (($_.Tags.Keys -notcontains "ms-resource-usage")  -and ( ($_.Location -eq "canadacentral") -or ($_.Location -eq "canadaeast"))) -and ($_.StorageAccountName -ne 'stgAccountName') }
Msgbox "Stage 1/2: " "Enabling Firewall and specific IP addresses" 0
ForEach ($SingleStorageAccount in $StorageAccounts){
    Msgbox "Updating Storage Account: " $SingleStorageAccount.StorageAccountName 0
    $tmp = Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $SingleStorageAccount.ResourceGroupName -Name $SingleStorageAccount.StorageAccountName -DefaultAction Deny 
    If ($tmp) {Msgbox "Storage Account (Default Action): " "Configured to Deny (required when using Virtual Network" 0}
    $tmp = Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $SingleStorageAccount.ResourceGroupName -Name $SingleStorageAccount.StorageAccountName -IPRule $JSONPublicIPs -ErrorVariable tmpErrorVar -ErrorAction SilentlyContinue
    If ($tmp) {
        Msgbox "Storage Account (Public IPs Action): " "All IPs from the PublicIPs.json were published" 0
    } Else {
            If ($tmpErrorVar) { 
                If ($tmpErrorVar[0].Exception.Message.Contains("networkAcls.virtualNetworkRules[*].id(unique)")) {
                    Msgbox "Storage Account (Public IPs Action): " "There are duplicated entries on the list. Check the JSON file" 2
                } 
                If ($tmpErrorVar[0].Exception.Message.Contains("networkAcls.ipRule[*].value")) {
                    Msgbox "Storage Account (Public IPs Action):" "There are wrong IPs/Subnets in the JSON file." 2
                }  
            }
    }
    #Cleaning up non-existent subnets
    $NonExistentSubnets = (Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $SingleStorageAccount.ResourceGroupName -Name $SingleStorageAccount.StorageAccountName).VirtualNetworkRules | Where-Object { $_.State -eq "NetworkSourceDeleted" }
    If ($NonExistentSubnets){
        ForEach ($SingleNonExistentSubnet in $NonExistentSubnets) {
            $tmp = Remove-AzStorageAccountNetworkRule -ResourceGroupName $SingleStorageAccount.ResourceGroupName -Name $SingleStorageAccount.StorageAccountName -VirtualNetworkId $SingleNonExistentSubnet.VirtualNetworkResourceId
            If ($tmp) {
                Msgbox "Virtual network Rule (deleted subnet):" "Subnet marked as non-existent was removed." 0
            }
        }
    }
}
Msgbox "Stage 2/2: " "Adding Virtual Networks within the Storage Account Firewall" 0
$StorageAccounts = $null
$SingleStorageAccount = $null
$SingleVNET = $null
$VNETs = $null
$StorageAccounts = Get-AzStorageAccount | Where-Object { (($_.Tags.Keys -notcontains "ms-resource-usage")  -and ( ($_.Location -eq "canadacentral") -or ($_.Location -eq "canadaeast"))) -and ($_.StorageAccountName -ne 'StorageAccountName') }
$VNETs = Get-AzVirtualNetwork | where { ($_.Location -eq "canadacentral") -or ($_.location -eq "canadaeast")}

ForEach ($SingleStorageAccount in $StorageAccounts){
    Msgbox "Virtual Network Updates on the following Storage Account: " $SingleStorageAccount.StorageAccountName 0
    $tmpSTGRules = $null
    $tmpStgRules = Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $SingleStorageAccount.ResourceGroupName -Name $SingleStorageAccount.StorageAccountName
    ForEach ($SingleVNET in $VNETs){
        $Subnets = Get-AzVirtualNetwork -Name $SingleVNET.Name | Get-AzVirtualNetworkSubnetConfig
        ForEach ($SingleSubnet in $Subnets){
            If ($tmpSTGRules.VirtualNetworkRules.Count -ne 0)  {
                If ($tmpStgRules.virtualNetworkRules.VirtualNetworkResourceId.Contains($SingleSubnet.Id) -eq $False ) {
                    $tmpOperation = Add-AzStorageAccountNetworkRule -ResourceGroupName $SingleStorageAccount.ResourceGroupName -Name $SingleStorageAccount.StorageAccountName -VirtualNetworkResourceId $SingleSubnet.Id #-ErrorVariable tmpErrorVar -ErrorAction SilentlyContinue
                }
            } Else{
                $tmpOperation = Add-AzStorageAccountNetworkRule -ResourceGroupName $SingleStorageAccount.ResourceGroupName -Name $SingleStorageAccount.StorageAccountName -VirtualNetworkResourceId $SingleSubnet.Id #-ErrorVariable tmpErrorVar -ErrorAction SilentlyContinue
            }
        }
    }
    start-sleep 15
}
Msgbox "Operation Complete: " "All Storage Accounts were updated." 0
