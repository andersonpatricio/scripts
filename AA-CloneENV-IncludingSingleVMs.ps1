workflow Clone-MGMT
{
    Param
    (
        [Parameter (Mandatory= $true)]
        [ValidateScript({Get-AzResourceGroup -Name $_})]
        [string]$ResourceGroupName,
        [boolean]$SingleVMInstead=$False,
        [string]$VMName,
        [Parameter (Mandatory= $true)]
        [string]$CloneName
    )
    $PSRunInProcessPreference = $true
    #
    # Connection Phase
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
    $InlineCloneName=$CloneName
    $InlineSingleVMInstead=$SingleVMInstead
    $InlineSingleVMName=$VMName
    $InlineResourceGroupName = $ResourceGroupName

    $tControl = InlineScript {
        Import-Module Az.Accounts
        Import-Module Az.Resources
        Import-Module Az.Compute
        Import-Module Az.Automation
        Import-Module Az.Storage
        Import-Module Az.Network
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
        Function CloneVNET($HashTable){
            $return=@{}
            $vVNET = Get-AzVirtualNetwork -Name $HashTable.VNETName
            $newVNETName = $vVNET.name + "_" + $HashTable.CloneName + $HashTable.BubbleName
            $newVNET = New-AzVirtualNetwork  -ResourceGroupName $HashTable.TargetResourceGroupName -Location $vVNET.Location -Name $newVNETName -AddressPrefix $vVNET.AddressSpace.AddressPrefixes -Force
            $Subnets = $vVNET.Subnets
            ForEach ($subnet in $subnets){
                $temp = Add-AzVirtualNetworkSubnetConfig -Name $subnet.name -AddressPrefix $subnet.AddressPrefix -VirtualNetwork $newVNET
            }
            $temp = $newVNET | Set-AZVirtualNetwork
            #validation required
            $return.TargetVNETName = $newVNETName
            Return $Return
        }

        Function ValidateEnv($HashTable){
            #Function Variables
            $tVNET = $null
            $return=@{}
            $targetResourceGroupName = $HashTable.ResourceGroupname + "_" + $HashTable.CloneName + $HashTable.BubbleName
            #Validate Resource Group
            If (Get-AzResourceGroup -Name $targetResourceGroupName -ErrorAction Ignore){
                $Return.Status = $False
                $Return.Message = "Resource Group $targetResourceGroupName already exist. Please delete it." 
                Return $Return
            }
            #Validate VMs in the Resource Group
            If ($HashTable.SingleVMInstead){
                $vVMRunning = get-azvm -Name $HashTable.SingleVMName -ResourceGroupName $HashTable.ResourceGroupName -Status | Where-Object { $_.PowerState -eq 'VM running'}
            }Else{
                $vVMRunning = get-azvm -ResourceGroupName $HashTable.ResourceGroupName -Status | Where-Object { $_.PowerState -eq 'VM running'}
            }
            
            If ($vVMRunning.Count -ne 0) {
                $Return.Status = $False
                $Return.Message = "The are VMs runnin on " + $HashTable.ResourceGroupName + ". Please deallocate them." 
                Return $Return
            }
            #Validate if all VMs share the same VNET
            If ($HashTable.SingleVMInstead -eq $False) {
                $NICs = Get-AzNetworkInterface -ResourceGroupName $HashTable.ResourceGroupName
            } Else {
                $tmpVM = Get-AzVM -Name $HashTable.SingleVMName
                $NICs = Get-AzNetworkInterface -Resourceid $tmpVM.NetworkProfile.NetworkInterfaces.Id
            }
            ForEach ($nic in $NICs){
                $tempVNETName = ($nic.IpConfigurations.Subnet.Id).split("/")[8]
                If (!($tVNET)) { $tVNET = $tempVNETName}
                If ($tVNET -ne $tempVNETName){
                    $Return.Message = "Not all VMs share the same VNET"
                    $Return.Status = $False
                    Return $Return
                }
            }
            
            $return.TargetResourceGroupName = $targetResourceGroupName
            $Return.VNETName = $tVNET
            $Return.Status = $True
            Return $Return
        }      
        #
        # Body Inline Section
        #
        $vTime = Get-Date
        Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"
        $tControl=@{}
            $tControl.CloneName = $Using:InlineCloneName
            $tControl.BubbleName = "_Bubble"
            $tControl.SingleVMInstead = $Using:InlineSingleVMInstead
            $tControl.SingleVMName = $Using:InlineSingleVMName
            $tControl.ResourceGroupName = $Using:InlineResourceGroupName
            $tControl.Location = (Get-AzResourceGroup -Name $tControl.ResourceGroupName).Location

        $temp = ValidateEnv $tControl
        If (!($temp.Status)) {
            MsgBox "Environment Validation:" $Temp.Message 2 70
            $tControl.Status = $False
        } Else {
            $tControl.VNETName = $temp.VNETName
            $tControl.TargetResourceGroupName = $temp.TargetResourceGroupName
            #Creating the Resource Group
            $temp = New-AzResourceGroup -Name $tControl.TargetResourceGroupName -Location $tControl.Location -ErrorAction Ignore 
            If ($temp.ProvisioningState -eq "Succeeded") {
                Msgbox "Resource Group:" ("New Clone Resource Group " + $tControl.TargetResourceGroupName + " created.") 0 70
            } Else {
                Msgbox "Resource Group:" ("New Clone Resource Group " + $tControl.TargetResourceGroupName + " failed.") 2 70
                Break
            }
            #Cloning the Virtual Network
            $temp = CloneVNET $tControl
            $tControl.TargetVNETName = $temp.TargetVNETName
            Msgbox "Virtual Network:" ("New Cloned Virtual Network " + $tControl.TargetVNETName + " created.") 0 70
            $tControl.Status = $True
        }
        $tControl
    }
    #
    # Function Workflow Section
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
    Function VMInventory($VMName){        
        $tmpContext = Import-AzContext -Path ((Get-Location).path + "\file.json")
        $info = "" | Select Name, ResourceGroupName, Location, VMSize, OSDisk, NetworkProfile, Subnet, NIC, DataDisk, SnapName, TotalDataDisks
        $vm = Get-AzVM -Name $VMName
        $info.Name = $vm.Name
        $info.ResourceGroupName = $vm.ResourceGroupName
        $info.Location = $vm.Location
        $info.VMSize = $vm.HardwareProfile.VmSize
        $info.OSDisk = $vm.StorageProfile.OsDisk
        $info.NetworkProfile = $vm.NetworkProfile
        $tNIC = $vm.NetworkProfile.NetworkInterfaces.Id
        $tSubnet = ((Get-AzNetworkInterface -Resourceid $tNIC).IpConfigurations.Subnet[0].Id).Split("/")[((Get-AzNetworkInterface -Resourceid $tNIC).IpConfigurations.Subnet[0].Id).Split("/").Length - 1]
        $info.NIC = $tNIC.split("/")[$tNIC.split("/").Length - 1]
        $info.Subnet = $tSubnet
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
    Function VMSnapshot($vmInfo,$HashTable){
        $tmpContext = Import-AzContext -Path ((Get-Location).path + "\file.json")
        $return = @{}
        $vStatus = $False
        #Creating a new snapshot
        $vm_OSDisk = Get-AzDisk -ResourceGroupName $vmInfo.ResourceGroupName -DiskName $vmInfo.OSDisk.Name
        $vm_OSSnapConfig = New-AzSnapshotConfig -SourceUri $vm_OSDisk.Id -CreateOption Copy -Location $vmInfo.location
        $tNewName = ($vminfo.OsDisk.name).Split(".")[0] + ".snap." + $HashTable.CloneName
        $vm_OSDiskSnap = New-AzSnapshot -SnapshotName $tNewName -Snapshot $vm_OSSnapConfig -ResourceGroupName $HashTable.TargetResourceGroupName
        If ($vm_OSDiskSnap.ProvisioningState -eq 'Succeeded'){
            $vStatus = $True
        } 
        #Creating the Data Disk(s) Snapshot(s)
        ForEach($disk in $vmInfo.DataDisk){
            $tmpContext = Import-AzContext -Path ((Get-Location).path + "\file.json")
            #Validating if there is no snapshot and then creating a new one
            $vm_DataDisk = Get-AzDisk -ResourceGroupName $vmInfo.ResourceGroupName -DiskName $disk.name
            $vm_DataDiskSnapConfig = New-AzSnapshotConfig -SourceUri $vm_DataDisk.Id -CreateOption Copy -Location $vmInfo.location
            $tNewName = ($Disk.name).Split(".")[0]  + ".snap." + $HashTable.CloneName
            $vm_DataDiskSnap = New-AzSnapshot -SnapshotName $tNewName -Snapshot $vm_DataDiskSnapConfig -ResourceGroupName $HashTable.TargetResourceGroupName
            If ($vm_DataDiskSnap.ProvisioningState -eq 'Succeeded'){
                $vStatus = $True
            }
        }
        #Saving as JSON
        $vmInfo | convertto-json | out-file  ($vmInfo.Name + "." + $HashTable.CloneName + ".json") 
        Return $vStatus
    }
    Function VMRestoreSnap($vminfo,$HashTable){
        $tmpContext = Import-AzContext -Path ((Get-Location).path + "\file.json")
        #OS Disk
        $vStatus = $False
        $tDiskType = (Get-AzDisk -DiskName $vminfo.OsDisk.name).sku.name
        $tSnapShotNewName = ($vminfo.OsDisk.name).Split(".")[0] + ".snap." + $HashTable.CloneName
        $tSnapShot = Get-AZSnapshot -SnapshotName $tSnapShotNewName
        $tDiskConfig = New-AzDiskConfig -SkuName $tDiskType -Location $vmInfo.location -CreateOption Copy -SourceResourceId $tsnapshot.Id  
        $tNewName = ($vminfo.OsDisk.name).Split(".")[0] + "_" + $HashTable.CloneName #Clone Name Fix
        $temp = New-AzDisk -Disk $tDiskConfig -ResourceGroupName $HashTable.TargetResourceGroupName -DiskName $tNewName
        If ($temp.ProvisioningState -eq "Succeeded") {
            $vStatus = $True
        }
        $tNewName = $null
        $tSnapShotNewName = $null
        #Data Disk(s)
        ForEach($disk in $vmInfo.DataDisk){
            $tmpContext = Import-AzContext -Path ((Get-Location).path + "\file.json")
            $tDiskType=$null
            $tSnapshot =$null
            $tDiskConfig=$null
            $tNewName=$null
            $tDiskType = (Get-AzDisk -DiskName $disk.name).sku.name
            $tSnapShotNewName = ($Disk.name).Split(".")[0] + ".snap." + $HashTable.CloneName
            $tSnapShot = Get-AZSnapshot -SnapshotName $tSnapShotNewName
            $tDiskConfig = New-AzDiskConfig -SkuName $tDiskType -Location $vmInfo.location -CreateOption Copy -SourceResourceId $tsnapshot.Id
            $tNewName = ($Disk.name).Split(".")[0] + "_" + $HashTable.CloneName #Clone Name Fix
            If ($tnewName -ne $False) {
                $temp = New-AzDisk -Disk $tDiskConfig -ResourceGroupName $HashTable.TargetResourceGroupName -DiskName $tNewName
                If ($temp.ProvisioningState -eq "Succeeded") {
                    $vStatus = $True
                }
            }      
            $tNewName = $null
            $tSnapShotNewName = $null
        }
        Return $vStatus
    }
    Function CloneVM($VMInfo,$HashTable){
        $tmpContext = Import-AzContext -Path ((Get-Location).path + "\file.json")
        #Retrieving main information
        $targetVNET = Get-AzVirtualNetwork -Name $HashTable.TargetVNETName
        $targetSubnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $targetVNET -Name $VMInfo.Subnet
        $vNIC = New-AzNetworkInterface -Name $VMInfo.NIC -ResourceGroupName $HashTable.TargetResourceGroupName -Location $VMInfo.Location -SubnetId $targetSubnet.Id
        $vOSDisk = Get-AZDisk -DiskName ($VMInfo.OSDisk.Name.split(".")[0] + "_" + $HashTable.CloneName) -ResourceGroupName $HashTable.TargetResourceGroupName #Clone Name Fix
        $VMConfig = New-AZVMConfig -VMName ($VMInfo.Name + "_" + $HashTable.CloneName + $HashTable.BubbleName) -VMSize $VMInfo.VmSize
        $VM = Add-AzVMNetworkInterface -VM $VMConfig -ID $vNIC.Id
        $VM = Set-AZVMOSDisk -VM $vm -ManagedDiskId $vOSDisk.Id -Name $vOSDisk.Name -CreateOption Attach -Windows
        foreach($disk in ($vmInfo.DataDisk)){
            $tNewDataDiskName = ($Disk.name).Split(".")[0] + "_" + $HashTable.CloneName #Clone Name Fix
            $tDiskID = Get-AZDisk -diskname  $tNewDataDiskName
            $VM = Add-AzVMDataDisk -CreateOption Attach -Lun $disk.Lun -VM $VM -ManagedDiskId $tDiskID.ID -Caching $disk.caching
        }    
        Set-AzVMBootDiagnostic -VM $VM -Disable
        #creating the VM
        $temp = New-AzVM -ResourceGroupName $HashTable.TargetResourceGroupName -Location $VMInfo.Location -VM $vm -LicenseType "Windows_Server"
        If ($temp.StatusCode -eq "OK"){
            Return $True
        } Else {
            Return $False
        }
    }

    #
    # Body Workflow Section
    #
    Save-AzContext -path ((Get-Location).Path + "\file.json") -Force
    $tControl
     If ($tControl.Status){
        [Double]$Timeout = 30
        $vTime = Get-Date
        
       If ($SingleVMInstead){
           $VMs= Get-AzVM -Name $VMName

       }Else{
           $VMs = Get-AZVM -ResourceGroupName $tControl.ResourceGroupName
       }
        
        #Write-Output $VMs.Count
        #$VMS | Select Name

        #ForEach ($vm in $VMs) {
        ForEach -Parallel -ThrottleLimit 6 ($vm in $VMs) {
            #Write-Output ("ForEach iteraction START->  " + $vm.name)
            $CurrentVM = VMInventory $vm.Name
            $opVMSnapshotStatus = VMSnapshot $CurrentVM $tControl
            #Write-Output ("ForEach iteraction->  " + $vm.name + " -> " + $opVMSnapshotStatus)
            If (!($opVMSnapshotStatus)){
                Msgbox "Snapshot Process: " ("Error creating snapshot for " + $CurrentVM.Name) 2 70
            } Else {
                Msgbox "Snapshot Process: " ("Process complete for " + $CurrentVM.Name) 0 70
                Start-Sleep -seconds $Timeout
                $opVMRestoreSnapStatus = VMRestoreSnap $CurrentVM $tControl
                If (!($opVMRestoreSnapStatus)){
                    Msgbox "Managed Disk Process: " ("Error creating Managed Disks for " + $CurrentVM.Name) 2 70
                } Else {
                    Msgbox "Managed Disk Process: " ("Disks created sucessfully for " + $CurrentVM.Name) 0 70
                    Start-Sleep -seconds $Timeout
                    $opCloneVMStatus = CloneVM $CurrentVM $tControl
                    If ($opCloneVMStatus){
                        Msgbox "VM Clone: " ("Cloned VM process was complete " + $CurrentVM.Name + "_" + $tControl.CloneName + $tControl.BubbleName) 0 70
                    }
                }
            }
        }
        #Cleaning up the Snapshots
        $OpSnapshotStatus = Get-AzSnapshot -ResourceGroupName $tControl.TargetResourceGroupName | Remove-AzSnapshot -Force
        If ((($OpSnapshotStatus.status | Group-Object).Name -eq 'Succeeded') -and (($OpSnapshotStatus.Status | Group-Object).Count -eq $OpSnapshotStatus.Count) ){
            Msgbox "Snapshot Removal Process:" "All snapshots were removed." 0 70
        } Else{
            Msgbox "Snapshot Removal Process:" "Some snapshots failed to be removed. Remove them manually." 1 70
        }
        #Time to complete the entire process
        Msgbox "Total Execution Time: " ((get-Date) - $vTime) 1 60
    } Else{
        Msgbox "Validation Fail:" "The source environment has not passed all the requirements." 2 60
    }
}
