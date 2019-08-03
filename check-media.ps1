#
# Check-Media.ps1 by Anderson Patricio (anderson@patricio.ca)
# https://github.com/andersonpatricio
#
param (
    [string]$file = $(throw "-file is required."), 
    [string]$checksum = $(throw "-checksum is required."),
    [string]$algorithm ="SHA1"
)

if (Test-Path $file) { 
    $hash  = (Get-FileHash $file -Algorithm $algorithm).hash
    if ($hash -eq $checksum) {
        Write-host
        Write-Host -ForegroundColor Green "SUCCESS! We are golden checksum and file match! We are ready to take off!"
        Write-Host
        } Else {
            write-host
            write-host "ERROR: The checksum and file hash DO NOT MATCH!! Double check the information but don't use the file until additional validation." -ForegroundColor Red
            Write-host
        }
        Write-Host "Additional Information:"
        Write-Host
        Write-Host "File name...............: " $file
        Write-Host "Checksum provided.......: " $checksum
        Write-Host "Algorithm...............: " $Algorithm
        Write-Host "File checksum...........: " $hash
        Write-Host
    } Else { 
    write-host
    write-host "ERROR: File does not exist. Please provide an existent file to be checked." -ForegroundColor DarkRed
    Write-host
    Exit
    }




