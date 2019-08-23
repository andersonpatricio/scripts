#
# Script: AzFwMaintenance.ps1
# Script by Anderson Patricio (AP6) https://github.com/andersonPatricio 
#
param (
    [string]$Operation = "Off",
    [String]$ResourceGroup="",
    [string]$FWPublicIPName = "azureFirewalls-ip",
    [string]$VNETName='<VNET-Name>'
)
#Validating parameters...
If (!$VNETName){
    $VNETName = Read-Host -Prompt "Please provide the Virtual Network Name (VNET) or Ctrl+C to abort?"
}

#Importing Az modules...
Import-Module Az.Resources
Import-Module Az.Network

#
# Main script
#
If (!$ResourceGroup){
   Write-Host -ForegroundColor Yellow "Resource Group was not specified, the script will run in the entire subscription!"
    $fws = Get-AzResource -ResourceType 'Microsoft.Network/azureFirewalls'
} Else{
    $fws = Get-AzResource -ResourceType 'Microsoft.Network/azureFirewalls' -ResourceGroupName $ResourceGroup
}
If ($fws -eq $null) {
    Write-Output "The Runbook could not find any Azure Firewall on the $ResourceGroup specified."
    Exit
} Else {
    Write-Output "We have found Azure Firewalls. We are going to validate and if doable we will take them $Operation."
}

if ($Operation -eq "on") {
    Write-Output "Starting the Azure Firewall(s)..."
    ForEach ($fw in $fws){
        Write-Output $fw.Name 
        $azfw = Get-AzFirewall -Name $fw.Name -ResourceGroupName $ResourceGroup
        $vPublicIP = Get-AzPublicIpAddress -Name $FWPublicIPName -ResourceGroupName $ResourceGroup
        $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Name $VNETName
        $azfw.Allocate($vnet,$vpublicip)
        Set-AzFirewall -AzureFirewall $azfw
    }
} Else {
    Write-Output 'Stopping the Azure Firewall(s)...'
    ForEach ($fw in $fws){
        Write-Output "Stopping " $fw.Name 
        $azfw = Get-AzFirewall -Name $fw.name -ResourceGroupName $ResourceGroup
        $azfw.Deallocate()
        Set-AzFirewall -AzureFirewall $azfw
    }
}


