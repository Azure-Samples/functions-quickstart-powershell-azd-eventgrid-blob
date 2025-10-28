# Script to install Azure PowerShell modules for Flex Consumption deployment
# This should be run before deployment to include modules with the function app

Write-Host "Installing Azure PowerShell modules for Flex Consumption..."

# Create Modules directory if it doesn't exist
$modulesPath = Join-Path $PSScriptRoot "Modules"
if (!(Test-Path $modulesPath)) {
    New-Item -ItemType Directory -Path $modulesPath -Force
    Write-Host "Created Modules directory at: $modulesPath"
}

# Install required modules
$requiredModules = @(
    "Az.Storage",
    "Az.Accounts"
)

foreach ($module in $requiredModules) {
    Write-Host "Installing module: $module"
    try {
        Save-Module -Name $module -Path $modulesPath -Repository PSGallery -Force
        Write-Host "Successfully installed: $module"
    } catch {
        Write-Error "Failed to install $module : $_"
    }
}

Write-Host "Module installation complete. Modules are now included in the function app package."