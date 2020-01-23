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

#
# Body
#
$AzureRegion ="CanadaCentral"

MsgBox "Generating Official-VMTypes.csv: " "Add this info into the Official-VMTypes sheet" 0
Get-AzVMSize -Location $AzureRegion | Select Name,NumberOfCores,MemoryinMB,MaxDataDiskCount | Export-Csv -Path .\Official-VMTypes.csv

MsgBox "Generating Official-FlexibilityGroups.csv: " "Add this info into the Official-FlexibilityGroup sheet" 0
Invoke-WebRequest -uri "https://isfratio.blob.core.windows.net/isfratio/ISFRatio.csv" -OutFile "Official-FlexibilityGroups.csv"
$FlexGroup = import-csv -Path .\Official-FlexibilityGroups.csv

$RIReport = @()
$VMs = Get-AzVM 

ForEach ($vm in $VMs){
    $tmpFlexInfo = $Null    
    $info = "" | Select VMName,VMSize,FlexGroup,Ratio
        $Info.VMName = $VM.Name
        $info.VMSize = $VM.HardwareProfile.VMSize
        $tmpFlexInfo = $FlexGroup | Where-Object { $_.ArmSkuName -eq $VM.HardwareProfile.VMSize}
        $info.FlexGroup = $tmpFlexInfo.InstanceSizeFlexibilityGroup
        $Info.Ratio = $tmpFlexInfo.Ratio
    $RIReport += $info
}

MsgBox "Generating Complete.csv: " "All info in a single file." 0
$RIReport | Export-Csv -Path Complete.csv

MsgBox "Generating VMSizeInfo.csv: " "Total VM instances by VMSize" 0
$RIReport | Group-Object VMSize | Select Name,Count | export-csv -path VMSizeInfo.csv

MsgBox  "Generating FlexInfo.csv: " "Totals by Flex Group" 0
$RIReport | Group-Object FlexGroup | Select Name,Count | export-csv -path FlexInfo.csv

MsgBox "Generating FlexVMSizeInfo.csv: " "Total VM instances by Flex Group and VM Size combined" 0
$RIReport | Group-Object FlexGroup,VMSize | Select Count,Name | export-csv -path FlexVMSizeInfo.csv

$FlexGroup = @()
$tmpCredits = $RIReport | Group-Object FlexGroup 
For ($i=0; $i -le ($tmpCredits.Count);$i++){
    If ($tmpCredits[$i].Name -ne "") {
        [int]$tmpTotal=0
        $info = "" | Select Name,Ratio
        $info.Name = $tmpCredits[$i].Name
        $tmpCredits[$i].Group | ForEach { $tmpTotal += $_.Ratio}
        $info.Ratio = $tmpTotal
        $FlexGroup += $info
    }
}
MsgBox "Generating VMSizeRatioInfo.csv: " "VM Types instances and their ratios" 0
$FlexGroup | export-csv -path VMSizeRatioInfo.csv

$VMReport = @()
$VMs = Get-AZVM
ForEach ($vm in $VMs) {
                $info = "" | Select VMName,ResourceGroupName,Location,Size
                $info.VMName = $vm.Name
                $info.ResourceGroupName = $vm.ResourceGroupName
                $info.Location = $vm.Location
                $info.Size = $vm.HardwareProfile.VMSize
                $VMreport += $info
}
MsgBox "Generating VMReport.csv: " "Individual VMs and their specs." 0
$VMReport | export-csv -path VMReport.csv


