#
# Script Clone and replace disks
# by Anderson Patricio AP6 (anderson@patricio.ca)

Param(
    [string] $VMName
)

#Function Msgbox
#Creates the Linux-like message outputs throughout the script
Function Msgbox($caption,$message,$type,$MaxSize){
    if ($MaxSize -eq $null) { $MaxSize = 125}
    $sCaption = $caption.Length
    $sMessage = $Message.Length
    If (($sCaption + $sMessage) -ge $MaxSize) {
        $MaxSize = ($sCaption + $sMessage) + 20
    }
    $vDynamicSpace = $MaxSize - ($sCaption + $sMessage)
    $vDynamicSpace = " " * $vDynamicSpace
    Write-Host $caption $message $vDynamicSpace " [" -NoNewline
    if ($type -eq '0') {
        Write-Host -ForegroundColor Green " OK " -NoNewline
    }Elseif ($type -eq '1'){
        Write-Host -ForegroundColor Yellow " WARNING " -NoNewline
    }Else{
        Write-Host -ForegroundColor Red " ERROR " -NoNewline
    }
    Write-Host "]" 
}
#Function NewName
#Uses the Disk Name and gives the new name (possible options are "" or ".restore")
Function NewName($Name,$vmInfo){
    If ($vminfo.NewName -eq ""){
        Return ($name).Substring(0,$name.Length -8)
    } else {
        Return $Name + $vminfo.NewName
    }
}
#Function VMInventory
#Create the Array with all VM and Disk information, validate if all disks are okay, validate if both versions exist in the subscription, saves as JSON file the current VM info.
Function VMInventory($VMName){
    $info = "" | Select Name, ResourceGroupName, Location, VMSize, OSDisk, DataDisk, NewName, TotalDataDisks
    $vm = Get-AzVM -Name $VMName
    If (!($vm)) { Msgbox "VMInventory:" "VM could not be found on the current subscription." 2 125; Return $False}
    $info.Name = $vm.Name
    $info.ResourceGroupName = $vm.ResourceGroupName
    $info.Location = $vm.Location
    $info.VMSize = $vm.HardwareProfile.VmSize
    $info.OSDisk = $vm.StorageProfile.OsDisk
    $info.DataDisk = $vm.StorageProfile.DataDisks
    $info.TotalDataDisks = ($vm.StorageProfile.DataDisks).count

    #Making sure all disks attached to the VM are on the same version
    $tOSVersion = ""
    $tDataVersion=""
    $vCount=0
    If (!($info.OSDisk.Name -like "*.restore")) {$tOSVersion =".restore"} 
    ForEach ($disk in $info.DataDisk) {
        If (!($disk.Name -like "*.restore")) {$tDataVersion =".restore"; $vcount++}
    }
    If ($tOSVersion -eq $tDataVersion){
        If (($vcount -eq $info.TotalDataDisks) -or ($vcount -eq 0)) {
            Msgbox "VMInventory:" "All disks share the same version: $tOSVersion" 0 125 
            $info.NewName = $tOSVersion
        } Else {
            Msgbox "VMInventory:" "Not all Data disks agree on the version: $tDataVersion" 2 125
            Return $False
        }
    } Else {
        Msgbox "VMInventory:" "We have discrepancies OS: $tOSVersion and Data: $tDataVersion" 2 125 
        Return $False
    }
    #validating if both versions are not in the same resource group
    $tNewName = NewName $info.OSDisk.Name $info
    If (Get-AZDisk -DiskName $tNewName) {
        Msgbox "VMInventory:" "The previous OS Disk is still present in the Resource Group. Please delete." 2 125
        Return $False
    } 

    ForEach ($disk in $info.DataDisk) {
        $tNewName = NewName $Disk.Name $info
        If (Get-AZDisk -DiskName $tNewName){
            Msgbox "VMInventory:" "At leat one previous data disk is still present in the Resource Group. Please delete." 2 125
            Msgbox "VMInventory:" ("The current disk is still present: " + $tNewName) 2 125
            Return $False
        }
    }
    Msgbox "VMInventory:" ("Switching the the following version (none or .restore):" + $info.NewVersion) 1 125
    #Saving as JSON
    $info | convertto-json | out-file  ($info.Name + ".json") 
    Return $info
}
#Function VMSnapshot
#Deletes all existent Snapshots, create new ones
Function VMSnapshot($vmInfo){
    #Deleting Snapshots of the existent disks
    If (Get-AzSnapshot -Name ($vmInfo.OSDisk.Name + ".snap")){
        Msgbox "VMSnapshot (OS):" ("The current OS Disk snapshot will be deleted." + $vmInfo.OSDisk.Name + ".snap") 1 125
        $tmp = Remove-AzSnapshot -Name ($vmInfo.OSDisk.Name + ".snap") -ResourceGroupName $vmInfo.ResourceGroupName -Force
        If ($tmp.Status -eq 'Succeeded') {
            Msgbox "VMSnapshot (OS):" ("Disk Snapshot " + $vmInfo.OSDisk.Name + ".snap Deletion was successful.") 0 125   
        }
    }
    #Previous version deletion
    $tNewName = NewName $vmInfo.OSDisk.Name $vmInfo
    If (Get-AzSnapshot -Name ($tNewName + ".snap")){
        Msgbox "VMSnapshot (OS):" ("The old OS Disk snapshot will be deleted." + $tNewName + ".snap") 1 125
        $tmp = Remove-AzSnapshot -Name ($tNewName + ".snap") -ResourceGroupName $vmInfo.ResourceGroupName -Force
        If ($tmp.Status -eq 'Succeeded') {
            Msgbox "VMSnapshot (OS):" ("Old Disk Snapshot " + $tNewName + ".snap Deletion was successful.") 0 125   
        }
        $tNewName = $null
    }

    #Creating a new snapshot
    $vm_OSDisk = Get-AzDisk -ResourceGroupName $vmInfo.ResourceGroupName -DiskName $vmInfo.OSDisk.Name
    $vm_OSSnapConfig = New-AzSnapshotConfig -SourceUri $vm_OSDisk.Id -CreateOption Copy -Location $vmInfo.location
    $vm_OSDiskSnap = New-AzSnapshot -SnapshotName ($vmInfo.OSDisk.Name + ".snap") -Snapshot $vm_OSSnapConfig -ResourceGroupName $vmInfo.ResourceGroupName
    If ($vm_OSDiskSnap.ProvisioningState -eq 'Succeeded'){
        Msgbox "VMSnapshot (OS):" ("Creation for OSDisk " + $vmInfo.OSDisk.Name + " was successful.") 0 125  
    }Else{
        Msgbox "VMSnapshot (OS)" ("Creation for OSDisk " + $vmInfo.OSDisk.Name + " failed.") 2 125  
    }

    #Creating the Data Disk(s) Snapshot(s)
    ForEach($disk in $vmInfo.DataDisk){
        #Validating if there is no snapshot and then creating a new one
        If (Get-AzSnapshot -Name ($disk.Name + ".snap")){
            Msgbox "VMSnapshot (Data):" ("The current snapshot " + ($disk.Name + ".snap") + " will be deleted.") 1 125
            $tmp = Remove-AzSnapshot -Name ($disk.Name + ".snap") -ResourceGroupName $vmInfo.ResourceGroupName -Force
            If ($tmp.Status -eq 'Succeeded') {
                Msgbox "VMSnapshot (Data):" ("The snapshot " + ($disk.Name + ".snap") + " was deleted.") 0 125   
            }
        }
        #Validating Previous
        $tNewName = NewName $disk.name $vmInfo
        If (Get-AzSnapshot -Name ($tNewName + ".snap")){
            Msgbox "VMSnapshot (Data):" ("The previous snapshot " + ($tNewName + ".snap") + " will be deleted.") 1 125
            $tmp = Remove-AzSnapshot -Name ($tNewName + ".snap") -ResourceGroupName $vmInfo.ResourceGroupName -Force
            If ($tmp.Status -eq 'Succeeded') {
                Msgbox "VMSnapshot (Data):" ("The snapshot " + ($tNewName + ".snap") + " was deleted.") 0 125   
            }
            $tNewName = $null
        }
        $vm_DataDisk = Get-AzDisk -ResourceGroupName $vmInfo.ResourceGroupName -DiskName $disk.name
        $vm_DataDiskSnapConfig = New-AzSnapshotConfig -SourceUri $vm_DataDisk.Id -CreateOption Copy -Location $vmInfo.location
        $vm_DataDiskSnap = New-AzSnapshot -SnapshotName ($Disk.Name + ".snap") -Snapshot $vm_DataDiskSnapConfig -ResourceGroupName $vmInfo.ResourceGroupName
        If ($vm_DataDiskSnap.ProvisioningState -eq 'Succeeded'){
            Msgbox "VMSnapshot (Data):" ("Creation of " + $disk.name + " was successful.") 0 125  
        }Else{
            Msgbox "VMSnapshot (Data):" ("Creation of " + $disk.name + " failed.") 2 125  
        }
    }
}
#Function RestoreSnap
#uses the previous snapshots and create managed disks
Function RestoreSnap($vminfo){
    #OS Disk
    $tDiskType = (Get-AzDisk -DiskName $vminfo.OsDisk.name).sku.name
    $tSnapShot = Get-AZSnapshot -SnapshotName ($vminfo.OsDisk.name + ".snap")
    $tDiskConfig = New-AzDiskConfig -SkuName $tDiskType -Location $vmInfo.location -CreateOption Copy -SourceResourceId $tsnapshot.Id
    $tNewName = NewName $vminfo.OsDisk.name $vmInfo
    $temp = New-AzDisk -Disk $tDiskConfig -ResourceGroupName $vmInfo.ResourceGroupName -DiskName $tNewName
    If ($temp.ProvisioningState -eq "Succeeded") {
        Msgbox "RestoreSnap (OS):" ("New Disk " + $tnewName + " was created.") 0 125
    } Else {Msgbox "RestoreSnap (OS):" ("New Disk " + $tnewName + " creation failed") 2 125}
    $tNewName = $null

    #Data Disk(s)
    ForEach($disk in $vmInfo.DataDisk){
        $tDiskType=$null
        $tSnapshot =$null
        $tDiskConfig=$null
        $tNewName=$null

        $tDiskType = (Get-AzDisk -DiskName $disk.name).sku.name
        $tSnapShot = Get-AZSnapshot -SnapshotName ($disk.name + ".snap")
        $tDiskConfig = New-AzDiskConfig -SkuName $tDiskType -Location $vmInfo.location -CreateOption Copy -SourceResourceId $tsnapshot.Id
        $tNewName = NewName $disk.name $vminfo
        If ($tnewName -ne $False) {
            $temp = New-AzDisk -Disk $tDiskConfig -ResourceGroupName $vmInfo.ResourceGroupName -DiskName $tNewName
            If ($temp.ProvisioningState -eq "Succeeded") {
                Msgbox "RestoreSnap (Data):" ("New Disk " + $tnewName + " was created.") 0 125
            } Else {Msgbox "RestoreSnap (Data):" ("New Disk " + $tnewName + " creation failed") 2 125}
        } else {
            Msgbox "RestoreSnap (Data): " ("Name couldnt be found " + $tNewName) 2 125
        }       
    }
}
#Function SwitchDisks
#Replace the current VM with the new Managed Disks
Function SwitchDisks($vmInfo){
    #OS Disk
    $tNewOSDiskName = NewName $vminfo.OsDisk.name $vmInfo
    $tVM = Get-AzVM -Name $vminfo.Name
    $New_OSDisk = Get-AzDisk -Name $tNewOSDiskName -ResourceGroupName $vmInfo.ResourceGroupName
    $temp = Set-AzVMOSDisk -VM $tVM -ManagedDiskId $New_OSDisk.Id -Name $New_OSDisk.Name
    $temp = Update-AzVM -VM $tVM -ResourceGroupName $vmInfo.ResourceGroupName
    If ($temp.StatusCode -eq "OK")  {
        Msgbox "SwitchDisks (OS):" ("The OS Disk " + $New_OSDisk.Name + " was swapped successful.") 0 125
    }


    foreach($disk in ($vmInfo.DataDisk)){
        #removing the disk
        $temp = Remove-AZVMDataDisk -VM $tVM -Name $disk.Name
        $temp = Update-AzVM -VM $tVM -ResourceGroupName $vminfo.ResourceGroupName
        #adding the new disk
        $tNewDataDiskName = NewName $disk.name $vmInfo
        $tDiskID = Get-AZDisk -diskname  $tNewDataDiskName
        $temp = Add-AzVMDataDisk -CreateOption Attach -Lun $disk.Lun -VM $tVM -ManagedDiskId $tDiskID.ID -Caching $disk.caching
        $temp = Update-AzVM -VM $tVM -ResourceGroupName $vmInfo.ResourceGroupName
        If ($temp.StatusCode -eq "OK") {
            Msgbox "SwitchDisks (Data):" ("The Data Disk " + $Disk.Name + " was swapped successful.") 0 125
        }
    }
}

#Body Script
Write-Host
Write-Host -ForegroundColor Yellow "Working on " $VMName
Write-Host 
$CurrentVM = VMInventory $VMName
$tStart = Get-Date
If ($CurrentVM -ne $False) {
    $temp = Stop-AzVM -Name $VMName -ResourceGroup $CurrentVM.ResourceGroupName -Force
    If ($temp.Status -eq "Succeeded") {
        Msgbox "Stop VM:" ("The VM " + $VMName + " is stopped.") 0 125
    }
    Start-Sleep 180
    VMSnapshot $CurrentVM
    start-sleep 15
    RestoreSnap $CurrentVM
    start-sleep 15
    SwitchDisks $CurrentVM
    $temp =  Start-AzVM -Name $VMName -ResourceGroup $CurrentVM.ResourceGroupName
    If ($temp.Status -eq "Succeeded") {
        Msgbox "Start VM:" ("The VM " + $VMName + " was started with the new cloned disks.") 0 125
    }
    Msgbox "Operation Total time:" ((Get-Date) - $tStart) 1 125
} Else {
    Msgbox "FATAL Error:" "Please correct the errors provided and retry the script" 2 125
}
