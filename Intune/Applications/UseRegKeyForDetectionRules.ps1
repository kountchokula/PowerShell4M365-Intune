<#
.DESCRIPTION
  This script component can be added to any application deployment to create registry entries for use as detection rules.
  It will create a key under HKLM:\Software with the $orgName variable. A second key will be created under HKLM:\Software\$orgName
  with the name of your application. Finally, a single value will be created called "Version" - you can use the $version variable
  to increment the deployment versions easily.
#>
#############################################################
## Script Variables
#############################################################
# Org Name for registry key folder
$orgName = "MyCompany"
# Registry key for deployment
$key = "ApplicationName"
# Deployment version
$version = "1.0"

# DO NOT CHANGE ANYTHING BELOW THIS LINE OR SCRIPT WILL NOT WORK

#############################################################
## Set registry key version
#############################################################
# Check for HKLM:\Software\Talkiatry reg key, create if does not exist
$orgKey = "HKLM:\Software\$($orgName)"
$orgKeyExists = Test-Path $orgKey
if (!$orgExists) {
    New-Item -Path "HKLM:\Software" -Name $orgName
    Write-Output "$($orgKey) registry key created"
}
else {
    Write-Output "$($orgKey) registry key exists"
}
# Check for application deployment key, create if does not exist
$appKey = $orgKey + "\" + $key
$appKeyExists = Test-Path $appKey
if (!$appKeyExists) { 
    New-Item -Path $orgKey -Name $key
    Write-Output "$($appKey) registry key created"
}
else {
    Write-Output "$($appKey) registry key exists"
}
# Set application deployment key version, create if does not exist
$versionKey = Get-ItemProperty -Path $appKey -Name "Version"
$versionKeyExists = Test-Path $versionKey
if (!$versionKeyExists) {
    New-ItemProperty -Path $appKey -Name "Version" -PropertyType "String" -Value $version
    Write-Output "Version key value created"
}
else {
    if ($versionKey.Version -ne $version) {
        # Update value to latest version
        Set-ItemProperty -Path $appKey -Name "Version" -Value $version
        Write-Output "Version key value updated to $($version)"
    }
    else {
    Write-Output "Version key value correctly set"
    }
}
