$tools = @("az", "func")

foreach ($tool in $tools) {
  if (!(Get-Command $tool -ErrorAction SilentlyContinue)) {
    Write-Host "Error: $tool command line tool is not available, check pre-requisites in README.md"
    exit 1
  }
}

Write-Host "Loading azd .env file from current environment"
foreach ($line in (& azd env get-values)) {
    if ($line -match "([^=]+)=(.*)") {
        $key = $matches[1]
        $value = $matches[2] -replace '^"|"$'
        [Environment]::SetEnvironmentVariable($key, $value)
    }
}

Write-Host "Installing PowerShell modules for Flex Consumption deployment..."
cd ./src

# Install Azure PowerShell modules if not already present
if (!(Test-Path "Modules") -or (Test-Path "Modules" -and (Get-ChildItem "Modules" -Force | Measure-Object).Count -eq 0)) {
    Write-Host "Modules directory not found or empty. Installing Azure PowerShell modules..."
    
    # Check if PowerShell Core is available (this script is already running in PowerShell, but let's be explicit)
    try {
        $pwshVersion = $PSVersionTable.PSVersion
        Write-Host "Using PowerShell version: $pwshVersion"
        
        if ($pwshVersion.Major -lt 7) {
            Write-Warning "PowerShell 7+ is recommended for best compatibility."
        }
        
        & .\install-modules.ps1
    } catch {
        Write-Error "Failed to install PowerShell modules: $_"
        Write-Host "Please install PowerShell modules manually:"
        Write-Host "1. Ensure PowerShell Core 7+ is installed: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell"
        Write-Host "2. Run: pwsh ./install-modules.ps1"
        Write-Host "3. Re-run: azd up"
        Write-Host ""
        Write-Host "Alternatively, use a system with PowerShell Core installed for deployment."
        exit 1
    }
} else {
    Write-Host "Modules directory found with content. Skipping module installation."
}

func azure functionapp publish $env:AZURE_FUNCTION_APP_NAME --powershell

Write-Host "Deployment completed. Creating event grid subscription."

#Get the function blobs_extension key
$blobs_extension=$(az functionapp keys list -n ${env:AZURE_FUNCTION_APP_NAME} -g ${env:RESOURCE_GROUP} --query "systemKeys.blobs_extension" -o tsv)

# Build the endpoint URL with the function name and extension key and create the event subscription
# Double quotes added here to allow the az command to work successfully. Quoting inside az command had issues.
$endpointUrl="""https://" + ${env:AZURE_FUNCTION_APP_NAME} + ".azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.ProcessBlobUpload&code=" + $blobs_extension + """"

$filter="/blobServices/default/containers/" + ${env:UNPROCESSED_PDF_CONTAINER_NAME}

az eventgrid system-topic event-subscription create -n unprocessed-pdf-topic-subscription -g ${env:RESOURCE_GROUP} --system-topic-name ${env:UNPROCESSED_PDF_SYSTEM_TOPIC_NAME} --endpoint-type webhook --endpoint $endpointUrl --included-event-types Microsoft.Storage.BlobCreated --subject-begins-with $filter

Write-Output "Created blob event grid subscription successfully."
