<# 	
 .NOTES
	==============================================================================================  
	File:		omsDeploy.ps1
	
	Purpose:	Automate deployment of OMS workspace, Automation Account via ARM template.
					
	Version: 	1.0.0.0 

	Author:	Shawn Tierney
 	==============================================================================================

 .SYNOPSIS
	Script to deploy OMS workspace and Automation account with preconfigured solutions, data collection and alerts.
  
 .DESCRIPTION
	This script will automate creation of resources required to execute automated deployments of OMS workspace and automation  via ARM template.  If required, a new storage account and container will be 
    provisioned and the template files will be copied from a local path to the storage container.  The template deployment will then access these files using a SAS token and deploy the OMS workspace 
    and Automation Account.

 .FUNCTIONS
    Fuctions:
    Deploy-StorageResources:  Deploys storage account and container
    Upload-Artifacts:  Copies arm template and scripts from local directory to storage container
		
    
 .EXAMPLE
	C:\PS>  .\omsDeploy.ps1 -subscriptionName 'Free Trial' -location 'East US' -customerPrefix 'testcorp' -artifactsAzurePrefix 'mycompany' -localArtifactsPath 'c:\temp' -storageType 'Standard_LRS'
	
	Description
	-----------
	This command will deploy the storage account and container where the template artifacts will be stored (if it does not already exist), copy 
    
 .PARAMETER subscriptionName
    This is the name of the subscription where the resources will be deployed. 

 .PARAMETER location
    Region where resources will be deployed. 

 .PARAMETER artifactsPrefix
   Only required if storage resources have not already been deployed.  Prefix added to the name of all resources deployed.  If not already deployed, this prefix will be added to the 
   beginning of the names for storage account, container, and resource group. If resources are already deployed, no new storage resources will be deployed.  For example, specifying testcorp will 
   result in a new resource group named testcorpartifacts-RG, a new storage account named testcorpartifacts, and a new storage container named testcorpartifacts.

 .PARAMETER storageType
   Specifies storage type for storage account.  For example, Standard_LRS specifies a standard account.

 .PARAMETER localArtifactsPath
   Local computer path to deployment artifacts (ARM templates, scripts, etc.).  For this deployment only the templates are necessary.  If new storage resources are deployed the artifacts (files) located 
   at this path will be uploaded to the new storage container.  These files will be utilized during the template deployment.  For example, if my template files are located in C:\Temp on my computer, 
   I will specify C:Temp here.

 
 .INPUTS
    None.

 .OUTPUTS
    None.
		   
 .LINK
	None.
#>  

Param(
            [parameter(Mandatory)]
            [string]$subscriptionName,

            [parameter(Mandatory)]
            [string]$location,

            [parameter(Mandatory)]
            [string]$customerPrefix,

            [parameter(Mandatory)]
            [string]$localArtifactsPath,

            [parameter(Mandatory)]
            [string]$artifactsPrefix
        )

#Function to deploy resource group, storage account, blob container, and copy artifacts to blob
Function Deploy-StorageResources {

    Param(
            [parameter(Mandatory)]
            [string]$subscriptionName,

            [parameter(Mandatory)]
            [string]$location,

            [parameter(Mandatory)]
            [string]$internalResourceGroup,

            [parameter(Mandatory)]
            [string]$storageAccount,

            [parameter(Mandatory)]
            [string]$storageType,

            [parameter(Mandatory)]
            [string]$storageContainer
        )


    #Select subscription 
    Select-AzureRmSubscription -SubscriptionName $subscriptionName

    #Create new resource group if it does not already exist 
    If ((Get-AzureRmResourceGroup -Name $internalResourceGroup -Location $location -ErrorAction SilentlyContinue) -eq $null) 
        {
            "Creating resource group...."
            New-AzureRmResourceGroup -Name $internalResourceGroup -Location $location
        }
    Else
        {
            "Resource group $internalResourceGroup already exists; skipping to create storage account...."
        }

    #Create new storage account
    If ((Get-AzureRmStorageAccount -ResourceGroupName $internalResourceGroup -Name $storageAccount -ErrorAction SilentlyContinue) -eq $null)
        {
            "Creating storage account...."
            New-AzureRmStorageAccount -ResourceGroupName $internalResourceGroup -Name $storageAccount -Location $location -SkuName $storageType
        }
    Else
        {
            "Storage account $storageAccount already exists; skipping to create storage container...."
        }

        $Script:StorageAccountContext = (Get-AzureRmStorageAccount -ResourceGroupName $internalResourceGroup -Name $storageAccount).Context

    #Create new storage container
    If ((Get-AzureStorageContainer -Name $storageContainer -Context $Script:StorageAccountContext -ErrorAction SilentlyContinue) -eq $null)
        {
            "Creating storage account container...."
            New-AzureStorageContainer -Name $storageContainer -Context $Script:StorageAccountContext -Permission Off
        }
    Else
        {
            "Storage accountcontainer $storageContainer already exists; skipping to create storage container...."
        }
}
#End function


#Function to upload artifacts to blob 
Function Upload-Artifacts{
    Param(
        [parameter(Mandatory)]
        [string]$localArtifactsPath,

        [parameter(Mandatory)]
        [string]$internalResourceGroup,

        [parameter(Mandatory)]
        [string]$storageAccount,

        [parameter(Mandatory)]
        [string]$storageContainer
        )
    #Get the list of files to upload
    "Retrieving artifacts to upload...."
    $files = Get-ChildItem -Path $localArtifactsPath -File

    Try{
        If ($files)
            {
                ForEach ($file in $files)
                    {
                        #Set the location and upload the content
                        "Uploading artifacts to $storageContainer...."
                        Select-AzureRmSubscription -SubscriptionName $subscriptionName
                        Set-AzureRmCurrentStorageAccount -ResourceGroupName $internalResourceGroup -Name $storageAccount
                        Set-AzureStorageBlobContent -Container $storageContainer -File $file.FullName -Force
                    }
            }
        Else
            {
                throw "No files exist in the $localArtifactsPath directory.  Aborting script."
            }
        }

   Catch 
       { 
                $errorMessages=“Exception Message: $($_.Exception.Message)”
                Write-Host "Error occurred in the Upload-Artifacts funcion. $ErrorMessage" -ForegroundColor Red
                break
       }        
    }
#End function

Function Create-KeyVault {
    Param(
            [parameter(Mandatory)]
            [string]$keyVault,

            [parameter(Mandatory)]
            [string]$keyVaultKey,

            [parameter(Mandatory)]
            [string]$internalResourceGroup,

            [parameter(Mandatory)]
            [string]$location
         )

    #Create key vault
    New-AzureRmKeyVault -VaultName $keyVault -ResourceGroupName $internalResourceGroup -Location $location -EnabledForTemplateDeployment

    #Create key vault secret
    Add-AzureKeyVaultKey -VaultName $keyVault -Name $keyVaultKey -Destination 'Software'

    $adminPass=ConvertTo-SecureString -String $keyVaultAdminPassword -AsPlainText -Force
    Set-AzureKeyVaultSecret -VaultName $keyVault -Name $keyVaultSecretName -SecretValue $adminPass
}
#End Function

###End Funcion Region###

###Begin Script Region###

#Internal subscription and local working file parameters - should not have to edit after first deployment
$internalResourceGroup=($artifactsPrefix + '-artifactsRG')
$storageAccount=($artifactsPrefix + 'artifacts')
$storageContainer=($artifactsPrefix + 'artifacts')
$storageType='Standard_LRS'

#Define parameters for functions 
$customerResourceGroup=($customerPrefix + '-omsRG')
#$customerLocation = <location where OMS workspace and automation account should be deployed if different than the internal location>er 


#Login to Azure
$credential=Get-Credential

Try
    {
        $loginCheck=Login-AzureRmAccount -Credential $credential

         If (!$loginCheck)
            {
                throw "logon failed"
                break 
            }
    }
Catch 
    {
        write-host "ExceptionMessage: $($_.Exception.Message)" -ForegroundColor Red
        $errorMessages += "ExceptionMessage: $($_.Exception.Message)"
        break
    }

#Select the correct subscription
Select-AzureRmSubscription -SubscriptionName $subscriptionName

#If not already deployed, deploy customer resource group
If ((Get-AzureRmResourceGroup -Name $customerResourceGroup -Location $location -ErrorAction SilentlyContinue) -eq $null) 
        {
            "Creating resource group $customerResourceGroup...."
            New-AzureRmResourceGroup -Name $customerResourceGroup -Location $location
        }
    Else
        {
            "Resource group $customerResourceGroup already exists; skipping to create storage account...."
        }

#If not already deployed, deploy centraldeployment storage and container resources
"Verifying internal storage account exists...."
If ((Get-AzureRmStorageAccount -ResourceGroupName $internalResourceGroup -Name $storageAccount -ErrorAction SilentlyContinue) -eq $null)
    {
        Deploy-StorageResources -subscriptionName $subscriptionName -location $location -internalResourceGroup $internalResourceGroup -storageAccount $storageAccount -storageType $storageType -storageContainer $storageContainer
    }
Else 
    {
        $StorageAccountContext = (Get-AzureRmStorageAccount -ResourceGroupName $internalResourceGroup -Name $storageAccount).Context
    }

"Verifying internal storage container exists...."
If ((Get-AzureStorageContainer -Container $storageContaine -Context $StorageAccountContext -ErrorAction SilentlyContinue) -eq $null)
    {
        Deploy-StorageResources -subscriptionName $subscriptionName -location $location -internalResourceGroup $internalResourceGroup -storageAccount $storageAccount -storageType $storageType -storageContainer $storageContainer
    }

#If not already uploaded, upload ARM template, scripts, etc. used for deployment
"Verifying artifacts exist...."
If ((Get-AzureStorageBlob -Container $storageContainer -Context $StorageAccountContext ) -eq $null)
    {
        Upload-Artifacts -localArtifactsPath $localArtifactsPath -internalResourceGroup $internalResourceGroup -storageAccount $storageAccount -storageContainer $storageContainer
    }

#Verify that artifacts were uploaded
"Verifying artifacts uploaded...."
Set-AzureRmCurrentStorageAccount -ResourceGroupName $internalResourceGroup -Name $storageAccount
$artifactsCheck = Get-AzureStorageBlob -Container $storageContainer

If (!$artifactsCheck)
    {
        throw "Failed to copy files to to $storageContainer"
    }

#Deploy the ARM template

#Define the template parameters (can use param.json file instead but I was unable to get the SAS token working with the param.json method)
$TemplateParams=[ordered]@{
                    "templateURI"=($storageContainerURI + '/deployOms.json' + $token)
                    "omsWorkspaceName"=($customerPrefix + '-oms')
                    "omsWorkspaceRegion"='East US'
                    "omsAutomationAccount"=($customerPrefix + '-omsAutomation')
                    "omsAutomationRegion"='East US 2'
                    "azureAdmin"=$credential.UserName
                    "azureAdminPwd"=($credential.Password | ConvertTo-SecureString -AsPlainText -Force)
                    "_artifactsLocation"=$storageContainerURI
                    "_artifactsLocationSasToken"=$token
                    }

#Storage sas token parameters - do not need to edit
"Setting storage container URI variable...."
$storageContainerURI=(Get-AzureStorageContainer -Name $storageContainer -Context $StorageAccountContext).CloudBlobContainer.Uri.AbsoluteUri

#Get SAS token for template
"Creating SAS token to access templates for deployment...."
Set-AzureRmCurrentStorageAccount -ResourceGroupName $internalResourceGroup -Name $storageAccount
$token = New-AzureStorageContainerSASToken -Name $storageContainer -Permission r -ExpiryTime (Get-Date).AddMinutes(30.0)

#Deploy template
"Deploying template...."
Test-AzureRmResourceGroupDeployment -ResourceGroupName $customerResourceGroup -TemplateFile C:\temp\gigaDeploy\gigatest_v1.json

#Debug
##$(Get-AzureRmLog -Status "Failed" -DetailedOutput).Properties | fl