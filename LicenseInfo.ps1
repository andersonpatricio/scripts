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

Function Menu(){
    
    $tmpOption = $null
    $tmpCurrentSubscription = (Get-AzContext).Name
    do {
        Clear-Host
        Write-Host
        Write-Host -ForegroundColor Yellow ".:. Azure License Info - " $tmpCurrentSubscription
        Write-Host
        Write-Host "1) Number of VMs"
        Write-Host "2) Report of VMs, VM Size, and FlexGroup"
        Write-Host "3) Total of VMSizes based on current numbers"
        Write-Host "4) Total of VMSizes/Flexgroup based on current numbers"
        Write-host "5) Total of VMs per FlexGroup based on current numbers"
        Write-Host "9) Exit"
        Write-Host
        $tmpOption = Read-Host -Prompt "Option -> "

        Switch ($tmpOption){
            1{ 
                Write-Host
                Write-Host -ForegroundColor DarkGreen "Total number of VMs in the current subscription is " (Get-AzVM).Count
            }
            2{
                Write-Host
                Write-Host -ForegroundColor DarkGreen "Total number of VMs, VMSize, FlexGroup and Ratio "
                write-output $RIReport
            }
            3{
                write-output $RIReport | Group-Object VMSize | Select Name,Count
            }
            4{
                write-output  $RIReport | Group-Object FlexGroup,VMSize | Select Count,Name
            }
            5{
                write-output $RIReport | Group-Object FlexGroup
            }

        }

        If ($tmpOption -ne '9'){
            Write-Host
            Read-Host -Prompt "Press <enter> to continue."
            Write-Host
        }

    } while ($tmpOption -ne 9)

}

#
# Body
#
$AzureRegion ="CanadaCentral"
MsgBox "Generating Official-VMTypes.csv: " "" 0
Get-AzVMSize -Location $AzureRegion | Select Name,NumberOfCores,MemoryinMB,MaxDataDiskCount | Export-Csv -Path .\Official-VMTypes.csv
MsgBox "Generating Official-FlexibilityGroups.csv: " "" 0
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

Menu
