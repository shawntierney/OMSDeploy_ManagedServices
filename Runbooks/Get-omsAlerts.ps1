Write-Output "Getting Azure credentials...."
#Get Creds
$azureUser="testUser"
$azureCred = Get-AutomationPSCredential -Name $azureUser

$errorMessages = @()

#Verify that the credential asset was able to be retrieved
If (!$azureCred)
    {
        Write-Output "Could not get Azure credential, terminating script."
        break
    }
Else
    {
        Write-Output "Retrieved Azure credential asset...."
    }

#Log into Azure
Try
    {
        "Logging into Azure...."
        $loginCheck=Login-AzureRmAccount -Credential $azureCred

         If (!$loginCheck)
            {
                throw "logon failed"
                break 
            }
    }
Catch 
    {
        Write-Output "ExceptionMessage: $($_.Exception.Message)" 
        $errorMessages += "ExceptionMessage: $($_.Exception.Message)"
        break
    }


#Select the subscription where the OMS workspaces are managed
Select-AzureRmSubscription -SubscriptionName "Microsoft Azure Sponsorship"

Try
    {
        #Get a list of OMS workspaces and master workspace key
        "Retrieving OMS workspaces and master workspace key...."
        $omsWorkspaces = Get-AzureRmOperationalInsightsWorkspace


        #Get details for master workspace
        $masterOmsWorkspace = $omsWorkspaces | Where-Object {$_.Name -eq "workspacename"}
        $masterOmsKey = (Get-AzureRmOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $masterOmsWorkspace.ResourceGroupName -Name $masterOmsWorkspace.Name).PrimarySharedKey
        $masterWorkspaceId = $masterOmsWorkspace.CustomerId
    }
Catch
    {
        Write-Output "ExceptionMessage: $($_.Exception.Message)" 
        $errorMessages += "ExceptionMessage: $($_.Exception.Message)"
        break
    }

#Save the AzureRmProfile to pass Azure login to jobs
Save-AzureRmProfile -Path .\azureCreds.json -Force

"Starting loop...."
#For each workspace, execute a job to poll for alerts and pass alerts to the master OMS workspace via the data collector API
ForEach ($workspace in $omsWorkspaces)
    {
    $job = Start-Job -ArgumentList($workspace,$masterWorkspaceId,$masterOmsKey) -ScriptBlock {

    Param ($workspace,$masterWorkspaceId,$masterOmsKey)
        
        Select-AzureRmProfile -Path .\azureCreds.json | Out-Null

        #Set customer and workspace key variables
        $customer=($workspace.Name).split('-')[0]

        "Retrieving workspace key for $customer...."
        $workspaceKey=(Get-AzureRmOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $workspace.ResourceGroupName -Name $workspace.Name).PrimarySharedKey

        If (!$workspaceKey)
            {
                Write-Error "Unable to retreive workspace key for $customer."
            }

        #Query OMS for new alerts
        "Querying $customer workspace for new alerts...."
        Import-Module AzureRm.OperationalInsights
        $dynamicQuery = 'Type=Alert SourceSystem=OMS SourceSystem=OMS AlertSeverity=Critical TimeGenerated>Now-30Days'
        $result = Get-AzureRmOperationalInsightsSearchResults `
         -ResourceGroupName $workspace.ResourceGroupName `
         -WorkspaceName $workspace.Name `
         -Query $dynamicQuery
        $omsAlerts=$result.Value | ConvertFrom-Json

        #Write status to console and return $omsAlerts
        write-host "Alerts for $($customer) workspace: " -ForegroundColor Green
        $omsAlerts | Out-Null

        #Define custom for API
        $logtype="omsManagedAlerts"
        $timestampfield = "" 
        
        #If alerts exist, format OMS schema and write output to the master OMS workspace
        If ($omsAlerts)
            {
                ForEach ($alert in $omsAlerts)
                    {
                        $omsAlerts= New-Object PSObject ([ordered]@{
                              Customer=$customer
                              WorkspaceName=$workspace.Name
                              AlertName=$alert.AlertName
                              AlertDescription=$alert.AlertDescription
                              Computer=$alert.Computer
                              AlertSeverity=$alert.AlertSeverity
                              TimeGenerated=$alert.TimeGenerated
                              AlertRuleId=$alert.AlertRuleId
                              AlertQuery=$alert.Query
                              })
                       $jsonTable = ConvertTo-Json -InputObject $omsAlerts
                       $jsonTable
                       
                       #Send data to OMS
                       Send-OMSAPIIngestionFile -customerId $masterWorkspaceId  -sharedKey $masterOmsKey -body $jsonTable -logType $logtype -TimeStampField $Timestampfield
                    }#ForEach
            }#If
       Else
          {
          "There are no new alerts for $customer...."
          }
    } #ScriptBlock

    #Return job results
    #$result = $job | Receive-Job -Wait

    #Return job errors
    #$job | Receive-Job -Keep -ErrorVariable jobErrors
    #$errorMessages+=$jobErrors
    #$errorMessages+=$job.ChildJobs[0].JobStateInfo.Reason | fl * -force

    #Remove job
    #Remove-Job $job
   }#ForEach

#Return all errros
 Write-Output $errorMessages