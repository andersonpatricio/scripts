#
# Script by Anderson Patricio (AP6) - anderson@patricio.ca 
# Source: github.com/andersonpatricio
#
Param(
    [string]$VMName
)

#retrieving Resource Group and Virtual vNIC
$vm = Get-AzVM | Where-Object { $_.Name -eq $vmName }
If (!$vm){
    Write-Host -Foregroundcolor 'Yellow' "The VM $vmName cannot be found in your current subscription."
    break
}Else{
    $rg = (Get-AzVM | Where-Object { $_.Name -eq $vmName } ).ResourceGroupName
    Write-Host "Stopping the VM $vmName..."
    Write-Host
    Stop-AzVM -Name $vmName -ResourceGroup $rg -Force
    Start-Sleep -Seconds 180
    $vtempNIC = Get-AzVM | Where-Object { $_.Name -eq $vmName }
    $vtempNIC = $vtempNIC.NetworkProfile.NetworkInterfaces.Id.Split("/")
    $vNIC = Get-AzNetworkInterface -Name $vTempNIC[-1]  -ResourceGroupName $rg
    $vNIC.EnableAcceleratedNetworking = $true
    $vNIC | Set-AzNetworkInterface
    Write-Host
    Write-Host "Starting the VM $vmName ..."
    Start-AzVM -ResourceGroup $rg -Name $vmName
}
