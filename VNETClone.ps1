Param(
    [ValidateScript({Get-AzVirtualNetwork -Name ($_)})]
    [string]$SourceVirtualNetworkName,
    [String]$CloneName="Clone",
    [ValidateScript({Get-AzResourceGroup -Name ($_)})]
    [String]$TargetResourceGroupName
)

#
# Functions Section
#
Function Msgbox($caption,$message,$type,$MaxSize){
    if ($MaxSize -eq $null) { $MaxSize = 126}
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

Function CloneVNET($VNETName,$TargetResourceGroupName,$CloneName){
    $return = @{}
    $vStatus = $False
    $vVNET = Get-AzVirtualNetwork -Name $VNETName
    $newVNETName = $vVNET.name + "_" + $CloneName
    $newVNET = New-AzVirtualNetwork  -ResourceGroupName $TargetResourceGroupName -Location $vVNET.Location -Name $newVNETName -AddressPrefix $vVNET.AddressSpace.AddressPrefixes -Force
    If ($newVNET.ProvisioningState -eq "Succeeded"){
        $vStatus = $True
        $return.VNETName = $newVNETName
    }
    $Subnets = $vVNET.Subnets
    ForEach ($subnet in $subnets){
        $tOperation = Add-AzVirtualNetworkSubnetConfig -Name $subnet.name -AddressPrefix $subnet.AddressPrefix -VirtualNetwork $newVNET
        If ($tOperation.ProvisioningState -eq "Succeeded"){
            $vStatus = $True
        } Else {
            $vStatus = $False
        }
    }
    $tOperation = $newVNET | Set-AZVirtualNetwork
    Return $return
}

#
# Body Section
#

Msgbox "Virtual Network (original):" $SourceVirtualNetworkName 1 50
Msgbox "Resource Group (clone):" $TargetResourceGroupName 1 50
Msgbox "Clone Name:" $CloneName 1 50
$temp = CloneVNET $SourceVirtualNetworkName $TargetResourceGroupName $CloneName
Msgbox "Virtual Network (Clone)" $temp.VNETName 0 50


