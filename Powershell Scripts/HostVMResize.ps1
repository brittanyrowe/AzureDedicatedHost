# PowerShell function to stop all VMs on a host, resize the VMs to a different type, move the VMs onto a new host
# and start the VMs on a new host.
# Move-ADHVMs {srcResourceGroup} {srcHostGroup} {srcHostName} {dstResourceGroup} {dstHostGroup} {dstHostName}
# Author: Brittany Rowe
Function Move-ADHVMs {
    [cmdletbinding()]
    Param (
        [string]$SourceResourceGroup,
        [string]$SourceHostGroup,
        [string]$SourceHostName,
        [string]$DestResourceGroup,
        [string]$DestHostGroup,       
        [string]$DestHostName,
        [string]$DestVMSize,
        [string]$Location
    )
    Process {
        Clear-Host
        Write-Host (get-date).ToString('T') ": Looking for source host"
        $srcHost = Get-AzHost -ResourceGroupName $SourceResourceGroup -HostGroupName $SourceHostGroup -Name $SourceHostName
        if (!$srcHost)
        {
            Write-Host " Source Host was not found .. Exit"
            return
        }

        $dstHost = Get-AzHost -ResourceGroupName $DestResourceGroup -HostGroupName $DestHostGroup -Name $DestHostName
        if ($dstHost.name -notcontains $DestHostName )
        {
            Write-Host " Destination Host was not found .. Creating new Host"
            $dstHost = New-AzHost -HostGroupName $DestHostGroup -Location $Location -Name $DestHostName -ResourceGroupName $DestResourceGroup -Sku EASv4-Type1 -AutoReplaceOnFailure 1 -PlatformFaultDomain 0
            return
        }

        Write-Host (get-date).ToString('T') ": Stoping and resizing all VMs"
        foreach ($vm in $srcHost.VirtualMachines) 
        {
            Write-Host "Iterate VM: " $vm.Id
            $strToken=$vm.Id.split("/")
            Write-Host "Stop VM: -ResourceGroupName " $strToken[4] " -name " $strToken[8]
            Stop-AzVM -Id $vm.Id -Force -AsJob

            Get-Job | Wait-Job -Timeout 240

            $vmname = Get-AzVM -ResourceGroupName $SourceResourceGroup -VMName $strToken[8]
            
            Write-Host "Disassociating VM from host: " vmname
            $vmname.Host = New-Object Microsoft.Azure.Management.Compute.Models.SubResource
            $vmname.Host.Id = ""
            Update-AzVM -ResourceGroupName $strToken[4] -VM $vmname

            Write-Host "Resizing VM: " $vmname
            $vmname.HardwareProfile.VmSize = $DestVMSize
            Update-AzVM -VM $vmname -ResourceGroupName $DestResourceGroup 
        }

        Write-Host (get-date).ToString('T') ": Moving all VMs"
        foreach ($vm in $srcHost.VirtualMachines) 
        {
            Write-Host "Iterate VM: " $vm.Id
            $strToken=$vm.Id.split("/")
            $currVM = Get-AzVM -ResourceGroupName $strToken[4] -name $strToken[8] 
            $currVM.Host = New-Object Microsoft.Azure.Management.Compute.Models.SubResource
            $currVM.Host.Id = $dstHost.Id
            Update-AzVM -ResourceGroupName $strToken[4] -VM $currVM -AsJob           
            
        }
        Write-Host (get-date).ToString('T') ": Waiting for all jobs to complete"

        Get-Job | Wait-Job -Timeout 180
        Get-Job | Remove-Job
        
        Write-Host (get-date).ToString('T') ": Starting all VMs"
       
        Write-Host "Iterate VM: " $vm.Id
        $strToken=$vm.Id.split("/")
        Start-AzVM -Id $currVM.Id -AsJob            


        Write-Host (get-date).ToString('T') ": Waiting for all jobs to complete"

        Get-Job | Wait-Job -Timeout 120
        Get-Job | Remove-Job

        Write-Host (get-date).ToString('T') ": All jobs have been completed"

    }
}

# syntax
# Move-ADHVMs {srcResourceGroup} {srcHostGroup} {srcHostName} {dstResourceGroup} {dstHostGroup} {dstHostName}
