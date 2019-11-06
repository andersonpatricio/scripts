Function EncryptVM($KeyVault,$KeyName,$VM){
    $kv = Get-azKeyVault -VaultName $KeyVault
    $key = get-Azkeyvaultkey -Name $KeyName -VaultName $KeyVault
    Set-AzVmDiskEncryptionExtension -ResourceGroupName $kv.ResourceGroupName -DiskEncryptionKeyVaultId  $kv.ResourceID -DiskEncryptionKeyVaultUrl $kv.VaultURI -VMName $VM -KeyEncryptionKeyVaultId $kv.ResourceID -KeyEncryptionKeyUrl $key.id -SkipVmBackup -VolumeType "All"
}
