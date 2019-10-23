#
# Function by Anderson Patricio (AP6) - anderson@patricio.ca 
# Source: github.com/andersonpatricio
#
Function Msgbox($caption,$message,$type,$MaxSize){
    if ($MaxSize -eq $null) { $MaxSize = 66}
    $sCaption = $caption.Length
    $sMessage = $Message.Length
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
