# Copyright(c) Microsoft and contributors. All rights reserved
#
# This source code is licensed under the MIT license found in the LICENSE file in the root directory of the source tree

<#
.SYNOPSIS
    This script performs pool change for specific volume
.DESCRIPTION
    Authenticates with Azure, and then creates account, primary pool with Premium service level and Secondary pool with standard service level and a volume in a primary pool then move the volume to the secondary pool.
.PARAMETER ResourceGroupName
    Name of the Azure Resource Group where the ANF will be created
.PARAMETER Location
    Azure Location (e.g 'WestUS', 'EastUS')
.PARAMETER NetAppAccountName
    Name of the Azure NetApp Files Account
.PARAMETER PrimaryNetAppPoolName
    Name of the Azure NetApp Files primary Capacity Pool
.PARAMETER PrimaryServiceLevel
    Service Level - Ultra, Premium or Standard
.PARAMETER SecondaryNetAppPoolName
    Name of the Azure NetApp Files secondary Capacity Pool
.PARAMETER SecondaryServiceLevel
    Service Level - Ultra, Premium or Standard
.PARAMETER NetAppPoolSize
    Size of the Azure NetApp Files Capacity Pool in Bytes. Range between 4398046511104 and 549755813888000
.PARAMETER NetAppVolumeName\
    Name of the Azure NetApp Files Volume
.PARAMETER NetAppVolumeSize
    Size of the Azure NetApp Files volume in Bytes. Range between 107374182400 and 109951162777600
.PARAMETER SubnetId
    The Delegated subnet Id within the VNET
.PARAMETER CleanupResources
    If the script should clean up the resources, $false by default
.EXAMPLE
    PS C:\\> ANFPoolChange.ps1
#>
param
(
    # Name of the Azure Resource Group
    [string]$ResourceGroupName = 'My-RG',

    #Azure location 
    [string]$Location ='CentralUS',

    #Azure NetApp Files account name
    [string]$NetAppAccountName = 'anfaccount',

    #Azure NetApp Files Primary capacity pool name
    [string]$PrimaryNetAppPoolName = 'pool1' ,

    # Primary Service Level, can be {Ultra, Premium or Standard}
    [ValidateSet("Ultra","Premium","Standard")]
    [string]$PrimaryServiceLevel = 'Premium',

     #Azure NetApp Files Secondary capacity pool name
    [string]$SecondaryNetAppPoolName = 'pool2' ,

    # Secondary Service Level. can be {Ultra, Premium or Standard}
    [ValidateSet("Ultra","Premium","Standard")]
    [string]$SecondaryServiceLevel = 'Standard',

    #Azure NetApp Files capacity pool size
    [ValidateRange(4398046511104,549755813888000)]
    [long]$NetAppPoolSize = 4398046511104,

    #Azure NetApp Files volume name
    [string]$NetAppVolumeName = 'vol1',

    #Azure NetApp Files volume size
    [ValidateRange(107374182400,109951162777600)]
    [long]$NetAppVolumeSize = 107374182400,

    #Subnet Id 
    [string]$SubnetId = 'Subnet ID',
    
    #Clean Up resources
    [bool]$CleanupResources = $false
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


# Authorizing and connecting to Azure
Write-Verbose -Message "Authorizing with Azure Account..." -Verbose
Connect-AzAccount

# Create Azure NetApp Files Account
Write-Verbose -Message "Creating Azure NetApp Files Account" -Verbose
$NewAccount = New-AzNetAppFilesAccount -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -Name $NetAppAccountName `
    -ErrorAction Stop
Write-Verbose -Message "Azure NetApp Account has been created successfully: $($NewAccount.Id)" -Verbose


# Create Azure NetApp Files Primary Capacity Pool
Write-Verbose -Message "Creating Azure NetApp Files Primary Capacity Pool" -Verbose
$NewPrimaryPool = New-AzNetAppFilesPool -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AccountName $NetAppAccountName `
    -Name $PrimaryNetAppPoolName `
    -PoolSize $NetAppPoolSize `
    -ServiceLevel $PrimaryServiceLevel `
    -ErrorAction Stop
Write-Verbose -Message "Azure NetApp Primary Capacity Pool has been created successfully: $($NewPrimaryPool.Id)" -Verbose

# Create Azure NetApp Files Secondary Capacity Pool
Write-Verbose -Message "Creating Azure NetApp Files Secondary Capacity Pool" -Verbose
$NewSecondaryPool = New-AzNetAppFilesPool -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AccountName $NetAppAccountName `
    -Name $SecondaryNetAppPoolName `
    -PoolSize $NetAppPoolSize `
    -ServiceLevel $SecondaryServiceLevel `
    -ErrorAction Stop
Write-Verbose -Message "Azure NetApp Secondary Capacity Pool has been created successfully: $($NewSecondaryPool.Id)" -Verbose

#Create Azure NetApp Files NFS Volume
Write-Verbose -Message "Creating Azure NetApp Files Volume" -Verbose

$ExportPolicyRule = New-Object -TypeName Microsoft.Azure.Commands.NetAppFiles.Models.PSNetAppFilesExportPolicyRule
$ExportPolicyRule.RuleIndex =1
$ExportPolicyRule.UnixReadOnly =$false
$ExportPolicyRule.UnixReadWrite =$true
$ExportPolicyRule.Cifs = $false
$ExportPolicyRule.Nfsv3 = $false
$ExportPolicyRule.Nfsv41 = $true
$ExportPolicyRule.AllowedClients ="0.0.0.0/0"

$ExportPolicy = New-Object -TypeName Microsoft.Azure.Commands.NetAppFiles.Models.PSNetAppFilesVolumeExportPolicy -Property @{Rules = $ExportPolicyRule}

$NewVolume = New-AzNetAppFilesVolume -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AccountName $NetAppAccountName `
    -PoolName $PrimaryNetAppPoolName `
    -Name $NetAppVolumeName `
    -UsageThreshold $NetAppVolumeSize `
    -ProtocolType "NFSv4.1" `
    -ServiceLevel $PrimaryServiceLevel `
    -SubnetId $SubnetId `
    -CreationToken $NetAppVolumeName `
    -ExportPolicy $ExportPolicy `
    -ErrorAction Stop

Write-Verbose -Message "Azure NetApp Files has been created successfully." -Verbose

# Performing Pool Change
Write-Verbose -Message "Performing Pool Change, updating volume..."
Set-AzNetAppFilesVolumePool -ResourceGroupName $ResourceGroupName `
    -AccountName $NetAppAccountName `
    -PoolName $PrimaryNetAppPoolName `
    -Name $NetAppVolumeName `
    -NewPoolResourceId $($NewSecondaryPool.Id) `
    -ErrorAction Stop

if($CleanupResources)
{
    
    Write-Verbose -Message "Cleaning up Azure NetApp Files resources..." -Verbose

    #Deleting NetApp Files Volume
    Write-Verbose -Message "Deleting Azure NetApp Files Volume: $NetAppVolumeName" -Verbose
    Remove-AzNetAppFilesVolume -ResourceGroupName $ResourceGroupName `
            -AccountName $NetAppAccountName `
            -PoolName $SecondaryNetAppPoolName `
            -Name $NetAppVolumeName `
            -ErrorAction Stop

    #Deleting NetApp Files Primary Pool
    Write-Verbose -Message "Deleting Azure NetApp Files Primary pool: $PrimaryNetAppPoolName" -Verbose
    Remove-AzNetAppFilesPool -ResourceGroupName $ResourceGroupName `
        -AccountName $NetAppAccountName `
        -PoolName $PrimaryNetAppPoolName `
        -ErrorAction Stop

    #Deleting NetApp Files Secondary Pool
    Write-Verbose -Message "Deleting Azure NetApp Files Secondary pool: $SecondaryNetAppPoolName" -Verbose
    Remove-AzNetAppFilesPool -ResourceGroupName $ResourceGroupName `
        -AccountName $NetAppAccountName `
        -PoolName $SecondaryNetAppPoolName `
        -ErrorAction Stop

    #Deleting NetApp Files account
    Write-Verbose -Message "Deleting Azure NetApp Files Volume: $NetAppVolumeName" -Verbose
    Remove-AzNetAppFilesAccount -ResourceGroupName $ResourceGroupName -Name $NetAppAccountName -ErrorAction Stop

    Write-Verbose -Message "All Azure NetApp Files resources have been deleted successfully." -Verbose    
}
