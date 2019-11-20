#
# 
#
Function VMPowerCheck($VMName,$Status){
    If ($status -eq "on"){
        $vPowerstate = "VM Running"
    }
    If ($status -eq "off"){
        $vPowerstate = "VM deallocated"
    }
    $vStatus = $False
    while ($vStatus -eq $False) {
        $temp = Get-AzVM -Name $VMName -Status | Where-Object  { $_.PowerState -eq $vPowerstate}
        If ($temp){
            Return $True
        } Else {
            Write-Host "The VM " $VMName " is not compliant. Waiting the VM to be turned " $Status "."
        }
    }
}
