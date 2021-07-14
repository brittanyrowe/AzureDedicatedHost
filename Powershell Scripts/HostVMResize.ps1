# PowerShell function to stop all VMs on a host, resize the VMs to a different type, move the VMs onto a new host
# and start the VMs on a new host.
# Move-ADHVMs {srcResourceGroup} {srcHostGroup} {srcHostName} {dstResourceGroup} {dstHostGroup} {dstHostName}
# Author: Brittany
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
        
        Write-Host (get-date).ToString('T') " Creating destination host and host group"
        $DestHostGroup = New-AzHostGroup -Location $Location -Name NewHG -PlatformFaultDomain 1 -ResourceGroupName $DestResourceGroup -Zone 1 -SupportAutomaticPlacement true

        $dstHost = Get-AzHost -ResourceGroupName $DestResourceGroup -HostGroupName $DestHostGroup -Name $DestHostName
        if (!$dstHost)
        {
            Write-Host " Destination Host was not found .. Creating new Host"
            $dstHost = New-AzHost -HostGroupName $DestHostGroup -Location $Location -Name myHost -ResourceGroupName $DestResourceGroup -Sku EASv4-Type1 -AutoReplaceOnFailure 1 -PlatformFaultDomain 1
            return
        }

        Write-Host (get-date).ToString('T') ": Stoping and resizing all VMs"
        foreach ($vm in $srcHost.VirtualMachines) 
        {
            Write-Host "Iterate VM: " $vm.Id
            $strToken=$vm.Id.split("/")
            Write-Host "Stop VM: -ResourceGroupName " $strToken[4] " -name " $strToken[8]
            Stop-AzVM -ResourceGroupName $strToken[4] -name $strToken[8] -Force -AsJob

            $vm.HardwareProfile.VmSize = "E20ASv4"
            Update-AzVM -VM $vm -ResourceGroupName $DestResourceGroup
            Start-AzVM -ResourceGroupName $DestResourceGroup -Name $vmName
        }
        Write-Host (get-date).ToString('T') ": Waiting for all jobs to complete"
        Get-Job | Wait-Job -Timeout 180
        Get-Job | Remove-Job

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
        
        foreach ($vm in $srcHost.VirtualMachines) 
        {
            Write-Host "Iterate VM: " $vm.Id
            $strToken=$vm.Id.split("/")
            Start-AzVM -ResourceGroupName $strToken[4] -name $strToken[8] -AsJob            
        }

        Write-Host (get-date).ToString('T') ": Waiting for all jobs to complete"

        Get-Job | Wait-Job -Timeout 240
        Get-Job | Remove-Job

        Write-Host (get-date).ToString('T') ": All jobs have been completed"

        Remove-AzHost -ResourceGroupName $SourceResourceGroup -Name $SourceHostName

    }
}

# syntax
# Move-ADHVMs {srcResourceGroup} {srcHostGroup} {srcHostName} {dstResourceGroup} {dstHostGroup} {dstHostName}
