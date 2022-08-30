Import-Module Az.Accounts
Import-Module Az.Resources
Import-Module Az.Compute
Import-Module Az.Automation
Import-Module Az.Storage
Import-Module Az.Monitor

#
# Connnection Phase
#
$connectionName = "AzureRunAsConnection"
try
{
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName
    Connect-AzAccount `
        -ServicePrincipal `
        -Subscription 'subscription.azure' `
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
# Functions
#
Function global:Msgbox($caption,$message,$type,$MaxSize){
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
Function script:fCreatecmdlet($ResourceInfo,$Command,$Stage){
    $vRules = $Rules | where-object { $_.ResourceType -eq $ResourceInfo.ResourceType}
    Switch ($Command){
        "check" {
                    $tmpStage = '$vRules' + ".S" + $Stage + "check"
                    $tmpCmdlet = Invoke-Expression $tmpStage
                }
        "deploy" {
                    $tmpStage = '$vRules' + ".S" + $Stage + "deploy"
                    $tmpCmdlet = Invoke-Expression $tmpStage
                }
        "remove" {
                    $tmpStage = '$vRules' + ".S" + $Stage + "remove"
                    $tmpCmdlet = Invoke-Expression $tmpStage
                }
    }
    If ($tmpCmdlet -ne "none") {
        $tmpCmdlet = $tmpCmdlet -replace "<VMName>",$ResourceInfo.Name
        $tmpCmdlet = $tmpCmdlet -replace "<ResourceGroupName>",$ResourceInfo.ResourceGroupName
        $tmpCmdlet = $tmpCmdlet -replace "<ResourceId>",$ResourceInfo.ResourceId
        $tmpCmdlet = $tmpCmdlet -replace "<JSONPath>",$tVMPath
        $tmpCmdlet = $tmpCmdlet -replace "<STGDiagName>",$Rules[0].STGDiagName
        $tmpCmdlet = $tmpCmdlet -replace "<BootDiagName>",$Rules[0].BootDiagName
        $tmpCmdlet = $tmpCmdlet -replace "<ResourceId>",$ResourceInfo.ResourceId
        $tmpCmdlet = $tmpCmdlet -replace "<WorkspaceID>",$Rules[0].WorkspaceID
        $tmpCmdlet = $tmpCmdlet -replace "<RGBootDiag>",$Rules[0].RGBootDiag
        
    }
    Return $tmpCmdlet
}
Function fLoadVMDiagSettings{
    #Storage Connection
    $vResourceGroupname = "cc1-np-devops-psg-rg"
    $vAutomationAccountName = "svc-azdev-automation" 
    $vContainerName = "it4p-operations"
    $vaStorageAccount = "devopspsgsa" #to be replaced
    #$vaStorageAccount = Get-AzAutomationVariable $vAutomationAccountName -Name "StorageAccount" -ResourceGroupName $vResourceGroupname 
    $StartTime = Get-Date
    $EndTime = $startTime.AddHours(1.0)
    #$stgAccount = Get-AzStorageAccount -Name $vaStorageAccount.value -ResourceGroupName $vResourceGroupname 
    $stgAccount = Get-AzStorageAccount -Name $vaStorageAccount -ResourceGroupName $vResourceGroupname  #To be replaced
    $SASToken = New-AzStorageAccountSASToken -Service Blob -ResourceType Container,Object -Permission "racwdlup" -startTime $StartTime -ExpiryTime $EndTime -Context $StgAccount.Context
    $stgcontext = New-AzStorageContext -storageAccountName $stgAccount.StorageAccountName -SasToken $SASToken
    $tmp = Get-AzStorageBlobContent -Container $vContainerName -Blob ("template.standard.v" + $global:ConfigVersion + ".json") -Destination (Get-Location).path -Context $stgcontext
    $tmpRuleFileName = ("operationflag.rules.v" + $global:ConfigVersion + ".json")
    $tmp = Get-AzStorageBlobContent -Container $vContainerName -Blob $tmpRuleFileName -Destination (Get-Location).path -Context $stgcontext
    $Global:Rules = Get-Content -Raw -Path ((Get-Location).Path + "\" + $tmpRuleFileName) | ConvertFrom-Json
    Return $True
}

Function Phase1($ResourceInfo){
    # $Action 1 is deployment and $Action 6 means removal. The current status is the difference between TAG settings and Current VM Settings
    $vRules = $Rules | where-object { $_.ResourceType -eq $ResourceInfo.ResourceType}
    $swapResourceInfo = $ResourceInfo
    $vStatus = $False
    For ($i=0; $i -lt ($rules[0].OperationFlagSize).Length;$i++){
       Switch ($ResourceInfo.CurrentStatus[$i]){
        "1" {
                $tVMPath = ((Get-Location).Path + "\" + $ResourceInfo.Name + ".json")
                (Get-Content ((Get-Location).Path + "\template.standard.v" + $Global:ConfigVersion + ".json")) -replace 'PLACEHOLDER-resourceId', $ResourceInfo.ResourceId | Out-File $tVMPath -Force
                #Creating the cmdlet
                $tmpCmdlet = fCreatecmdlet $swapResourceInfo "deploy" $i
            }
        "6" {
                $tmpCmdlet = fCreatecmdlet $swapResourceInfo "remove" $i           
            }
        }

        If (($tmpcmdlet) -and ($tmpcmdlet -ne "none")){ 
            $tmpOp = Invoke-Expression ($tmpCmdlet)
            $vStatus = $true
        }
    }
    Return $vStatus
}

Function global:fQuickCheck($ResourceInfo){
    #Loading Rules
    $vRules = $Rules | where-object { $_.ResourceType -eq $ResourceInfo.ResourceType}
    [string]$tOperationFlag = ([string]$tOperationFlag).PadRight(($ResourceInfo.OperationFlag).Length,"0")
    $tStatus = $tOperationFlag

    $vStatus = $False
    If ($Global:ConfigVersion -ne $ResourceInfo.DiagVersion) {
        $vStatus = $False
    }Else{
        #$currentPosition=0
        For ($i=0; $i -lt ($rules[0].OperationFlagSize).Length;$i++){
            $swapResourceInfo = $ResourceInfo
            $tmpCmdlet = fCreatecmdlet $swapResourceInfo "check" $i

            $vStatus = $False
            If (($tmpcmdlet) -and ($tmpCmdlet -ne "none")) {
                $tmpOp = Invoke-Expression ($tmpCmdlet)
                If ($tmpOp) { $vStatus = $True }
            } Else {
                $vStatus = $False
            }
            If ($vStatus) { 
                $tOperationFlag = $tOperationFlag.remove($i,1).insert($i,1)
            } else {
                $tOperationFlag = $tOperationFlag.remove($i,1).insert($i,0)
            }
            If ($tmpCmdlet -eq "none"){
                #write-output $tmpcmdlet
                #write-output $tOperationFlag
                $tOperationFlag = $tOperationFlag.remove($i,1).insert($i,"x")
                #write-output $tOperationFlag
            }
        }
    }
    #Comparing..
    For ($i=0; $i -lt $tOperationFlag.Length;$i++){
        If (($ResourceInfo.OperationFlag[$i] -eq "1") -and ($tOperationFlag[$i] -eq "0")){$tStatus = $tStatus.Remove($i,1).Insert($i,1)}
        If (($ResourceInfo.OperationFlag[$i] -eq "1") -and ($tOperationFlag[$i] -eq "x")){$tStatus = $tStatus.Remove($i,1).Insert($i,"x")}
        #If (($ResourceInfo.OperationFlag[$i] -eq "1") -and ($tOperationFlag[$i] -eq "x")){$tStatus = $tStatus.Remove($i,1).Insert($i,0)}
        #If (($vmInfo.OperationFlag[$i] -eq "1") -and ($tOperationFlag[$i] -eq "1")){$tStatus = $tStatus.Remove($i,1).Insert($i,0)}
        #If (($vmInfo.OperationFlag[$i] -eq "0") -and ($tOperationFlag[$i] -eq "0")){$tStatus = $tStatus.Remove($i,1).Insert($i,0)}
        If (($ResourceInfo.OperationFlag[$i] -eq "0") -and ($tOperationFlag[$i] -eq "1")){$tStatus = $tStatus.Remove($i,1).Insert($i,6)}
    }
    Return $tStatus
}
Function fTagAssessment($Resource){
    #Loading Rules
    $vRules = $Rules | where-object { $_.ResourceType -eq $Resource.Type}
    $ResourceInfo=@{}
        $ResourceInfo.Name = $Resource.Name
        $ResourceInfo.ResourceGroupName = $Resource.ResourceGroupName
        $ResourceInfo.ResourceId = $Resource.Id
        $ResourceInfo.ResourceType = $Resource.Type
        If ($Resource.Tags.DiagVersion) {
            $ResourceInfo.DiagVersion = $Resource.Tags.DiagVersion
        } Else { 
            If ($Resource.Tags.Count -eq 0) {
                $tmp = Set-AzResource -Tag @{DiagVersion="$Global:ConfigVersion";DiadWorkload="Standard"} -ResourceId $Resource.Id -Force
            }else{
                $Resource.Tags.Add("DiagVersion","$Global:ConfigVersion")
                $Resource.Tags.Add("DiagWorkload","Standard")
                Set-AzResource -Tag $Resource.Tags -ResourceId $Resource.Id -Force
            }
        }
        If (!($Resource.Tags.OperationFlag)){
            $RG = Get-AzResourceGroup -name $ResourceInfo.ResourceGroupName
            If (!($RG.Tags.OperationFlag)){
                $tmpRGTags = $RG.Tags
                $tmpOperationFlag = $Rules[0].OperationFlagSize
                $tmpRGTags += @{"OperationFlag"="$TmpOperationFlag"}
                $tmp = Set-AzResourceGroup -Name $RG.ResourceGroupName -Tag $tmpRGTags
                $ResourceInfo.OperationFlag = $TmpOperationFlag
            }Else{
                $ResourceInfo.OperationFlag = $RG.Tags.OperationFlag
            }
        }Else{
            $ResourceInfo.OperationFlag = $Resource.Tags.OperationFlag
        }
    Return $ResourceInfo
}
#
# Body
#
[Int]$Global:ConfigVersion=1
$tmp = fLoadVMDiagSettings  #load all json templates into the Azure Automation node
$Resources = Invoke-Expression ("Get-AzResource -ResourceGroupName RG-MSLab " + $Rules[0].QueryResources)

ForEach ($SingleResource in $Resources){
    $ResourceInfo = fTagAssessment $SingleResource
    $tmpResourceCheck = fQuickCheck $ResourceInfo
    $ResourceInfo.Add("CurrentStatus",$tmpResourceCheck)
    #$ResourceInfo
    $tmp = Phase1 $ResourceInfo
    If ($tmp){
        Msgbox "Diagnostic Settings Updated: " $ResourceInfo.Name 0 70
    } Else {
        Msgbox "Diagnostic Settings (no changes): " $ResourceInfo.Name 1 70
    }
}
