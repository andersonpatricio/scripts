workflow RGSnapWorkflow
{
    Param
    (
        [Parameter (Mandatory= $true)]
        [string]$ResourceGroupName,
        [Parameter (Mandatory= $true)]
        [string]$SnapshotName,
        [boolean]$backup=$True,
        [boolean]$restore=$False
    )
    #
    # Connection Phase
    #
    $connectionName = "AzureRunAsConnection"
    try
    {
        $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName
        Connect-AzAccount `
            -ServicePrincipal `
            -Subscription "dev.psg.hoopp.azure" `
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
    # Function Section
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
    Function VMInventory($VMName,$tSnapshotname){
        $info = "" | Select Name, ResourceGroupName, Location, VMSize, OSDisk, DataDisk, SnapName, TotalDataDisks
        $vm = Get-AzVM -Name $VMName
        $info.Name = $vm.Name
        $info.ResourceGroupName = $vm.ResourceGroupName
        $info.Location = $vm.Location
        $info.VMSize = $vm.HardwareProfile.VmSize
        $info.OSDisk = $vm.StorageProfile.OsDisk
        $info.DataDisk = $vm.StorageProfile.DataDisks
        $info.TotalDataDisks = ($vm.StorageProfile.DataDisks).count
        $info.Snapname = "." + $tSnapshotName
        #Making sure all disks attached to the VM are on the same version
        $vStatus = $False
        If (!($info.OSDisk.Name -like $info.Snapname)) {$vStatus=$true} 
        ForEach ($disk in $info.DataDisk) {
            If (!($disk.Name -like  $info.Snapname)) {$vStatus=$true; $vcount++}
        }
        if (!(Get-AzDisk | where-object { $_.Name -like $info.Snapname })) {
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
        $vStatus = $False
        $tNewName = ($vminfo.OsDisk.name).Split(".")[0] + ".snap" + $vminfo.SnapName
        $vm_OSDiskSnap = New-AzSnapshot -SnapshotName $tNewName -Snapshot $vm_OSSnapConfig -ResourceGroupName $vmInfo.ResourceGroupName
        If ($vm_OSDiskSnap.ProvisioningState -eq 'Succeeded'){
            $vStatus = $True  
        }
        #Creating the Data Disk(s) Snapshot(s)
        ForEach($disk in $vmInfo.DataDisk){
            #Validating if there is no snapshot and then creating a new one
            $vm_DataDisk = Get-AzDisk -ResourceGroupName $vmInfo.ResourceGroupName -DiskName $disk.name
            $vm_DataDiskSnapConfig = New-AzSnapshotConfig -SourceUri $vm_DataDisk.Id -CreateOption Copy -Location $vmInfo.location
            $tNewName = ($Disk.name).Split(".")[0] + ".snap" + $vminfo.SnapName
            $vm_DataDiskSnap = New-AzSnapshot -SnapshotName $tNewName -Snapshot $vm_DataDiskSnapConfig -ResourceGroupName $vmInfo.ResourceGroupName
            If ($vm_DataDiskSnap.ProvisioningState -eq 'Succeeded'){
                $vStatus = $True  
            }
        }
        #Saving as JSON
        $vmInfo | convertto-json | out-file  ($vmInfo.Name + $vmInfo.Snapname + ".json") 
        Return $vstatus
    }
    Function RestoreSnap($vminfo){
        #OS Disk
        $vStatus = $False
        $tDiskType = (Get-AzDisk -DiskName $vminfo.OsDisk.name).sku.name
        $tSnapShotNewName = ($vminfo.OsDisk.name).Split(".")[0] + ".snap" + $vminfo.SnapName
        $tSnapShot = Get-AZSnapshot -SnapshotName $tSnapShotNewName
        $tDiskConfig = New-AzDiskConfig -SkuName $tDiskType -Location $vmInfo.location -CreateOption Copy -SourceResourceId $tsnapshot.Id  
        $tNewName = ($vminfo.OsDisk.name).Split(".")[0] + $vmInfo.SnapName #Name change
        $temp = New-AzDisk -Disk $tDiskConfig -ResourceGroupName $vmInfo.ResourceGroupName -DiskName $tNewName
        If ($temp.ProvisioningState -eq "Succeeded") {
            $vStatus = $True
        }
        $tNewName = $null
        $tSnapShotNewName = $null

        #Data Disk(s)
        ForEach($disk in $vmInfo.DataDisk){
            $tDiskType=$null
            $tSnapshot =$null
            $tDiskConfig=$null
            $tNewName=$null
            $tDiskType = (Get-AzDisk -DiskName $disk.name).sku.name
            $tSnapShotNewName = ($Disk.name).Split(".")[0] + ".snap" + $vminfo.SnapName
            $tSnapShot = Get-AZSnapshot -SnapshotName $tSnapShotNewName
            $tDiskConfig = New-AzDiskConfig -SkuName $tDiskType -Location $vmInfo.location -CreateOption Copy -SourceResourceId $tsnapshot.Id
            $tNewName = ($Disk.name).Split(".")[0] + $vmInfo.SnapName  #name change
            If ($tnewName -ne $False) {
                $temp = New-AzDisk -Disk $tDiskConfig -ResourceGroupName $vmInfo.ResourceGroupName -DiskName $tNewName
                If ($temp.ProvisioningState -eq "Succeeded") {
                    $vStatus = $True
                }
            }      
            $tNewName = $null
            $tSnapShotNewName = $null
        }
        Return $vStatus
    }
    Function VMRestore($vmInfo){
        #OS Disk
        $vStatus = $False
        $tNewOSDiskName = ($vminfo.OsDisk.name).Split(".")[0] + $vmInfo.SnapName #name change
        $tVM = Get-AzVM -Name $vminfo.Name
        $New_OSDisk = Get-AzDisk -Name $tNewOSDiskName -ResourceGroupName $vmInfo.ResourceGroupName
        $temp = Set-AzVMOSDisk -VM $tVM -ManagedDiskId $New_OSDisk.Id -Name $New_OSDisk.Name
        $temp = Update-AzVM -VM $tVM -ResourceGroupName $vmInfo.ResourceGroupName
        If ($temp.StatusCode -eq "OK")  { $vStatus = $True }
        foreach($disk in ($vmInfo.DataDisk)){
            #removing the disk
            $temp = Remove-AZVMDataDisk -VM $tVM -Name $disk.Name
            $temp = Update-AzVM -VM $tVM -ResourceGroupName $vminfo.ResourceGroupName
            #adding the new disk
            $tNewDataDiskName = ($Disk.name).Split(".")[0] + $vmInfo.SnapName #name change
            $tDiskID = Get-AZDisk -diskname  $tNewDataDiskName
            $temp = Add-AzVMDataDisk -CreateOption Attach -Lun $disk.Lun -VM $tVM -ManagedDiskId $tDiskID.ID -Caching $disk.caching
            $temp = Update-AzVM -VM $tVM -ResourceGroupName $vmInfo.ResourceGroupName
            If ($temp.StatusCode -eq "OK") {
                $vStatus = $True
            }
        }
        Return $vstatus
    }

    #
    # Body Section
    #
    If ($backup -and $restore) {
        Msgbox "FATAL ERROR:" "The operation must be either BACKUP or RESTORE, but not both. Try Again." 2 60
    }
    $vTime = Get-Date
    Write-output ""
    Msgbox "Resource Group Name:" ($ResourceGroupName) 0 60
    Msgbox "Snapshot Name:" ($SnapshotName) 0 60

    $VMs = Get-AZVM -ResourceGroupName $ResourceGroupName
    If ($backup) {
        Msgbox "Operation Type:" "Backup" 0 60
        ForEach -parallel ($vm in $VMs){
            $CurrentVM = VMInventory $vm.name $SnapshotName
            $tmp = VMSnapshot $CurrentVM
            If ($tmp) { Msgbox "VMSnaphot Operation:" ($vm.Name + "had a snaphsot of all disks associated to the VM") 0 60}

        }
        InlineScript{
            Import-Module Az.Accounts
            Import-Module Az.Resources
            Import-Module Az.Automation
            Import-Module Az.Storage
            #Storage Connection
            $vResourceGroupname = "cc1-np-devops-psg-rg"
            $vAutomationAccountName = "svc-azdev-automation" 
            $vContainerName = "rgsnap"
            $vaStorageAccount = Get-AzAutomationVariable $vAutomationAccountName -Name "StorageAccount" -ResourceGroupName $vResourceGroupname 
            $StartTime = Get-Date
            $EndTime = $startTime.AddHours(1.0)
            $stgAccount = Get-AzStorageAccount -Name $vaStorageAccount.value -ResourceGroupName $vResourceGroupname 
            $SASToken = New-AzStorageAccountSASToken -Service Blob -ResourceType Container,Object -Permission "racwdlup" -startTime $StartTime -ExpiryTime $EndTime -Context $StgAccount.Context
            $stgcontext = New-AzStorageContext -storageAccountName $stgAccount.StorageAccountName -SasToken $SASToken
            $tempFiles = Get-ChildItem *.json
            foreach ($file in $tempFiles) {
                $tmp = Set-AzStorageBlobContent -File $file.Name -Container $vContainerName -Context $stgcontext -Force
            }
        }
    }
    If ($restore) {
        Msgbox "Operation Type:" "Restore" 0 60
        ForEach -parallel ($vm in $VMs){
            $CurrentVM = VMInventory $vm.name $SnapshotName
            $tmp = RestoreSnap $CurrentVM
            If ($tmp) { Msgbox "RestoreSnap Operation:" ($vm.Name + " had all Managed disks created.") 0 60}
            $tmp= VMRestore $CurrentVM   
            If ($tmp) { Msgbox "Disk Swap Operation:" ($vm.Name + "had all Managed disks switched. Restore complete!") 0 60}
        }
    }
    Msgbox "Total Execution Time: " ((get-Date) - $vTime) 1 60
}
