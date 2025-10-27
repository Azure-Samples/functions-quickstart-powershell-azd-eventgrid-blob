using namespace System.Net

# Input bindings are passed in via param block.
param($InputBlob, $TriggerMetadata)

# Write an information log with the current time.
Write-Host "PowerShell Blob Trigger (using Event Grid) processed blob"

$blobName = $TriggerMetadata.Name
$fileSize = $InputBlob.Length

Write-Host "Name: $blobName"
Write-Host "Size: $fileSize bytes"

try {
    # Copy to processed container - simple demonstration of an async operation
    Copy-ToProcessedContainer -BlobData $InputBlob -BlobName "processed_$blobName"
    
    Write-Host "PDF processing complete for $blobName"
} catch {
    Write-Error "Error processing blob $blobName : $_"
    throw
}

function Copy-ToProcessedContainer {
    param(
        [byte[]]$BlobData,
        [string]$BlobName
    )
    
    Write-Host "Starting copy operation for $BlobName"
    
    try {
        # Get storage account context using environment variables
        $storageAccountName = $env:PDFProcessorSTORAGE__accountName
        $connectionString = $env:PDFProcessorSTORAGE
        
        # Check if running locally with Azurite
        if ($connectionString -eq "UseDevelopmentStorage=true") {
            # For local development with Azurite
            Write-Host "Using Azurite for local development"
            $context = New-AzStorageContext -ConnectionString $connectionString
        } elseif ($storageAccountName) {
            # For Azure with managed identity
            Write-Host "Using managed identity for storage access with account: $storageAccountName"
            $context = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
        } else {
            throw "No valid storage configuration found. Check PDFProcessorSTORAGE settings."
        }
        
        # Convert byte array to temporary file for upload
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            [System.IO.File]::WriteAllBytes($tempFile, $BlobData)
            
            # Upload blob to processed-pdf container
            $result = Set-AzStorageBlobContent -Context $context `
                -Container "processed-pdf" `
                -Blob $BlobName `
                -File $tempFile `
                -BlobType Block `
                -Force
            
            Write-Host "Successfully copied $BlobName to processed-pdf container"
            return $result
        }
        finally {
            # Clean up temporary file
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force
            }
        }
    } catch {
        Write-Error "Failed to copy $BlobName to processed container: $_"
        throw
    }
}