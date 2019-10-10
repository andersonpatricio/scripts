#
# Script by Anderson Patricio (AP6) - anderson@patricio.ca 
# Source: github.com/andersonpatricio
#
Param(
    [string]$VMName,
    [string]$VirtualNetwork,
    [string]$VirtualSubnet
)

#Initial Validation and loading of the variables to use during the script
if (!(get-azvm -name $VMName)) {
    Write-Host
    Write-Host -ForegroundColor Yellow "[ERROR] VM was not found. Please check the VM name and make sure that you are in the right subscription"
    write-Host
    Break
    } Else {
        $tVM = Get-AzVM -Name $vmName
        $tDataDisks = (Get-AzVM -Name $vmName).StorageProfile.DataDisks
        $tOSDisk = (Get-AzVM -Name $vmName).StorageProfile.OSDisk
    }
    
If (!(Get-AZVirtualNetwork -Name $VirtualNetwork)){
    Write-Host
    Write-Host -ForegroundColor Yellow "[ERROR] Virtual Network was not found. Please check the Virtual Network name and make sure that you are in the right subscription"
    write-Host
    Break
} Else{
    $tvnet = Get-AZVirtualNetwork -Name $VirtualNetwork
    If (!(Get-AzVirtualNetworkSubnetConfig -Name $VirtualSubnet -VirtualNetwork $tvnet -ErrorAction SilentlyContinue)) {
        Write-Host
        Write-Host -ForegroundColor Yellow "[ERROR] Subnet was not found. Please check the Virtual Network name and make sure that you are in the right subscription"
        write-Host
        Break
    }
}
Write-Host
Write-Host -ForegroundColor Yellow "[Warning] This process is about to move the $VMName to the Virtual Network $Virtualnetwork."
Write-Host "Note #1: The VM will be deallocated, removed, and recreated with the same disks on the new virtual network"
Write-Host "Note #2: In case of any issues during the script, all VM configuration will be displayed, and can be used to recreate the VM manually"
Write-Host "Note #3: Between the VM deletion and VM creation, there is a delay of 2 minutes. Be patient."
$tAnswer = Read-Host -Prompt "Please, type [Yes] to confirm, or [no]"

If ($tAnswer -eq 'yes'){ 
    # Printing the information for future use
    Write-Host
    Write-Host -ForegroundColor Green 'Original VM Info. Use this info for validation or plan B in case of any error.'
    $tVM.Name
    $tVM.Location
    $tvm.HardwareProfile.VmSize
    $tVM.ResourceGroupName
    Write-Host -ForegroundColor Green 'Disk Information'
    $tDataDisks
    $tOSDisk 

    #Removing the VM
    Remove-AzVM -Name $tVM.Name -ResourceGroupName $tVM.ResourceGroupName -Force 
    Start-Sleep 120

    #Gathering information to create the new VM
    $vnet = Get-AzVirtualNetwork -Name $VirtualNetwork
    $vsubnet = Get-AzVirtualNetworkSubnetConfig -Name $VirtualSubnet -VirtualNetwork $vnet
    $VirtualMachine = New-AzVMConfig -VMName $tVM.Name -VMSize $tvm.HardwareProfile.VmSize
    $VirtualMachine = Set-AzVMOSDisk -VM $VirtualMachine -ManagedDiskId $tvm.StorageProfile.OsDisk.ManagedDisk.id -CreateOption Attach -Windows
    $nic = New-AzNetworkInterface -Name ($VirtualMachine.Name.ToLower()+'_vnic') -ResourceGroupName $tVM.ResourceGroupName -Location $tVM.Location -SubnetId $vsubnet.Id -Force
    $VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $nic.Id
    ForEach ($Disk in $tDataDisks){
        $VirtualMachine = Add-AzVMDataDisk -VM $VirtualMachine -Name $Disk.Name -CreateOption Attach -Lun $Disk.Lun -ManagedDiskId $Disk.ManagedDisk.Id -Caching $Disk.Caching
    }
    New-AzVM -ResourceGroupName $tvm.ResourceGroupName -Location $tvm.Location -VM $VirtualMachine -LicenseType 'Windows_Server'
}
