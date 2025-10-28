#!/bin/bash
commands=("az" "func")

for cmd in "${commands[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd command is not available, check pre-requisites in README.md"
    exit 1
  fi
done

echo "Loading azd .env file from current environment..."

while IFS='=' read -r key value; do
    value=$(echo "$value" | sed 's/^"//' | sed 's/"$//')
    export "$key=$value"
done <<EOF
$(azd env get-values)
EOF

echo "Installing PowerShell modules for Flex Consumption deployment..."
cd ./src

# Install Azure PowerShell modules if not already present
if [ ! -d "Modules" ] || [ -z "$(ls -A Modules 2>/dev/null)" ]; then
    echo "Modules directory not found or empty. Installing Azure PowerShell modules..."
    
    # Check if PowerShell Core is available
    if command -v pwsh >/dev/null 2>&1; then
        pwsh ./install-modules.ps1
    else
        echo "Warning: PowerShell Core (pwsh) not found."
        echo "Please install PowerShell modules manually:"
        echo "1. Install PowerShell Core: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell"
        echo "2. Run: pwsh ./install-modules.ps1"
        echo "3. Re-run: azd up"
        echo ""
        echo "Alternatively, use a system with PowerShell Core installed for deployment."
        exit 1
    fi
else
    echo "Modules directory found with content. Skipping module installation."
fi

func azure functionapp publish $AZURE_FUNCTION_APP_NAME --powershell

echo "Deployed successfully. Creating event grid subscription."

#Get the function blobs_extension key
blobs_extension=$(az functionapp keys list -n ${AZURE_FUNCTION_APP_NAME} -g ${RESOURCE_GROUP} --query "systemKeys.blobs_extension" -o tsv)

# Build the endpoint URL with the function name and extension key and create the event subscription
endpointUrl="https://${AZURE_FUNCTION_APP_NAME}.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.ProcessBlobUpload&code=${blobs_extension}"
filter="/blobServices/default/containers/${UNPROCESSED_PDF_CONTAINER_NAME}"

az eventgrid system-topic event-subscription create -n "unprocessed-pdf-topic-subscription" -g "${RESOURCE_GROUP}" --system-topic-name "${UNPROCESSED_PDF_SYSTEM_TOPIC_NAME}" --endpoint-type "webhook" --endpoint "$endpointUrl" --included-event-types "Microsoft.Storage.BlobCreated" --subject-begins-with "$filter" 

echo "Created blob event grid subscription successfully."

