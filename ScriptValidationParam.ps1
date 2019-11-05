Param (
	[Parameter(Mandatory=$true,HelpMessage="The VM Name in the current Azure subscription")]
	[Alias("VirtualMachine","Machine","Alien","ChupaCabra")]
	[ValidateScript({($_).Length -gt 4})]
	[string]
	$VMName,
	[switch]$protect,
	[switch]$restore
)

If ($PSBoundParameters.Count -gt 2) {
	Write-Host "Too many parameters"
}
Write-Host
If ($PSBoundParameters.Keys.Contains("restore")) {
	Write-Host "Restore code..."
}
If ($PSBoundParameters.Keys.Contains("protect")) {
	Write-Host "Protect code..."
}
Write-Host

