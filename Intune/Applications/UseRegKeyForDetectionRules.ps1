<#
.DESCRIPTION
  This script component can be added to any Intune application deployment package to create registry entries for use as detection rules.
  It will create a key under HKLM:\SOFTWARE with the $orgName variable. A second key will be created under HKLM:\SOFTWARE\$orgName
  with the name of your application. Finally, a single value will be created called $keyName - you can use the $keyValue variable
  to increment the deployment versions easily.
#>
#############################################################
## Set registry key version for app detection
#############################################################	
# Variables - change these for app and version as needed

# Org Name for registry key folder
$orgName = "MyCompany"
# App name for reg key
$app = "ApplicationName"
# Key to set for app detection check
$keyName = "KeyName"
# Key type
$keyType = "KeyType"
# Key value
$keyValue = "1.0"

#############################################################
## DO NOT CHANGE ANYTHING BELOW THIS LINE
#############################################################
# Check for existing org reg key
$basePath = "HKLM:\SOFTWARE\" + $orgName
if (!(Test-Path $basePath)) {
	# Create if not found
  New-Item -Path "HKLM:\SOFTWARE" -Name $orgName
	Write-Output "Created '$($basePath)' registry key"
}
# Check for existing application reg key
$appKey = $basePath + "\" + $app
if (!(Test-Path $appKey)) {
  # Create if not found
	New-Item -Path $basePath -Name $app
	Write-Output "Created '$($appKey)' registry key"
}
# Check for detection key (and the correct value)
$detectionKey = Get-ItemProperty -Path $appKey -Name $keyName
if (!$detectionKey) {
  # Create if not found
  New-ItemProperty -Path $appKey -Name $keyName -PropertyType $keyType -Value $keyValue
  Write-Output "Created and set '$($keyName)' value in '$($appKey)' and set it to '$($keyValue)'"
}
else {
  if ($detectionKey.$keyName -ne $keyValue) {
    # Update value to latest version
		Set-ItemProperty -Path $appKey -Name $keyName -Value $keyValue
		Write-Output "'$($keyName)' value updated to '$($keyValue)'"
  }
  else {
    # Output successful verification of correct key/value
		Write-Output "'$($keyName)' value correctly set"
  }
}
