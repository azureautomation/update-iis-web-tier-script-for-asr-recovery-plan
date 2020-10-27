<#
.SYNOPSIS
    Runs a PowerShell script updating Site Bindings on IIS server and Wbb farms on ARR.

.DESCRIPTION
    After Failover of data and web tier in IIS workload, this runbook runs powershell script which updates Site Bindings on IIS server and Wbb farms on ARR.
    This runbook requires  Push-AzureVMCommand runbook to be imported from gallery in azure automation account.
   
.DEPENDENCIES
    Azure VM agent should be installed in the VM before it is executed
    If it is not already installed install it inside the VM from http://aka.ms/vmagentwin
    Script that needs to run inside the virtual machine should already be uploaded in a storage account


    Download IIS-Update-SiteBindings.ps1 script from https://aka.ms/asr-iis-update-site-binding-script-classic and store it locally. Use the local path in "ScriptLocalFilePath" variable.
    Now upload the script to your Azure storage account using following command. Command is given the example value.
     Replace following items as per your account name and key and container name: 
    "ScriptScriptStorageAccountName", ScriptStorageAccountKey", "ContainerName"

    $context = New-AzureStorageContext -ScriptStorageAccountName "ScriptScriptStorageAccountName" -StorageAccountKey "ScriptStorageAccountKey"
    Set-AzureStorageBlobContent -Blob "IIS-Update-SiteBindings.ps1" -Container "ContainerName" -File "ScriptLocalFilePath" -context $context

    
    Specify $AutomationAccountName with the required value. Runbook needs it to create an asset.

.ASSETS
    Add below Assets 
    'ScriptScriptStorageAccountName': Name of the storage account where the script is stored
    'ScriptStorageAccountKey': Key for the storage account where the script is stored
    'AzureSubscriptionName': Azure Subscription Name to use
    'ContainerName': Container in which script is uploaded
    'IIS-Update-SiteBindings': Name of script
    in the azure automation account	
    You can choose to encrtypt these assets

.PARAMETER RecoveryPlanContext
    RecoveryPlanContext is the only parameter you need to define.
    This parameter gets the failover context from the recovery plan. 

.NOTE
    The script is to be run only on Azure classic resources. It is not supported for Azure Resource Manager resources.

    Author: sakulkar@microsoft.com
#>

workflow IISWebTierUpdate
{
    param
    (
        [Object]$RecoveryPlanContext
    )
    try
    {
        $AzureOrgIdCredential = Get-AutomationPSCredential -Name 'AzureOrgIdCredential'
        $AzureAccount = Add-AzureAccount -Credential $AzureOrgIdCredential
        $AzureSubscriptionName = Get-AutomationVariable -Name 'AzureSubscriptionName'
        Select-AzureSubscription -SubscriptionName $AzureSubscriptionName

        #Provide Automation Account Details
        $AutomationAccountName = "e2a-bcdr"

        $vmMap = $RecoveryPlanContext.VmMap.PsObject.Properties
        $RecoveryPlanName = $RecoveryPlanContext.RecoveryPlanName

        #Provide the storage account name and the storage account key information
        $ScriptStorageAccountName = Get-AutomationVariable -Name 'ScriptScriptStorageAccountName'

        #Script Details
        $ContainerName = Get-AutomationVariable -Name 'ContainerName'
        $ScriptName = "IIS-Update-SiteBindings.ps1"

        foreach($VMProperty in $vmMap)
        {
            $VM = $VMProperty.Value
            $VMName = $VMProperty.Value.RoleName
            $VMNames = "$VMNames,$VMName"
            $ServiceName = $VMProperty.Value.CloudServiceName
        }

        $VMNameList = $VMNames.split(",")
        
        foreach($VMName in VMNameList)
        {
            if(($VMName -ne $null) -or ($VMName -ne ""))
            {
                Write-Output "Updating Site Bindings on IIS VM"

                $IPMapping = Push-AzureVMCommand `
                -AzureOrgIdCredential $AzureOrgIdCredential `
                -AzureSubscriptionName $AzureSubscriptionName `
                -Container $ContainerName `
                -ScriptName $ScriptName `
                -ServiceName $ServiceName `
                -ScriptStorageAccountName $ScriptStorageAccountName `
                -TimeoutLimitInSeconds 600 `
                -VMName $VMName `
                -WaitForCompletion $true

                Write-output "IP Address Mapping  - $IPMapping"

                $IPMappingString = $IPMappingString+","+$IPMapping

                InLineScript
                {
                    $AssetName = "$Using:RecoveryPlanName-IPMapping"
                    $IPMappings = $Using:IPMappingString
                    write-output $IPMappings
                    $IPMappingsList = $IPMappings.split(",")
                    Write-output $IPMappingsList
                    $IPMappingAsset=@{}
                    for($i=1;$i -lt $IPMappingsList.Length;$i=$i+2)
                    {
                        write-output "Old IP Address:New IP Address Pair - $IPMappingsList[$i]:$IPMappingsList[$i+1] "
                        $IPMappingAsset.add($IPMappingsList[$i],$IPMappingsList[$i+1])
                    }
                    $sIPMappingAsset=[system.management.automation.psserializer]::Serialize($IPMappingAsset)
                    write-output $sIPMappingAsset
                    New-AzureAutomationVariable -Name $AssetName -Value $sIPMappingAsset -AutomationAccountName $AutomationAccountName -Encrypted $false  -ErrorAction Stop
                }
                Write-Output "Updated Site Bindings on IIS VM"
            }
        }
    }
    catch
    {
        $ErrorMessage = $ErrorMessage+$_.Exception.Message
        Write-output $ErrorMessage
    }
}