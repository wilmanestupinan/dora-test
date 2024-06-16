#Parameters for the top level  deploymentfrequency.ps1 PowerShell script
Param(
    [string] $ownerRepo,
    [string] $workflows,
    [string] $branch,
    [Int32] $numberOfDays,
    [string] $patToken = "",
    [string] $actionsToken = ""
)

#The main function
function Main ([string] $ownerRepo,
    [string] $workflows,
    [string] $branch,
    [Int32] $numberOfDays,
    [string] $patToken = "",
    [string] $actionsToken = "")
{

    #==========================================
    #Input processing
    $ownerRepoArray = $ownerRepo -split '/'
    $owner = $ownerRepoArray[0]
    $repo = $ownerRepoArray[1]
    $workflowsArray = $workflows -split ','
    $numberOfDays = $numberOfDays       
    Write-Host "Owner/Repo: $owner/$repo"
    Write-Host "Workflows: $workflows"
    Write-Host "Branch: $branch"
    Write-Host "Number of days: $numberOfDays"

    #==========================================
    # Get authorization headers  
    $authHeader = GetAuthHeader $patToken $actionsToken

    #==========================================
    #Get workflow definitions from github
    $uri = "https://api.github.com/repos/$owner/$repo/actions/workflows"
    if (!$authHeader)
    {
        #No authentication
        $workflowsResponse = Invoke-RestMethod -Uri $uri -ContentType application/json -Method Get -SkipHttpErrorCheck -StatusCodeVariable "HTTPStatus"
    }
    else
    {
        #there is authentication
        $workflowsResponse = Invoke-RestMethod -Uri $uri -ContentType application/json -Method Get -Headers @{Authorization=($authHeader["Authorization"])} -SkipHttpErrorCheck -StatusCodeVariable "HTTPStatus" 
        #$workflowsResponse = Invoke-RestMethod -Uri $uri -ContentType application/json -Method Get -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -ErrorAction Stop
    }
    if ($HTTPStatus -eq "404")
    {
        Write-Output "Repo is not found or you do not have access"
        break
    }  

    #Extract workflow ids from the definitions, using the array of names. Number of Ids should == number of workflow names
    $workflowIds = [System.Collections.ArrayList]@()
    $workflowNames = [System.Collections.ArrayList]@()
    Foreach ($workflow in $workflowsResponse.workflows){

        Foreach ($arrayItem in $workflowsArray){
            if ($workflow.name -eq $arrayItem)
            {
                #This looks odd: but assigning to a (throwaway) variable stops the index of the arraylist being output to the console. Using an arraylist over an array has advantages making this worth it for here
                if (!$workflowIds.Contains($workflow.id))
                {
                    $result = $workflowIds.Add($workflow.id)
                }
                if (!$workflowNames.Contains($workflow.name))
                {
                    $result = $workflowNames.Add($workflow.name)
                }
            }
        }
    }

    #==========================================
    #Filter out workflows that were successful. Measure the number by date/day. Aggegate workflows together
    $dateList = @()
    $uniqueDates = @()
    $deploymentsPerDayList = @()
    
    #For each workflow id, get the last 100 workflows from github
    Foreach ($workflowId in $workflowIds){
        #Get workflow definitions from github
        $uri2 = "https://api.github.com/repos/$owner/$repo/actions/workflows/$workflowId/runs?per_page=100&status=completed"
        if (!$authHeader)
        {
            $workflowRunsResponse = Invoke-RestMethod -Uri $uri2 -ContentType application/json -Method Get -SkipHttpErrorCheck -StatusCodeVariable "HTTPStatus"
        }
        else
        {
            $workflowRunsResponse = Invoke-RestMethod -Uri $uri2 -ContentType application/json -Method Get -Headers @{Authorization=($authHeader["Authorization"])} -SkipHttpErrorCheck -StatusCodeVariable "HTTPStatus"      
        }

        $buildTotal = 0
        Foreach ($run in $workflowRunsResponse.workflow_runs){
            #Count workflows that are completed, on the target branch, and were created within the day range we are looking at
            if ($run.head_branch -eq $branch -and $run.created_at -gt (Get-Date).AddDays(-$numberOfDays))
            {
                #Write-Host "Adding item with status $($run.status), branch $($run.head_branch), created at $($run.created_at), compared to $((Get-Date).AddDays(-$numberOfDays))"
                $buildTotal++       
                #get the workflow start and end time            
                $dateList += New-Object PSObject -Property @{start_datetime=$run.created_at;end_datetime=$run.updated_at}
                $uniqueDates += $run.created_at.Date.ToString("yyyy-MM-dd")     
            }
        }

        if ($dateList.Length -gt 0)
        {
            #==========================================
            #Calculate deployments per day
            $deploymentsPerDay = 0

            if ($dateList.Count -gt 0 -and $numberOfDays -gt 0)
            {
                $deploymentsPerDay = $dateList.Count / $numberOfDays
            }
            $deploymentsPerDayList += $deploymentsPerDay
            #Write-Host "Adding to list, workflow id $workflowId deployments per day of $deploymentsPerDay"
        }
    }

    $totalDeployments = 0
    Foreach ($deploymentItem in $deploymentsPerDayList){
        $totalDeployments += $deploymentItem
    }
    if ($deploymentsPerDayList.Length -gt 0)
    {
        $deploymentsPerDay = $totalDeployments / $deploymentsPerDayList.Length
    }
    Write-Host "Total deployments $totalDeployments with a final deployments value of $deploymentsPerDay"

    #==========================================
    #Show current rate limit
    $uri3 = "https://api.github.com/rate_limit"
    if (!$authHeader)
    {
        $rateLimitResponse = Invoke-RestMethod -Uri $uri3 -ContentType application/json -Method Get -SkipHttpErrorCheck -StatusCodeVariable "HTTPStatus"
    }
    else
    {
        $rateLimitResponse = Invoke-RestMethod -Uri $uri3 -ContentType application/json -Method Get -Headers @{Authorization=($authHeader["Authorization"])} -SkipHttpErrorCheck -StatusCodeVariable "HTTPStatus"
    }    
    Write-Host "Rate limit consumption: $($rateLimitResponse.rate.used) / $($rateLimitResponse.rate.limit)"    

    #==========================================
    #Calculate deployments per day
    $deploymentsPerDay = 0

    if ($dateList.Count -gt 0 -and $numberOfDays -gt 0)
    {
        $deploymentsPerDay = $dateList.Count / $numberOfDays
        # get unique values in $uniqueDates
        $uniqueDates = $uniqueDates | Sort-Object | Get-Unique
    }

    #==========================================
    #output result
    $dailyDeployment = 1
    $weeklyDeployment = 1 / 7
    $monthlyDeployment = 1 / 30
    $everySixMonthsDeployment = 1 / (6 * 30) #Every 6 months
    $yearlyDeployment = 1 / 365

    #Calculate rating, metric, and unit
    if ($deploymentsPerDay -le 0)
    {
        $rating = "None"
        $color = "lightgrey"
        $displayMetric = 0
        $displayUnit = "per day"
    }
    elseif ($deploymentsPerDay -gt $dailyDeployment) 
    {
        $rating = "Elite"
        $color = "brightgreen"
        $displayMetric = [math]::Round($deploymentsPerDay,2)
        $displayUnit = "per day"
    }
    elseif ($deploymentsPerDay -le $dailyDeployment -and $deploymentsPerDay -ge $weeklyDeployment)
    {
        $rating = "High"
        $color = "green"
        $displayMetric = [math]::Round($deploymentsPerDay * 7,2)
        $displayUnit = "times per week"
    }
    elseif ($deploymentsPerDay -lt $weeklyDeployment -and $deploymentsPerDay -ge $monthlyDeployment)
    {
        $rating = "Medium"
        $color = "yellow"
        $displayMetric = [math]::Round($deploymentsPerDay * 30,2)
        $displayUnit = "times per month"
    }
    elseif ($deploymentsPerDay -lt $monthlyDeployment -and $deploymentsPerDay -gt $yearlyDeployment)
    {
        $rating = "Low"
        $color = "red"
        $displayMetric = [math]::Round($deploymentsPerDay * 30,2)
        $displayUnit = "times per month"
    }
    elseif ($deploymentsPerDay -le $yearlyDeployment)
    {
        $rating = "Low"
        $color = "red"
        $displayMetric = [math]::Round($deploymentsPerDay * 365,2)
        $displayUnit = "times per year"
    }

    if ($dateList.Count -gt 0 -and $numberOfDays -gt 0)
    {
        Write-Host "Deployment frequency over last $numberOfDays days, is $displayMetric $displayUnit, with a DORA rating of '$rating'"   
        
        $resultObject = @{
        DeploymentFrequency = [math]::Round($deploymentsPerDay*7, 2)
        Rating = $rating
        NumberOfUniqueDeploymentDays = $uniqueDates.Length
        TotalDeployments = $totalDeployments
        }
        
        # Convert the result object to JSON
        $jsonResult = $resultObject | ConvertTo-Json -Compress
        
        # Output the JSON string
        Write-Output "###JSON_START###"  # This marker helps to easily identify the JSON part in the output
        Write-Output $jsonResult
        return GetFormattedMarkdown -workflowNames $workflowNames -displayMetric $displayMetric -displayUnit $displayUnit -repo $ownerRepo -branch $branch -numberOfDays $numberOfDays -numberOfUniqueDates $uniqueDates.Length.ToString() -color $color -rating $rating
    }
    else
    {

        $resultObject = @{
        DeploymentFrequency = [math]::Round($deploymentsPerDay*7, 2)
        Rating = $rating
        NumberOfUniqueDeploymentDays = $uniqueDates.Length
        TotalDeployments = $totalDeployments
        }
        
        # Convert the result object to JSON
        $jsonResult = $resultObject | ConvertTo-Json -Compress
        
        # Output the JSON string
        Write-Output "###JSON_START###"  # This marker helps to easily identify the JSON part in the output
        Write-Output $jsonResult
        
        return GetFormattedMarkdownForNoResult -workflows $workflows -numberOfDays $numberOfDays
    }
}

#Generate the authorization header for the PowerShell call to the GitHub API
#warning: PowerShell has really wacky return semantics - all output is captured, and returned
#reference: https://stackoverflow.com/questions/10286164/function-return-value-in-powershell
function GetAuthHeader ([string] $patToken, [string] $actionsToken, [string] $appId, [string] $appInstallationId, [string] $appPrivateKey) 
{
    #Clean the string - without this the PAT TOKEN doesn't process
    $patToken = $patToken.Trim()
    if (![string]::IsNullOrEmpty($patToken))
    {
        Write-Host "Authentication detected: PAT TOKEN"
        $base64AuthInfo = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$patToken"))
        $authHeader = @{Authorization=("Basic {0}" -f $base64AuthInfo)}
    }
    elseif (![string]::IsNullOrEmpty($actionsToken))
    {
        Write-Host "Authentication detected: GITHUB TOKEN"  
        $authHeader = @{Authorization=("Bearer {0}" -f $base64AuthInfo)}
    } 
    else
    {
        Write-Host "No authentication detected" 
        $base64AuthInfo = $null
        $authHeader = $null
    }

    return $authHeader
}

function ConvertTo-Base64UrlString(
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]$in) 
{
    if ($in -is [string]) {
        return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($in)) -replace '\+','-' -replace '/','_' -replace '='
    }
    elseif ($in -is [byte[]]) {
        return [Convert]::ToBase64String($in) -replace '\+','-' -replace '/','_' -replace '='
    }
    else {
        throw "GitHub App authenication error: ConvertTo-Base64UrlString requires string or byte array input, received $($in.GetType())"
    }
}

# Format output for deployment frequency in markdown
function GetFormattedMarkdown([array] $workflowNames, [string] $rating, [string] $displayMetric, [string] $displayUnit, [string] $repo, [string] $branch, [string] $numberOfDays, [string] $numberOfUniqueDates, [string] $color)
{
    $encodedString = [uri]::EscapeUriString($displayMetric + " " + $displayUnit)
    #double newline to start the line helps with formatting in GitHub logs
    $markdown = "`n`n![Deployment Frequency](https://img.shields.io/badge/frequency-" + $encodedString + "-" + $color + "?logo=github&label=Deployment%20frequency)`n" +
        "**Definition:** For the primary application or service, how often is it successfully deployed to production.`n" +
        "**Results:** Deployment frequency is **$displayMetric $displayUnit** with a **$rating** rating, over the last **$numberOfDays days**.`n" + 
        "**Details**:`n" + 
        "- Repository: $repo using $branch branch`n" + 
        "- Workflow(s) used: $($workflowNames -join ", ")`n" +
        "- Active days of deployment: $numberOfUniqueDates days`n" + 
        "---"
    return $markdown
}

function GetFormattedMarkdownForNoResult([string] $workflows, [string] $numberOfDays)
{
    #double newline to start the line helps with formatting in GitHub logs
    $markdown = "`n`n![Deployment Frequency](https://img.shields.io/badge/frequency-none-lightgrey?logo=github&label=Deployment%20frequency)`n`n" +
        "No data to display for $ownerRepo for workflow(s) $workflows over the last $numberOfDays days`n`n" + 
        "---"
    return $markdown
}

main -ownerRepo $ownerRepo -workflows $workflows -branch $branch -numberOfDays $numberOfDays -patToken $patToken -actionsToken $actionsToken

