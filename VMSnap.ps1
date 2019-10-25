Param(
    [Parameter(Mandatory=$true,HelpMessage="The VM Name in the current Azure subscription")]
    [ValidateScript({Get-AZVM -Name ($_)})]
    [string] $VMName,
    [Parameter(Mandatory=$true,HelpMessage="Short name for the Snapshot.")]
    [string] $Snapname,
    [switch] $Backup,
    [switch] $Restore
)

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

Function VMShortName($objName){
    Return $objName.Split(".")[0]
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

Function VMSnapshot($vmInfo){
    #Creating a new snapshot
    $vm_OSDisk = Get-AzDisk -ResourceGroupName $vmInfo.ResourceGroupName -DiskName $vmInfo.OSDisk.Name
    $vm_OSSnapConfig = New-AzSnapshotConfig -SourceUri $vm_OSDisk.Id -CreateOption Copy -Location $vmInfo.location
    $tNewName = (VMShortName $vminfo.OsDisk.name) + ".snap" + $vminfo.SnapName
    $vm_OSDiskSnap = New-AzSnapshot -SnapshotName $tNewName -Snapshot $vm_OSSnapConfig -ResourceGroupName $vmInfo.ResourceGroupName
    If ($vm_OSDiskSnap.ProvisioningState -eq 'Succeeded'){
        Msgbox "VMSnapshot (OS):" ("Creation for OSDisk " + $tNewName + " was successful.") 0 125  
    }Else{
        Msgbox "VMSnapshot (OS)" ("Creation for OSDisk " + $tNewName+ " failed.") 2 125 
    }
    #Creating the Data Disk(s) Snapshot(s)
    ForEach($disk in $vmInfo.DataDisk){
        #Validating if there is no snapshot and then creating a new one
        $vm_DataDisk = Get-AzDisk -ResourceGroupName $vmInfo.ResourceGroupName -DiskName $disk.name
        $vm_DataDiskSnapConfig = New-AzSnapshotConfig -SourceUri $vm_DataDisk.Id -CreateOption Copy -Location $vmInfo.location
        $tNewName = (VMShortName $Disk.name) + ".snap" + $vminfo.SnapName
        $vm_DataDiskSnap = New-AzSnapshot -SnapshotName $tNewName -Snapshot $vm_DataDiskSnapConfig -ResourceGroupName $vmInfo.ResourceGroupName
        If ($vm_DataDiskSnap.ProvisioningState -eq 'Succeeded'){
            Msgbox "VMSnapshot (Data):" ("Creation of " + $tNewName + " was successful.") 0 125  
        }Else{
            Msgbox "VMSnapshot (Data):" ("Creation of " + $tNewName + " failed.") 2 125  
        }
    }
    #Saving as JSON
    $vmInfo | convertto-json | out-file  ($vmInfo.Name + $vmInfo.Snapname + ".json") 
    Msgbox "VMSnapshot:" ("Creation of " + $vmInfo.Name +  $vmInfo.Snapname + ".json") 0 125  
}

Function RestoreSnap($vminfo){
    #OS Disk
    $tDiskType = (Get-AzDisk -DiskName $vminfo.OsDisk.name).sku.name
    #changes
    $tSnapShotNewName = (VMShortName $vminfo.OsDisk.name) + ".snap" + $vminfo.SnapName
    $tSnapShot = Get-AZSnapshot -SnapshotName $tSnapShotNewName
    #$tSnapShot = Get-AZSnapshot -SnapshotName ($vminfo.OsDisk.name + ".snap" + $vminfo.SnapName)
    $tDiskConfig = New-AzDiskConfig -SkuName $tDiskType -Location $vmInfo.location -CreateOption Copy -SourceResourceId $tsnapshot.Id  
    $tNewName = (VMShortName $vminfo.OsDisk.name) + $vmInfo.SnapName #Name change
    $temp = New-AzDisk -Disk $tDiskConfig -ResourceGroupName $vmInfo.ResourceGroupName -DiskName $tNewName
    If ($temp.ProvisioningState -eq "Succeeded") {
        Msgbox "RestoreSnap (OS):" ("New Disk " + $tnewName + " was created.") 0 125
    } Else {Msgbox "RestoreSnap (OS):" ("New Disk " + $tnewName + " creation failed") 2 125}
    $tNewName = $null
    $tSnapShotNewName = $null
    #Data Disk(s)
    ForEach($disk in $vmInfo.DataDisk){
        $tDiskType=$null
        $tSnapshot =$null
        $tDiskConfig=$null
        $tNewName=$null
        $tDiskType = (Get-AzDisk -DiskName $disk.name).sku.name
        #changes
        $tSnapShotNewName = (VMShortName $Disk.name) + ".snap" + $vminfo.SnapName
        $tSnapShot = Get-AZSnapshot -SnapshotName $tSnapShotNewName
        #$tSnapShot = Get-AZSnapshot -SnapshotName ($vminfo.OsDisk.name + ".snap" + $vminfo.SnapName)
        $tDiskConfig = New-AzDiskConfig -SkuName $tDiskType -Location $vmInfo.location -CreateOption Copy -SourceResourceId $tsnapshot.Id
        $tNewName = (VMShortName $Disk.name) + $vmInfo.SnapName  #name change
        If ($tnewName -ne $False) {
            $temp = New-AzDisk -Disk $tDiskConfig -ResourceGroupName $vmInfo.ResourceGroupName -DiskName $tNewName
            If ($temp.ProvisioningState -eq "Succeeded") {
                Msgbox "RestoreSnap (Data):" ("New Disk " + $tnewName + " was created.") 0 125
            } Else {Msgbox "RestoreSnap (Data):" ("New Disk " + $tnewName + " creation failed") 2 125}
        } else {
            Msgbox "RestoreSnap (Data): " ("Name couldnt be found " + $tNewName) 2 125
        }       
        $tNewName = $null
        $tSnapShotNewName = $null
    }
}

Function VMRestore($vmInfo){
    #OS Disk
    $tNewOSDiskName = (VMShortName $vminfo.OsDisk.name) + $vmInfo.SnapName #name change
    $tVM = Get-AzVM -Name $vminfo.Name
    $New_OSDisk = Get-AzDisk -Name $tNewOSDiskName -ResourceGroupName $vmInfo.ResourceGroupName
    $temp = Set-AzVMOSDisk -VM $tVM -ManagedDiskId $New_OSDisk.Id -Name $New_OSDisk.Name
    $temp = Update-AzVM -VM $tVM -ResourceGroupName $vmInfo.ResourceGroupName
    If ($temp.StatusCode -eq "OK")  {
        Msgbox "Swap Disk (OS):" ("The OS Disk " + $New_OSDisk.Name + " was swapped successful.") 0 125
    } Else {
        Msgbox "Swap Disk (OS):" ("The OS Disk " + $New_OSDisk.Name + " failed during the swap process. Manual investigation required.") 2 125
    }
    ForEach($disk in ($vmInfo.DataDisk)){
        #removing the disk
        $temp = Remove-AZVMDataDisk -VM $tVM -Name $disk.Name
        $temp = Update-AzVM -VM $tVM -ResourceGroupName $vminfo.ResourceGroupName
        #adding the new disk
        $tNewDataDiskName = (VMShortName $Disk.name) + $vmInfo.SnapName #name change
        $tDiskID = Get-AZDisk -diskname  $tNewDataDiskName
        $temp = Add-AzVMDataDisk -CreateOption Attach -Lun $disk.Lun -VM $tVM -ManagedDiskId $tDiskID.ID -Caching $disk.caching
        $temp = Update-AzVM -VM $tVM -ResourceGroupName $vmInfo.ResourceGroupName
        If ($temp.StatusCode -eq "OK") {
            Msgbox "Swap Disk(s) (Data):" ("The Data Disk " + $Disk.Name + " was swapped by " + $tNewDataDiskName + " successful.") 0 125
        } Else {
            Msgbox "Swap Disk(s) (Data):" ("The Data Disk " + $Disk.Name + " failed during the swap process. Manual investigation required.") 0 125
        }
    }
}

#Body Script
If (($PSBoundParameters.Keys.Contains("backup")) -and ($PSBoundParameters.Keys.Contains("restore"))) {
    Msgbox "INPUT ERROR:" "You need to select either Backup or Restore switch." 2 125
    break
}

Write-Host
Write-Host -ForegroundColor Yellow "Working on Virtual Machine...: " $VMName
Write-Host -ForegroundColor Yellow "Creating the snapshot........:" $Snapname
Write-Host     

$global:vSnapName = "." + $Snapname
$CurrentVM = VMInventory $VMName

If ($PSBoundParameters.Keys.Contains("backup")) {
    VMSnapshot $CurrentVM
}
If ($PSBoundParameters.Keys.Contains("restore")) {
        RestoreSnap $CurrentVM
        VMRestore $CurrentVM   
}
