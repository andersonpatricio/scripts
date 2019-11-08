#
# Function by Anderson Patricio (AP6) - anderson@patricio.ca 
# Source: github.com/andersonpatricio
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
