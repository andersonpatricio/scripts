Param (
    [Parameter (Mandatory=$True)]
    [ValidateScript({Get-AzVM -Name $_})]
    [string] $VMName
)
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

# Loading dates in TimeSchedule hashtable
$CurrentMonth = Get-Date -Format "MM"
$CurrentYear = Get-Date -Format "yyyy"
$TimeSchedule = @{}
$TimeSchedule.Current = $CurrentYear.ToString() + $CurrentMonth.ToString()
$PreviousMonth = $CurrentMonth - 1
$PreviousYear = $CurrentYear - 1
If ($PreviousMonth -eq 0) {$PreviousMonth=12; $PreviousYear=$CurrentYear - 1}
$TimeSchedule.Previous = $PreviousYear.ToString() + $PreviousMonth.toString()


#Generating the Monthly Costs per Billing Cycle
$Monthlyreport = @()
Msgbox "VM Information: " $VMName 0
ForEach ($vEachBilling in $TimeSchedule.Keys){
    $VM = Get-AzConsumptionUsageDetail -InstanceName $VMName -BillingPeriodName $TimeSchedule[$vEachBilling]
    $info = "" | Select InstanceName,UsageQuantity,Currency,InstanceLocation,BillingPeriodName,PreTaxCost
        $Info.InstanceName = $VM.InstanceName
        $info.UsageQuantity = $VM.UsageQuantity
        $info.Currency = $VM.Currency
        $Info.InstanceLocation = $VM.InstanceLocation
        $info.BillingPeriodName = $VM.BillingPeriodName
        $info.PreTaxCost = $VM.PreTaxCost
    $Monthlyreport += $info
    $tmpTotal = 0
    ForEach ($SingleEntry in $MonthlyReport.PreTaxCost){
        $tmpTotal += $SingleEntry
    }
    Msgbox ($vEachBilling + " billing Cycle (" + $TimeSchedule[$vEachBilling] + ")" ) (" Monthly cost was " + (($report.Currency | Group-Object).Name) + " " + ([math]::round($tmpTotal,2)) )  1
}
